"""
tune.py

Hyperparameter tuning + cross-validation for the two strongest models from
train.py's six-way comparison (Gradient Boosting and the Neural Network
MLP - see outputs/algorithm_comparison_report.md). train.py picks a model
FAMILY by comparing default-hyperparameter versions of six algorithms;
this script asks a different question - "given the winning family, which
hyperparameters actually work best?" - and answers it with proper
cross-validation rather than a single lucky train/test split.

Methodology notes (for Chapter 6 - this is the "ablation / sensitivity"
evidence the rubric asks for, applied to hyperparameters rather than
architecture components):

- GroupKFold, grouped by user_id, is used instead of plain KFold for the
  SAME reason train.py splits by user at the top level: a random row-level
  split would let the same user's rows appear in both the training and
  validation fold within a single CV split, leaking that user's label
  distribution across the split and inflating the cross-validated score.
  GroupKFold guarantees a user's rows are never split across folds.
- RandomizedSearchCV (not GridSearchCV) is used because the parameter
  space is continuous/large enough that an exhaustive grid would be
  expensive for negligible benefit over a random sample of the same
  space - a standard, defensible trade-off worth stating explicitly in
  the report.
- The search itself runs on a capped subsample of the training data (see
  MAX_SEARCH_ROWS) purely for runtime reasons in this environment. Once
  the best hyperparameters are found, the FINAL comparison against the
  untuned models in train.py's metrics.json is run on the same held-out
  test set train.py uses, so the numbers are directly comparable.
- Override the defaults from the shell for a more thorough run, e.g.
    MAX_SEARCH_ROWS=0 N_ITER=30 CV_FOLDS=5 python3 tune.py   # 0 = no cap
"""

import os
import json
import time

import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

from sklearn.compose import ColumnTransformer
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler, OneHotEncoder
from sklearn.ensemble import GradientBoostingRegressor
from sklearn.neural_network import MLPRegressor
from sklearn.model_selection import RandomizedSearchCV, GroupKFold
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
import joblib

_t0 = time.time()
def tick(label):
    print(f"[{time.time() - _t0:6.1f}s] {label}", flush=True)

RNG_SEED = 42
np.random.seed(RNG_SEED)

CV_FOLDS = int(os.environ.get("CV_FOLDS", 3))
N_ITER = int(os.environ.get("N_ITER", 8))
MAX_SEARCH_ROWS = int(os.environ.get("MAX_SEARCH_ROWS", 25_000))

# ---------------------------------------------------------------
# Load data - same feature columns and same user-level split logic
# as train.py, so the held-out test set is identical and results
# are directly comparable to outputs/metrics.json.
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

unique_users = df["user_id"].unique()
rng = np.random.default_rng(RNG_SEED)
rng.shuffle(unique_users)
split_idx = int(len(unique_users) * 0.8)
train_users = set(unique_users[:split_idx])
test_users = set(unique_users[split_idx:])

train_df = df[df["user_id"].isin(train_users)].reset_index(drop=True)
test_df = df[df["user_id"].isin(test_users)].reset_index(drop=True)

# Held-out test set: capped the same way train.py caps it, so the final
# comparison numbers line up with outputs/metrics.json exactly.
MAX_TEST_ROWS = int(os.environ.get("MAX_TEST_ROWS", 30_000))
if len(test_df) > MAX_TEST_ROWS:
    test_df = test_df.sample(n=MAX_TEST_ROWS, random_state=RNG_SEED).reset_index(drop=True)

# Search subsample - smaller than train.py's training set on purpose (see
# module docstring). GroupKFold needs at least CV_FOLDS distinct groups,
# so we sample whole users, not rows, to keep every user's rows together.
search_users = list(train_df["user_id"].unique())
rng.shuffle(search_users)
if MAX_SEARCH_ROWS > 0:
    kept_users, running = [], 0
    per_user_counts = train_df["user_id"].value_counts()
    for u in search_users:
        kept_users.append(u)
        running += per_user_counts.get(u, 0)
        if running >= MAX_SEARCH_ROWS:
            break
    search_df = train_df[train_df["user_id"].isin(kept_users)].reset_index(drop=True)
