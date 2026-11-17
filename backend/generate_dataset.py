"""
generate_dataset.py

Builds a labelled training dataset for the LoseIt recommendation model.

WHY SYNTHETIC DATA (explain this in Chapter 5 / Data Selection):
The app has no real users yet, so there is no interaction history
(ratings, meal logs, accept/reject signals) to train a collaborative-
filtering model on - this is the classic "cold-start problem" in
recommender systems. To still produce a genuinely trained model, we
simulate a realistic population of users and label each (user, recipe)
pair using a defined satisfaction function grounded in nutrition
science (BMR/TDEE) plus a taste-preference signal. This is a standard
bootstrapping technique for recommenders before real usage data exists,
sometimes called "weak supervision" or "programmatic labelling".

IMPORTANT - this label function is DELIBERATELY richer than the existing
rule-based baseline (see baseline_score() below): it adds a spice-
preference matching term and stochastic noise that the hand-built
baseline formula does not model. This is what gives the trained model
something genuine to learn, and is what makes the baseline-vs-trained-
model comparison in Chapter 6 meaningful rather than circular.
"""

import json
import numpy as np
import pandas as pd

RNG_SEED = 42
N_USERS = 2000

np.random.seed(RNG_SEED)

# ---------------------------------------------------------------
# Load recipe data
# ---------------------------------------------------------------
with open("data/recipes.json") as f:
    recipes = json.load(f)

recipes_df = pd.DataFrame(recipes)
print(f"Loaded {len(recipes_df)} recipes")

ACTIVITY_LEVELS = ["Sedentary", "Light", "Moderate", "Active"]
ACTIVITY_MULTIPLIER = {"Sedentary": 1.2, "Light": 1.375, "Moderate": 1.55, "Active": 1.725}
DIETARY_PREFS = ["Non-Vegetarian", "Pescatarian", "Vegetarian", "Vegan"]
SPICE_LEVELS = ["Mild", "Medium", "Hot"]
SPICE_RANK = {"Mild": 0, "Medium": 1, "Hot": 2}

# ---------------------------------------------------------------
# 1. Generate a synthetic user population
# ---------------------------------------------------------------
def generate_users(n):
    users = []
    for _ in range(n):
        gender = np.random.choice(["Male", "Female"])
        age = int(np.random.randint(18, 65))

        if gender == "Male":
            height_cm = np.random.normal(172, 7)
        else:
            height_cm = np.random.normal(160, 6)
        height_cm = float(np.clip(height_cm, 145, 195))

        # Weight-loss-app users skew toward higher BMI (overweight range)
        bmi = np.random.uniform(24, 34)
        weight_kg = round(bmi * (height_cm / 100) ** 2, 1)

        # Target weight: aiming to lose 3-15kg, not below a healthy BMI ~20
        loss_goal = np.random.uniform(3, 15)
        min_healthy_weight = 20 * (height_cm / 100) ** 2
        target_weight_kg = max(round(weight_kg - loss_goal, 1), round(min_healthy_weight, 1))

        activity_level = np.random.choice(
            ACTIVITY_LEVELS, p=[0.35, 0.30, 0.25, 0.10]  # skews sedentary/light
        )
        dietary_pref = np.random.choice(
            DIETARY_PREFS, p=[0.55, 0.15, 0.22, 0.08]  # rough SL population skew
        )
        spice_pref = np.random.choice(SPICE_LEVELS, p=[0.25, 0.45, 0.30])

        users.append({
            "age": age, "gender": gender, "height_cm": height_cm,
            "weight_kg": weight_kg, "target_weight_kg": target_weight_kg,
            "activity_level": activity_level, "dietary_pref": dietary_pref,
            "spice_pref": spice_pref,
        })
    return pd.DataFrame(users)


def bmr(row):
    base = 10 * row["weight_kg"] + 6.25 * row["height_cm"] - 5 * row["age"]
    return base + 5 if row["gender"] == "Male" else base - 161


def daily_calorie_target(row):
    maintenance = row["bmr"] * ACTIVITY_MULTIPLIER[row["activity_level"]]
    target = maintenance - 500
    safe_min = 1500 if row["gender"] == "Male" else 1200
    return max(target, safe_min)


users_df = generate_users(N_USERS)
users_df["bmr"] = users_df.apply(bmr, axis=1)
users_df["daily_calorie_target"] = users_df.apply(daily_calorie_target, axis=1)
users_df["per_meal_target"] = users_df["daily_calorie_target"] * 0.30
users_df["bmi"] = users_df["weight_kg"] / ((users_df["height_cm"] / 100) ** 2)
users_df["user_id"] = range(len(users_df))

print(f"Generated {len(users_df)} synthetic user profiles")


