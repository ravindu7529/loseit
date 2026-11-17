"""
Load the fine-tuned Sri Lankan recipe model and generate brand-new recipes
from a mood/craving.

    .venv/bin/python3 generative/generate.py "something sweet"
    .venv/bin/python3 generative/generate.py "spicy kottu" --num 3
"""
import argparse
import pickle
import re
from pathlib import Path

import torch
from transformers import GPT2LMHeadModel, GPT2Tokenizer

HERE = Path(__file__).resolve().parent
FINAL_DIR = HERE / "outputs" / "final_model"
NOVELTY_REF = HERE / "data" / "novelty_reference.pkl"

MOOD_KEYWORDS = {
    "sweet": ["dessert"],
    "dessert": ["dessert"],
    "spicy": ["hot"],
    "hot": ["hot"],
    "mild": ["mild"],
    "medium spice": ["medium"],
    "healthy": ["low-cal"],
    "light": ["low-cal"],
    "diet": ["low-cal"],
    "lose weight": ["low-cal"],
    "low calorie": ["low-cal"],
    "vegetarian": ["vegetarian"],
    "vegan": ["vegan"],
    "breakfast": ["breakfast"],
    "lunch": ["lunch"],
    "dinner": ["dinner"],
    "snack": ["snack", "short eats"],
    "short eats": ["short eats"],
    "soup": ["soup"],
    "seafood": ["pescatarian"],
    "fish": ["pescatarian"],
    "kottu": ["kottu"],
    "biryani": ["biryani"],
    "sambol": ["sambol", "condiment / sambol"],
    "pickle": ["achcharu (pickle)"],
    "rice": ["rice & curry"],
    "curry": ["curry"],
    "hoppers": ["bread & hoppers"],
    "roti": ["bread & hoppers"],
    "beverage": ["beverage"],
    "drink": ["beverage"],
}


def build_prompt(mood_text):
    mood_lower = mood_text.lower()
    matched = []
    for kw, tags in MOOD_KEYWORDS.items():
        if kw in mood_lower:
            for t in tags:
                if t not in matched:
                    matched.append(t)
    if not matched:
        matched = [mood_lower.strip()]
    return f"<|startofrecipe|>\ntags: {', '.join(matched)}\ntitle:"


def parse_generated_recipe(text):
    text = text.split("<|endofrecipe|>")[0]
    text = text.replace("<|startofrecipe|>", "").strip()

    def extract(label, next_labels):
        pattern = rf"{label}:\s*(.*?)(?=(?:{'|'.join(next_labels)}):|$)"
        m = re.search(pattern, text, re.DOTALL)
        return m.group(1).strip() if m else ""

    labels_order = ["tags", "title", "ingredients", "steps", "nutrition", "description"]
    result = {}
    for i, label in enumerate(labels_order):
        result[label] = extract(label, labels_order[i + 1:])
    return result


def generate_recipe(mood_text, model, tokenizer, device, num_return_sequences=1,
                     max_new_tokens=220, temperature=0.9, top_p=0.92, top_k=50):
    prompt = build_prompt(mood_text)
    input_ids = tokenizer(prompt, return_tensors="pt").input_ids.to(device)
    outputs = model.generate(
        input_ids,
        max_new_tokens=max_new_tokens,
        do_sample=True,
        temperature=temperature,
        top_p=top_p,
        top_k=top_k,
        no_repeat_ngram_size=3,
        repetition_penalty=1.2,
        num_return_sequences=num_return_sequences,
        pad_token_id=tokenizer.pad_token_id,
    )
    return [parse_generated_recipe(tokenizer.decode(o, skip_special_tokens=False)) for o in outputs]


def print_recipe(r):
    print("TITLE:", r.get("title", "").strip())
    print("TAGS:", r.get("tags", "").strip())
    print("INGREDIENTS:\n" + r.get("ingredients", "").strip())
    if r.get("steps"):
        print("STEPS:\n" + r["steps"].strip())
    if r.get("nutrition"):
        print("NUTRITION:", r["nutrition"].strip())
    if r.get("description"):
        print("DESCRIPTION:", r["description"].strip())
    print("-" * 60)


def ingredient_set_from_text(text):
    return {line.strip("- ").lower() for line in text.split("\n") if line.strip()}


def novelty_report(recipe, reference):
    title = recipe.get("title", "").strip().lower()
    exact_title_match = title in reference["titles"]
    gen_ingredients = ingredient_set_from_text(recipe.get("ingredients", ""))

    def jaccard(a, b):
        if not a or not b:
            return 0.0
        return len(a & b) / len(a | b)

    best_overlap = max((jaccard(gen_ingredients, s) for s in reference["ingredient_sets"]), default=0.0)
    print(f"  Exact title seen in training data: {exact_title_match}")
    print(f"  Highest ingredient-set overlap with any training recipe: {best_overlap:.2%}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mood", nargs="?", default="something sweet", help='e.g. "something sweet", "spicy and healthy"')
    parser.add_argument("--num", type=int, default=1)
    args = parser.parse_args()

    if not FINAL_DIR.exists():
        raise SystemExit(f"No trained model found at {FINAL_DIR}. Run prepare_data.py then train.py first.")

    device = "mps" if torch.backends.mps.is_available() else ("cuda" if torch.cuda.is_available() else "cpu")
    tokenizer = GPT2Tokenizer.from_pretrained(str(FINAL_DIR))
    model = GPT2LMHeadModel.from_pretrained(str(FINAL_DIR)).to(device)
    model.eval()

    reference = None
    if NOVELTY_REF.exists():
        with open(NOVELTY_REF, "rb") as f:
            reference = pickle.load(f)

    print(f"Mood: {args.mood!r}")
    for r in generate_recipe(args.mood, model, tokenizer, device, num_return_sequences=args.num):
        print_recipe(r)
        if reference:
            novelty_report(r, reference)
            print("-" * 60)


if __name__ == "__main__":
    main()
