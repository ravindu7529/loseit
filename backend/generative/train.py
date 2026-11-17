"""
Fine-tunes distilgpt2 on the Sri Lankan recipe dataset so it can generate
brand-new recipes. Run generative/prepare_data.py first. Single stage, sized
to finish in a few minutes on a laptop CPU/MPS backend -- the dataset is only
300 recipes (oversampled with shuffled tags), so there is no need for a large
model or a long schedule.

    .venv/bin/python3 generative/train.py            # full run
    .venv/bin/python3 generative/train.py --smoke-test  # tiny correctness check
"""
import argparse
import json
import math
from pathlib import Path

import torch
from datasets import Dataset
from transformers import (
    GPT2LMHeadModel,
    GPT2Tokenizer,
    Trainer,
    TrainerCallback,
    TrainingArguments,
)


class NanGuardCallback(TrainerCallback):
    """Last-resort safety net: aborts if a non-finite value still reaches the
    logs despite SkipNanTrainer below (i.e. real, sustained instability
    rather than one bad batch). Cheap insurance against silently training on
    dead weights for several minutes before anyone notices."""

    def on_log(self, args, state, control, logs=None, **kwargs):
        if logs and any(isinstance(v, float) and math.isnan(v) for v in logs.values()):
            raise RuntimeError(f"NaN detected in training logs at step {state.global_step}: {logs}")


class SkipNanTrainer(Trainer):
    """Skips the optimizer update for any micro-batch whose loss is
    non-finite, instead of letting one bad batch permanently corrupt the
    model (once a NaN gradient is applied, every weight it touches stays NaN
    forever). Aborts if it sees too many in a row, since that would mean real
    instability rather than an isolated bad example."""

    _consecutive_bad_windows = 0
    _last_bad_step = None

    def training_step(self, model, inputs, num_items_in_batch=None):
        loss = super().training_step(model, inputs, num_items_in_batch)
        if not torch.isfinite(loss):
            step = self.state.global_step
            if step != self._last_bad_step:
                self._consecutive_bad_windows += 1
                self._last_bad_step = step
            if self._consecutive_bad_windows > 2:
                raise RuntimeError(
                    f"2+ consecutive fully-bad accumulation windows around step {step} -- "
                    "this looks like real instability, not an isolated bad batch."
                )
            for p in model.parameters():
                if p.grad is not None:
                    p.grad.zero_()
            print(f"  [skip] non-finite loss at step {step}, zeroed gradient")
            return torch.zeros_like(loss)
        if self.state.global_step != self._last_bad_step:
            self._consecutive_bad_windows = 0
        return loss


HERE = Path(__file__).resolve().parent
DATA_DIR = HERE / "data"
OUT_DIR = HERE / "outputs"
FINAL_DIR = OUT_DIR / "final_model"

BASE_MODEL = "distilgpt2"
# 128 was tried and measured LESS stable than 256 at this learning rate: a
# smaller block concentrates the <|startofrecipe|>/<|endofrecipe|> special
# tokens (added fresh, at the very start of every example) into a larger
# fraction of each block, which sharpens the gradient on their still-raw
# embedding rows enough to blow up (grad_norm in the hundreds of thousands,
# NaN loss by step ~70). 256 dilutes that signal with more ordinary context
# per block and ran clean end-to-end with zero skipped steps.
BLOCK_SIZE = 256

EPOCHS = 6  # fewer measured undertrained (292 steps: model never left generic-English mode).
            # 6 epochs x 4x oversample (~587 steps) is the validated floor that actually
            # learns the recipe structure -- verify with generate.py, not eval_loss alone.
LEARNING_RATE = 5e-5
WARMUP_STEPS = 50


def get_device():
    if torch.backends.mps.is_available():
        return "mps"
    if torch.cuda.is_available():
        return "cuda"
    return "cpu"


def load_jsonl(path):
    with open(path) as f:
        return [json.loads(line)["text"] for line in f]