# ---------------------------------------------------------------
# 2. Hard dietary-compatibility filter (never learned/approximated -
#    a safety-relevant constraint applied outside the model, same as
#    the existing rule-based system)
# ---------------------------------------------------------------
def diet_compatible(user_pref, recipe_tag):
    if user_pref == "Vegan":
        return recipe_tag == "Vegan"
    if user_pref == "Vegetarian":
        return recipe_tag in ("Vegan", "Vegetarian")
    if user_pref == "Pescatarian":
        return recipe_tag in ("Vegan", "Vegetarian", "Pescatarian")
    return True  # Non-Vegetarian: everything eligible


# ---------------------------------------------------------------
# 3. Label function (the "ground truth" the model learns to predict)
# ---------------------------------------------------------------
# Compatibility is expressed as an integer rank so it can be checked
# with a single vectorised comparison instead of a slow per-row loop.
DIET_RANK = {"Vegan": 0, "Vegetarian": 1, "Pescatarian": 2, "Non-Vegetarian": 3}


def spice_match_component(user_rank, recipe_rank):
    diff = np.abs(user_rank - recipe_rank)
    return np.where(diff == 0, 100.0, np.where(diff == 1, 50.0, 0.0))


# ---------------------------------------------------------------
# 4. Build (user, recipe) pairs for all dietary-eligible combinations
#    using a vectorised cross join + boolean filter (fast even at
#    hundreds of thousands of rows - avoids slow row-by-row Python loops)
# ---------------------------------------------------------------
users_df["_pref_rank"] = users_df["dietary_pref"].map(DIET_RANK)
recipes_df["_tag_rank"] = recipes_df["Dietary_Tag"].map(DIET_RANK)
recipes_df["_spice_rank"] = recipes_df["Spice_Level"].map(SPICE_RANK)
users_df["_spice_rank"] = users_df["spice_pref"].map(SPICE_RANK)

users_df["_key"] = 1
recipes_df["_key"] = 1
pairs = users_df.merge(recipes_df, on="_key", suffixes=("", "_r")).drop(columns="_key")

# Hard dietary filter: recipe tag rank must be <= the user's preference rank
pairs = pairs[pairs["_tag_rank"] <= pairs["_pref_rank"]].reset_index(drop=True)
print(f"After dietary filtering: {len(pairs):,} eligible (user, recipe) pairs")

rng = np.random.default_rng(RNG_SEED)

calorie_component = np.clip(
    100 - np.abs(pairs["Calories_kcal"] - pairs["per_meal_target"]) / pairs["per_meal_target"] * 100,
    0, 100,
)
protein_component = np.clip(pairs["Protein_g"] / 40 * 100, 0, 100)
spice_component = spice_match_component(pairs["_spice_rank"].values, pairs["_spice_rank_r"].values)
noise = rng.normal(0, 4, size=len(pairs))

label = np.clip(
    0.5 * calorie_component + 0.3 * protein_component + 0.2 * spice_component + noise,
    0, 100,
)

# Rule-based baseline score, recreated from the existing Dart formula
# (recipe_service.dart) for a like-for-like comparison. Deliberately
# does NOT use spice preference - that gap is what the trained model
# is expected to close.
baseline_calorie_fit = np.clip(
    100 - np.abs(pairs["Calories_kcal"] - pairs["per_meal_target"]) / pairs["per_meal_target"] * 100,
    0, 100,
)
baseline_protein_bonus = np.clip(pairs["Protein_g"], 0, 40)
baseline_score = baseline_calorie_fit * 0.7 + baseline_protein_bonus * 0.75

dataset = pd.DataFrame({
    "user_id": pairs["user_id"],
    "age": pairs["age"],
    "gender": pairs["gender"],
    "height_cm": pairs["height_cm"],
    "weight_kg": pairs["weight_kg"],
    "bmi": pairs["bmi"],
    "activity_level": pairs["activity_level"],
    "spice_pref": pairs["spice_pref"],
    "daily_calorie_target": pairs["daily_calorie_target"],
    "per_meal_target": pairs["per_meal_target"],
    "recipe_id": pairs["Recipe_ID"],
    "recipe_calories": pairs["Calories_kcal"],
    "recipe_protein": pairs["Protein_g"],
    "recipe_carbs": pairs["Carbs_g"],
    "recipe_fat": pairs["Fat_g"],
    "recipe_fiber": pairs["Fiber_g"],
    "recipe_prep_time": pairs["Prep_Time_Min"],
    "recipe_spice_level": pairs["Spice_Level"],
    "recipe_food_group": pairs["Food_Group"],
    "recipe_meal_type": pairs["Meal_Type"],
    "baseline_score": baseline_score,
    "label": label,
})

print(f"Built {len(dataset):,} (user, recipe) training pairs")
dataset.to_csv("outputs/training_dataset.csv", index=False)
print("Saved outputs/training_dataset.csv")
print(dataset[["label", "baseline_score"]].describe())
