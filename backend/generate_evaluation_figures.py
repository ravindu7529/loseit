"""
generate_evaluation_figures.py

Generates Figure 6.2 (predicted vs actual suitability scatter) and
Figure 6.3 (residual distribution) for the multi-layer perceptron,
using the ACTUAL held-out test partition -- no synthetic stand-in data.
"""

import os
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import joblib

plt.rcParams["font.family"] = "serif"   # falls back gracefully if Times New Roman isn't installed

NUMERIC_FEATURES = [
    "age", "height_cm", "weight_kg", "bmi", "daily_calorie_target",
    "per_meal_target", "recipe_calories", "recipe_protein", "recipe_carbs",
    "recipe_fat", "recipe_fiber", "recipe_prep_time",
]
CATEGORICAL_FEATURES = [
    "gender", "activity_level", "spice_pref", "recipe_spice_level",
    "recipe_food_group", "recipe_meal_type",
]
TARGET = "label"
RNG_SEED = 42


def get_test_split(dataset_path="outputs/training_dataset.csv"):
    df = pd.read_csv(dataset_path)
    print(f"Loaded {len(df):,} rows from {dataset_path}")
    
    unique_users = df["user_id"].unique()
    rng = np.random.default_rng(RNG_SEED)
    rng.shuffle(unique_users)

    split_idx = int(len(unique_users) * 0.8)
    test_users = set(unique_users[split_idx:])

    test_df = df[df["user_id"].isin(test_users)].reset_index(drop=True)

    max_test_rows = int(os.environ.get("MAX_TEST_ROWS", 30_000))
    if max_test_rows > 0 and len(test_df) > max_test_rows:
        test_df = test_df.sample(n=max_test_rows, random_state=RNG_SEED).reset_index(drop=True)

    print(f"Test split: {len(test_df):,} rows from {len(test_users)} users")
    X_test = test_df[NUMERIC_FEATURES + CATEGORICAL_FEATURES]
    y_test = test_df[TARGET]
    return X_test, y_test


def plot_fig_6_2(y_true, y_pred, out_path="outputs/fig_6_2_pred_vs_actual.png"):
    """Predicted vs actual suitability scatter with the identity line overlaid."""
    fig, ax = plt.subplots(figsize=(6, 5), dpi=200)

    ax.scatter(y_true, y_pred, s=10, alpha=0.35, color="#2E5339", edgecolors="none")

    lo = min(np.min(y_true), np.min(y_pred))
    hi = max(np.max(y_true), np.max(y_pred))
    ax.plot([lo, hi], [lo, hi], color="#8C2F1B", linewidth=1.5, linestyle="--", label="Identity (y = x)")

    ax.set_xlabel("Actual suitability score")
    ax.set_ylabel("Predicted suitability score")
    ax.set_title("Figure 6.2 — Predicted vs actual suitability (MLP, test partition)")
    ax.legend(loc="upper left", frameon=False)
    ax.set_xlim(lo, hi)
    ax.set_ylim(lo, hi)
    fig.tight_layout()
    fig.savefig(out_path, bbox_inches="tight")
    plt.close(fig)
    print(f"Saved {out_path}")


def plot_fig_6_3(y_true, y_pred, out_path="outputs/fig_6_3_residual_distribution.png"):
    """Residual (actual - predicted) distribution histogram."""
    residuals = np.asarray(y_true) - np.asarray(y_pred)

    fig, ax = plt.subplots(figsize=(6, 4.5), dpi=200)
    ax.hist(residuals, bins=40, color="#2E5339", edgecolor="white", alpha=0.85)
    ax.axvline(0, color="#8C2F1B", linewidth=1.5, linestyle="--")

    ax.set_xlabel("Residual (actual − predicted)")
    ax.set_ylabel("Count")
    ax.set_title("Figure 6.3 — Residual distribution (MLP, test partition)")
    fig.tight_layout()
    fig.savefig(out_path, bbox_inches="tight")
    plt.close(fig)
    print(f"Saved {out_path}")

    # Diagnostics for the interpretive paragraph the report asks you to write
    print("\n" + "="*50)
    print("RESIDUAL DIAGNOSTICS & REPORT METRICS")
    print("="*50)
    print(f"Residual mean: {residuals.mean():.3f}  (should be close to 0)")
    print(f"Residual std:  {residuals.std():.3f}")
    print(f"Skew:          {((residuals - residuals.mean())**3).mean() / residuals.std()**3:.3f}")

    # Is error concentrated at the extremes of the score range, or uniform?
    y_true = np.asarray(y_true)
    tertiles = np.quantile(y_true, [1/3, 2/3])
    low_mask  = y_true <= tertiles[0]
    mid_mask  = (y_true > tertiles[0]) & (y_true <= tertiles[1])
    high_mask = y_true > tertiles[1]
    print("\nMAE by actual-score tertile (checks whether error is uniform across the range):")
    print(f"  Low  scores (<= {tertiles[0]:.1f}):  MAE = {np.abs(residuals[low_mask]).mean():.3f}")
    print(f"  Mid  scores:                    MAE = {np.abs(residuals[mid_mask]).mean():.3f}")
    print(f"  High scores (>  {tertiles[1]:.1f}):  MAE = {np.abs(residuals[high_mask]).mean():.3f}")
    print("="*50 + "\n")


if __name__ == "__main__":
    MODEL_PATH = "outputs/loseit_recommender_model.joblib"
    DATASET_PATH = "outputs/training_dataset.csv"

    print(f"Loading model from {MODEL_PATH}...")
    pipeline = joblib.load(MODEL_PATH)
    
    X_test, y_test = get_test_split(DATASET_PATH)

    print("Computing predictions on test split...")
    y_pred = pipeline.predict(X_test)

    plot_fig_6_2(y_test, y_pred, out_path="outputs/fig_6_2_pred_vs_actual.png")
    plot_fig_6_3(y_test, y_pred, out_path="outputs/fig_6_3_residual_distribution.png")