def build_tokenizer():
    tokenizer = GPT2Tokenizer.from_pretrained(BASE_MODEL)
    tokenizer.add_special_tokens({
        "pad_token": "<|pad|>",
        "additional_special_tokens": ["<|startofrecipe|>", "<|endofrecipe|>"],
    })
    return tokenizer


def tokenize_and_group(texts, tokenizer, block_size=BLOCK_SIZE, batch_size=1000):
    all_ids = []
    for i in range(0, len(texts), batch_size):
        batch = texts[i:i + batch_size]
        enc = tokenizer(batch, add_special_tokens=False)
        for ids in enc["input_ids"]:
            all_ids.extend(ids)
    total_len = (len(all_ids) // block_size) * block_size
    blocks = [all_ids[i:i + block_size] for i in range(0, total_len, block_size)]
    return Dataset.from_dict({"input_ids": blocks, "labels": [b.copy() for b in blocks]})


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--smoke-test", action="store_true", help="tiny run to sanity-check the pipeline")
    parser.add_argument("--device", choices=["auto", "cpu", "mps"], default="auto")
    args = parser.parse_args()

    device = get_device() if args.device == "auto" else args.device
    print(f"Using device: {device}")

    tokenizer = build_tokenizer()

    model = GPT2LMHeadModel.from_pretrained(BASE_MODEL)
    # mean_resizing=True (the default) draws new embedding rows matched to the
    # existing rows' mean/covariance -- important for the tied lm_head output
    # layer. Plain small-random init previously miscalibrated the softmax
    # normalizer for every token position (loss ~42 immediately, before any
    # training at all, vs a healthy ~3.4 with mean_resizing=True).
    model.resize_token_embeddings(len(tokenizer))
    model.to(device)

    train_texts = load_jsonl(DATA_DIR / "train.jsonl")
    val_texts = load_jsonl(DATA_DIR / "val.jsonl")

    epochs, warmup_steps = EPOCHS, WARMUP_STEPS
    if args.smoke_test:
        train_texts = train_texts[:120]
        val_texts = val_texts[:20]
        epochs = 1

    train_ds = tokenize_and_group(train_texts, tokenizer)
    val_ds = tokenize_and_group(val_texts, tokenizer)
    print(f"train blocks: {len(train_ds)}  val blocks: {len(val_ds)}")

    training_args = TrainingArguments(
        output_dir=str(OUT_DIR / "checkpoints"),
        overwrite_output_dir=True,
        num_train_epochs=epochs,
        per_device_train_batch_size=4,
        per_device_eval_batch_size=4,
        gradient_accumulation_steps=4,
        save_strategy="no",       # only save the final model explicitly below
        logging_steps=10,         # short interval so NanGuardCallback catches divergence quickly
        learning_rate=LEARNING_RATE,
        warmup_steps=warmup_steps,
        fp16=False,               # not reliable on MPS; stay in fp32
        dataloader_num_workers=0,
        report_to="none",
        use_mps_device=(device == "mps"),
        max_grad_norm=0.5,        # tight clipping to avoid destabilizing the newly-added special tokens
        logging_nan_inf_filter=False,  # don't hide nan/inf losses from the log -- we need to see them
        adam_epsilon=1e-6,        # default 1e-8 is too aggressive for the sparsely-updated special-
                                   # token embedding rows -- see resize_token_embeddings comment above
    )

    trainer = SkipNanTrainer(
        model=model, args=training_args, train_dataset=train_ds, eval_dataset=val_ds,
        callbacks=[NanGuardCallback()],
    )
    trainer.train()

    eval_results = trainer.evaluate()
    ppl = math.exp(eval_results["eval_loss"])
    print(f"eval_loss={eval_results['eval_loss']:.4f}  perplexity={ppl:.2f}")

    FINAL_DIR.mkdir(parents=True, exist_ok=True)
    trainer.save_model(str(FINAL_DIR))
    tokenizer.save_pretrained(str(FINAL_DIR))
    print(f"Saved to {FINAL_DIR}")

    print("\nDone. Generate with: .venv/bin/python3 generative/generate.py \"something spicy\"")


if __name__ == "__main__":
    main()
