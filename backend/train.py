"""
train.py

Trains and evaluates the LoseIt recommendation model.

Methodology notes (for Chapter 5 / 6):
- Train/test split is done at the USER level, not the row level. If we
  split individual rows randomly, the same user could appear in both
  the training and test sets (just paired with different recipes),
  which leaks information about that user's label distribution across
  the split and inflates apparent performance. Splitting by user_id
  avoids this.
- Four models are compared (this is the ablation / baseline-comparison
  study for Chapter 6):
    1. Rule-based baseline  - the existing hand-built formula, not
       trained. Included to show what "no ML" achieves.
    2. Linear Regression    - simplest trained model. Shows what a
       model with no non-linearity can capture.
    3. Random Forest        - a strong conventional ML baseline for
       tabular data.
    4. Neural Network (MLP) - the proposed model. hidden_layer_sizes
       and other hyperparameters are documented below for Chapter 5.
"""

import os
import time
import json
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

from sklearn.compose import ColumnTransformer
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler, OneHotEncoder
from sklearn.linear_model import LinearRegression
from sklearn.neighbors import KNeighborsRegressor
from sklearn.ensemble import RandomForestRegressor, GradientBoostingRegressor
from sklearn.neural_network import MLPRegressor
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
import joblib

_t0 = time.time()
def tick(label):
    print(f"[{time.time() - _t0:6.1f}s] {label}", flush=True)

RNG_SEED = 42
np.random.seed(RNG_SEED)

# ---------------------------------------------------------------
# Load data
# ---------------------------------------------------------------
df = pd.read_csv("outputs/training_dataset.csv")
print(f"Loaded {len(df):,} rows")

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

# ---------------------------------------------------------------
# User-level train/test split (see note above)
# ---------------------------------------------------------------
unique_users = df["user_id"].unique()
rng = np.random.default_rng(RNG_SEED)
rng.shuffle(unique_users)

split_idx = int(len(unique_users) * 0.8)
train_users = set(unique_users[:split_idx])
test_users = set(unique_users[split_idx:])

train_df = df[df["user_id"].isin(train_users)].reset_index(drop=True)
test_df = df[df["user_id"].isin(test_users)].reset_index(drop=True)

# Subsample rows to keep training time tractable. The full dataset stays
# on disk in outputs/training_dataset.csv, so the report can quote the
# exact total pair count alongside the subsample actually trained on.
# Override from the shell to train on more (or all) of the data, e.g.
#   MAX_TRAIN_ROWS=0 MAX_TEST_ROWS=0 python3 train.py   # 0 = no cap
MAX_TRAIN_ROWS = int(os.environ.get("MAX_TRAIN_ROWS", 120_000))
MAX_TEST_ROWS = int(os.environ.get("MAX_TEST_ROWS", 30_000))
if MAX_TRAIN_ROWS <= 0:
    MAX_TRAIN_ROWS = len(train_df)
if MAX_TEST_ROWS <= 0:
    MAX_TEST_ROWS = len(test_df)
if len(train_df) > MAX_TRAIN_ROWS:
    train_df = train_df.sample(n=MAX_TRAIN_ROWS, random_state=RNG_SEED).reset_index(drop=True)
if len(test_df) > MAX_TEST_ROWS:
    test_df = test_df.sample(n=MAX_TEST_ROWS, random_state=RNG_SEED).reset_index(drop=True)

print(f"Train: {len(train_df):,} rows from {len(train_users)} users")
print(f"Test:  {len(test_df):,} rows from {len(test_users)} users")
tick("data loaded and split")

X_train = train_df[NUMERIC_FEATURES + CATEGORICAL_FEATURES]
y_train = train_df[TARGET]
X_test = test_df[NUMERIC_FEATURES + CATEGORICAL_FEATURES]
y_test = test_df[TARGET]

preprocessor = ColumnTransformer([
    ("num", StandardScaler(), NUMERIC_FEATURES),
    ("cat", OneHotEncoder(handle_unknown="ignore"), CATEGORICAL_FEATURES),
])

results = {}