else:
    search_df = train_df

print(f"Search subsample: {len(search_df):,} rows from {search_df['user_id'].nunique()} users")
print(f"Held-out test set: {len(test_df):,} rows from {test_df['user_id'].nunique()} users")
tick("data loaded and split")

X_search = search_df[NUMERIC_FEATURES + CATEGORICAL_FEATURES]
y_search = search_df[TARGET]
groups_search = search_df["user_id"]
X_test = test_df[NUMERIC_FEATURES + CATEGORICAL_FEATURES]
y_test = test_df[TARGET]

preprocessor = ColumnTransformer([
    ("num", StandardScaler(), NUMERIC_FEATURES),
    ("cat", OneHotEncoder(handle_unknown="ignore"), CATEGORICAL_FEATURES),
])

cv = GroupKFold(n_splits=CV_FOLDS)

results = {}


def evaluate_on_test(name, pipeline):
    y_pred = pipeline.predict(X_test)
    mae = mean_absolute_error(y_test, y_pred)
    rmse = np.sqrt(mean_squared_error(y_test, y_pred))
    r2 = r2_score(y_test, y_pred)
    print(f"{name:32s}  MAE={mae:6.3f}  RMSE={rmse:6.3f}  R2={r2:.4f}")
    return {"MAE": round(mae, 3), "RMSE": round(rmse, 3), "R2": round(r2, 4)}


def run_search(name, estimator, param_distributions):
    pipeline = Pipeline([("prep", preprocessor), ("model", estimator)])
    search = RandomizedSearchCV(
        pipeline,
        param_distributions=param_distributions,
        n_iter=N_ITER,
        scoring="neg_mean_absolute_error",
        cv=cv.split(X_search, y_search, groups=groups_search),
        random_state=RNG_SEED,
        n_jobs=-1,
        refit=True,
    )
    search.fit(X_search, y_search)
    tick(f"{name} search done ({N_ITER} candidates x {CV_FOLDS} folds)")

    best_params = {k.replace("model__", ""): v for k, v in search.best_params_.items()}
    cv_mae = -search.best_score_
    print(f"{name} best CV MAE: {cv_mae:.3f}  params: {best_params}")

    # Refit the best config on the FULL search subsample (not just the CV
    # training folds) before the final held-out evaluation, so the
    # reported test score isn't handicapped by the smaller per-fold
    # training set used during the search itself.
    final_pipeline = Pipeline([("prep", preprocessor), ("model", estimator.__class__(**best_params))])
    final_pipeline.fit(X_search, y_search)
    test_metrics = evaluate_on_test(f"{name} (tuned)", final_pipeline)

    results[name] = {
        "best_params": best_params,
        "cv_mae_mean": round(cv_mae, 3),
        "cv_folds": CV_FOLDS,
        "search_candidates": N_ITER,
        "test_metrics": test_metrics,
    }
    return final_pipeline, test_metrics


# ---------------------------------------------------------------
# Gradient Boosting - the closest untuned competitor to the MLP
# (see outputs/algorithm_comparison_report.md).
# ---------------------------------------------------------------
gb_pipeline, gb_test_metrics = run_search(
    "Gradient Boosting",
    GradientBoostingRegressor(random_state=RNG_SEED),
    {
        "model__n_estimators": [60, 100, 150, 200],
        "model__max_depth": [2, 3, 4, 5],
        "model__learning_rate": [0.03, 0.05, 0.1, 0.2],
        "model__subsample": [0.7, 0.85, 1.0],
    },
)

# ---------------------------------------------------------------
# Neural Network (MLP) - the untuned winner; tuning asks whether its
# architecture/regularisation choices in train.py were actually the
# best available, or just a reasonable first guess.
# ---------------------------------------------------------------
mlp_pipeline, mlp_test_metrics = run_search(
    "Neural Network (MLP)",
    MLPRegressor(
        activation="relu", solver="adam", max_iter=200,
        early_stopping=True, validation_fraction=0.1, n_iter_no_change=10,
        random_state=RNG_SEED,
    ),
    {
        "model__hidden_layer_sizes": [(32,), (32, 16), (64, 32), (64, 32, 16)],
        "model__alpha": [1e-5, 1e-4, 1e-3, 1e-2],
        "model__learning_rate_init": [3e-4, 1e-3, 3e-3],
    },
)

