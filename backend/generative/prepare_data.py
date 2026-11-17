"""
Stage 0 of the generative recipe pipeline: turn the Sri Lankan recipe
database into the JSONL text format train.py consumes. Run this once
before train.py.

    .venv/bin/python3 generative/prepare_data.py
"""
import json
import random
from pathlib import Path

import pandas as pd
from sklearn.model_selection import train_test_split

random.seed(42)

HERE = Path(__file__).resolve().parent
DATA_DIR = HERE / "data"
SRILANKAN_XLSX = HERE.parent.parent.parent / "Sri_Lankan_Recipe_Database_updated.xlsx"

OVERSAMPLE_FACTOR = 4  # repeat the 300 recipes with shuffled tag order for more gradient steps


def weight_loss_suitability(cal):
    if cal < 200:
        return "Low-Cal"
    elif cal < 400:
        return "Moderate"
    return "High-Cal"


def format_srilankan_row(row, shuffle_tags=False):
    tag_fields = ["Category", "Food_Group", "Dietary_Tag", "Meal_Type", "Spice_Level", "Weight_Loss_Suitability"]
    tags = []
    for field in tag_fields:
        v = str(row[field]).strip().lower()
        if v and v != "nan" and v not in tags:
            tags.append(v)
    if shuffle_tags:
        random.shuffle(tags)

    lines = ["<|startofrecipe|>", "tags: " + ", ".join(tags), "title: " + str(row["Recipe_Name"]).strip()]
    lines.append("ingredients:")
    lines.append(str(row["Ingredients_Full"]).strip())
    lines.append("steps:")
    lines.append(str(row["Cooking_Steps"]).strip())
    lines.append(
        "nutrition: {:.0f} kcal, {:.1f}g protein, {:.1f}g carbs, {:.1f}g fat, {:.1f}g fiber".format(
            row["Calories_kcal"], row["Protein_g"], row["Carbs_g"], row["Fat_g"], row["Fiber_g"]
        )
    )
    desc = str(row["Short_Description"]).strip()
    if desc and desc.lower() != "nan":
        lines.append("description: " + desc)
    lines.append("<|endofrecipe|>")
    return "\n".join(lines)


def write_jsonl(path, texts):
    with open(path, "w") as f:
        for t in texts:
            f.write(json.dumps({"text": t}) + "\n")


def main():
    DATA_DIR.mkdir(parents=True, exist_ok=True)

    print(f"Loading Sri Lankan dataset from {SRILANKAN_XLSX}")
    sl_df = pd.read_excel(SRILANKAN_XLSX, sheet_name="Recipes")
    sl_df["Weight_Loss_Suitability"] = sl_df["Calories_kcal"].apply(weight_loss_suitability)

    texts = []
    for _ in range(OVERSAMPLE_FACTOR):
        texts.extend(sl_df.apply(lambda r: format_srilankan_row(r, shuffle_tags=True), axis=1).tolist())
    random.shuffle(texts)
    print(f"{len(sl_df)} recipes x {OVERSAMPLE_FACTOR} (shuffled tags) = {len(texts)} training examples")

    train_texts, val_texts = train_test_split(texts, test_size=0.1, random_state=42)
    write_jsonl(DATA_DIR / "train.jsonl", train_texts)
    write_jsonl(DATA_DIR / "val.jsonl", val_texts)
    print(f"Wrote train.jsonl ({len(train_texts)}) / val.jsonl ({len(val_texts)})")

    # ---- Novelty-check reference (used by generate.py) ----
    titles = set(sl_df["Recipe_Name"].str.lower().str.strip())
    ingredient_sets = [
        {line.strip("- ").lower() for line in str(row).split("\n") if line.strip()}
        for row in sl_df["Ingredients_Full"]
    ]
    import pickle
    with open(DATA_DIR / "novelty_reference.pkl", "wb") as f:
        pickle.dump({"titles": titles, "ingredient_sets": ingredient_sets}, f)
    print("Wrote novelty_reference.pkl")

    print("\nDone. Next: .venv/bin/python3 generative/train.py")


if __name__ == "__main__":
    main()