def evaluate(name, y_true, y_pred):
    mae = mean_absolute_error(y_true, y_pred)
    rmse = np.sqrt(mean_squared_error(y_true, y_pred))
    r2 = r2_score(y_true, y_pred)
    results[name] = {"MAE": round(mae, 3), "RMSE": round(rmse, 3), "R2": round(r2, 4)}
    print(f"{name:22s}  MAE={mae:6.3f}  RMSE={rmse:6.3f}  R2={r2:.4f}")


# ---------------------------------------------------------------
# 1. Rule-based baseline (not trained)
# ---------------------------------------------------------------
evaluate("Rule-based baseline", y_test, test_df["baseline_score"])
tick("baseline evaluated")

# ---------------------------------------------------------------
# 2. Linear Regression
# ---------------------------------------------------------------
lin_pipeline = Pipeline([
    ("prep", preprocessor),
    ("model", LinearRegression()),
])
lin_pipeline.fit(X_train, y_train)
evaluate("Linear Regression", y_test, lin_pipeline.predict(X_test))
tick("linear regression done")

# ---------------------------------------------------------------
# 3. Random Forest
# ---------------------------------------------------------------
rf_pipeline = Pipeline([
    ("prep", preprocessor),
    ("model", RandomForestRegressor(
        n_estimators=40, max_depth=8, random_state=RNG_SEED, n_jobs=-1)),
])
rf_pipeline.fit(X_train, y_train)
evaluate("Random Forest", y_test, rf_pipeline.predict(X_test))
tick("random forest done")

# ---------------------------------------------------------------
# 4. k-Nearest Neighbors
#    Instance-based ("lazy") learner - no training phase, predicts by
#    averaging the k most similar training examples. Included as a
#    classic, simple-to-explain alternative.
# ---------------------------------------------------------------
knn_pipeline = Pipeline([
    ("prep", preprocessor),
    ("model", KNeighborsRegressor(n_neighbors=15, weights="distance", n_jobs=-1)),
])
knn_pipeline.fit(X_train, y_train)
evaluate("k-Nearest Neighbors", y_test, knn_pipeline.predict(X_test))
tick("knn done")

# ---------------------------------------------------------------
# 5. Gradient Boosting
#    Sequential ensemble - each new tree corrects the previous trees'
#    errors. Often the strongest conventional (non-deep-learning)
#    method for tabular data; included as the toughest baseline for
#    the neural network to beat.
# ---------------------------------------------------------------
gb_pipeline = Pipeline([
    ("prep", preprocessor),
    ("model", GradientBoostingRegressor(
        n_estimators=80, max_depth=3, learning_rate=0.1, random_state=RNG_SEED)),
])
gb_pipeline.fit(X_train, y_train)
evaluate("Gradient Boosting", y_test, gb_pipeline.predict(X_test))
tick("gradient boosting done")

# ---------------------------------------------------------------
# 6. Neural Network (MLP) - the proposed model
#    Architecture: input -> Dense(64, ReLU) -> Dense(32, ReLU) -> output
#    Optimizer: Adam, adaptive learning rate, early stopping on a
#    held-out validation slice of the training set to prevent overfitting.
# ---------------------------------------------------------------
mlp_pipeline = Pipeline([
    ("prep", preprocessor),
    ("model", MLPRegressor(
        hidden_layer_sizes=(32, 16),
        activation="relu",
        solver="adam",
        alpha=1e-4,               # L2 regularisation
        learning_rate_init=1e-3,
        max_iter=150,
        early_stopping=True,
        validation_fraction=0.1,
        n_iter_no_change=10,
        random_state=RNG_SEED,
    )),
])
mlp_pipeline.fit(X_train, y_train)
evaluate("Neural Network (MLP)", y_test, mlp_pipeline.predict(X_test))
tick("neural network done")

# ---------------------------------------------------------------
# Save metrics
# ---------------------------------------------------------------
with open("outputs/metrics.json", "w") as f:
    json.dump(results, f, indent=2)
print("\nSaved outputs/metrics.json")

# ---------------------------------------------------------------
# Plot 1: training loss curve (MLP)
# ---------------------------------------------------------------
mlp_model = mlp_pipeline.named_steps["model"]
plt.figure(figsize=(7, 4.5))
plt.plot(mlp_model.loss_curve_, label="Training loss")
if hasattr(mlp_model, "validation_scores_") and mlp_model.validation_scores_:
    pass  # validation_scores_ is R^2 per epoch if early_stopping=True