# ---------------------------------------------------------------
# Compare against the untuned baselines already recorded by train.py,
# so the report can show tuning's actual marginal contribution.
# ---------------------------------------------------------------
untuned_path = "outputs/metrics.json"
untuned = {}
if os.path.exists(untuned_path):
    with open(untuned_path) as f:
        untuned = json.load(f)

comparison = {
    "Gradient Boosting (untuned)": untuned.get("Gradient Boosting", {}),
    "Gradient Boosting (tuned)": gb_test_metrics,
    "Neural Network (MLP) (untuned)": untuned.get("Neural Network (MLP)", {}),
    "Neural Network (MLP) (tuned)": mlp_test_metrics,
}
print("\n=== Tuned vs untuned, on the identical held-out test set ===")
for name, m in comparison.items():
    if m:
        print(f"{name:34s}  MAE={m['MAE']:6.3f}  RMSE={m.get('RMSE','?'):>6}  R2={m.get('R2','?')}")

with open("outputs/tuning_results.json", "w") as f:
    json.dump({"search_config": {"cv_folds": CV_FOLDS, "n_iter": N_ITER,
                                  "search_rows": len(search_df)},
               "models": results, "comparison": comparison}, f, indent=2)
print("\nSaved outputs/tuning_results.json")

# ---------------------------------------------------------------
# Chart: tuned vs untuned MAE, side by side.
# ---------------------------------------------------------------
labels = ["Gradient\nBoosting\n(untuned)", "Gradient\nBoosting\n(tuned)",
          "Neural Net\n(MLP)\n(untuned)", "Neural Net\n(MLP)\n(tuned)"]
maes = [comparison["Gradient Boosting (untuned)"].get("MAE"),
        comparison["Gradient Boosting (tuned)"].get("MAE"),
        comparison["Neural Network (MLP) (untuned)"].get("MAE"),
        comparison["Neural Network (MLP) (tuned)"].get("MAE")]
colors = ["#A9C9B8", "#4F8F6B", "#8FBFA3", "#1B4D3E"]
plt.figure(figsize=(7.5, 4.8))
bars = plt.bar(labels, maes, color=colors)
plt.ylabel("Mean Absolute Error (lower is better)")
plt.title("Effect of Hyperparameter Tuning on the Two Strongest Models")
for bar, mae in zip(bars, maes):
    if mae is not None:
        plt.text(bar.get_x() + bar.get_width() / 2, bar.get_height() + 0.05,
                  f"{mae:.2f}", ha="center", fontsize=9)
plt.tight_layout()
plt.savefig("outputs/tuning_comparison.png", dpi=150)
plt.close()
print("Saved outputs/tuning_comparison.png")

# ---------------------------------------------------------------
# If the tuned MLP beats the currently-served model, replace it and
# record the win in metrics.json under a new key - the untuned 6-way
# comparison entries are left untouched so that table still stands as
# the "algorithm family selection" evidence; this becomes the separate
# "hyperparameter tuning" evidence on top of it.
# ---------------------------------------------------------------
current_mlp_mae = untuned.get("Neural Network (MLP)", {}).get("MAE")
if current_mlp_mae is not None and mlp_test_metrics["MAE"] < current_mlp_mae:
    joblib.dump(mlp_pipeline, "outputs/loseit_recommender_model.joblib")
    untuned["Neural Network (MLP, tuned)"] = mlp_test_metrics
    with open(untuned_path, "w") as f:
        json.dump(untuned, f, indent=2)
    print(f"\nTuned MLP improved MAE ({current_mlp_mae} -> {mlp_test_metrics['MAE']}); "
          f"replaced outputs/loseit_recommender_model.joblib and updated metrics.json.")
else:
    print(f"\nTuned MLP (MAE={mlp_test_metrics['MAE']}) did not beat the current "
          f"served model (MAE={current_mlp_mae}); leaving the served model unchanged.")