plt.xlabel("Training iteration")
plt.ylabel("Loss")
plt.title("Neural Network Training Loss Curve")
plt.legend()
plt.tight_layout()
plt.savefig("outputs/loss_curve.png", dpi=150)
plt.close()
print("Saved outputs/loss_curve.png")

# ---------------------------------------------------------------
# Plot 2: model comparison bar chart (MAE, lower is better)
# ---------------------------------------------------------------
names = list(results.keys())
maes = [results[n]["MAE"] for n in names]
colors = ["#B0B0B0", "#A9C9B8", "#8FBFA3", "#6FA787", "#4F8F6B", "#1B4D3E"]
plt.figure(figsize=(9, 4.8))
bars = plt.bar(names, maes, color=colors[:len(names)])
plt.ylabel("Mean Absolute Error (lower is better)")
plt.title("Model Comparison on Held-Out Test Set")
plt.xticks(rotation=20, ha="right")
for bar, mae in zip(bars, maes):
    plt.text(bar.get_x() + bar.get_width() / 2, bar.get_height() + 0.3,
              f"{mae:.2f}", ha="center", fontsize=9)
plt.tight_layout()
plt.savefig("outputs/model_comparison.png", dpi=150)
plt.close()
print("Saved outputs/model_comparison.png")

# ---------------------------------------------------------------
# Plot 3: predicted vs actual scatter (MLP, sample for readability)
# ---------------------------------------------------------------
sample_idx = np.random.choice(len(y_test), size=min(3000, len(y_test)), replace=False)
y_test_sample = y_test.values[sample_idx]
y_pred_mlp = mlp_pipeline.predict(X_test)
y_pred_sample = y_pred_mlp[sample_idx]

plt.figure(figsize=(5.5, 5.5))
plt.scatter(y_test_sample, y_pred_sample, alpha=0.15, s=10, color="#1B4D3E")
plt.plot([0, 100], [0, 100], "r--", linewidth=1, label="Perfect prediction")
plt.xlabel("Actual label")
plt.ylabel("Predicted label")
plt.title("Neural Network: Predicted vs Actual")
plt.legend()
plt.tight_layout()
plt.savefig("outputs/predicted_vs_actual.png", dpi=150)
plt.close()
print("Saved outputs/predicted_vs_actual.png")


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

    # Diagnostics
    print(f"\nResidual mean: {residuals.mean():.3f}  (should be close to 0)")
    print(f"Residual std:  {residuals.std():.3f}")
    print(f"Skew:          {((residuals - residuals.mean())**3).mean() / residuals.std()**3:.3f}")

    y_true_arr = np.asarray(y_true)
    tertiles = np.quantile(y_true_arr, [1/3, 2/3])
    low_mask  = y_true_arr <= tertiles[0]
    mid_mask  = (y_true_arr > tertiles[0]) & (y_true_arr <= tertiles[1])
    high_mask = y_true_arr > tertiles[1]
    print("\nMAE by actual-score tertile (checks whether error is uniform across the range):")
    print(f"  Low  scores (<= {tertiles[0]:.1f}):  MAE = {np.abs(residuals[low_mask]).mean():.3f}")
    print(f"  Mid  scores:                    MAE = {np.abs(residuals[mid_mask]).mean():.3f}")
    print(f"  High scores (>  {tertiles[1]:.1f}):  MAE = {np.abs(residuals[high_mask]).mean():.3f}")


plot_fig_6_2(y_test, y_pred_mlp)
plot_fig_6_3(y_test, y_pred_mlp)

# ---------------------------------------------------------------
# Save the trained model + preprocessing pipeline together
# ---------------------------------------------------------------
joblib.dump(mlp_pipeline, "outputs/loseit_recommender_model.joblib")
print("Saved outputs/loseit_recommender_model.joblib")

print("\n=== Final comparison table ===")
for name, m in results.items():
    print(f"{name:22s}  MAE={m['MAE']:6.3f}  RMSE={m['RMSE']:6.3f}  R2={m['R2']:.4f}")

