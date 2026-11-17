"""
compute_table_6_2.py

Computes Wilcoxon signed-rank test and 10,000-iteration bootstrap 95% CI
for Table 6.2 across the held-out test partition.
"""

import os
import time
import numpy as np
import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler, OneHotEncoder
from sklearn.neighbors import KNeighborsRegressor
from sklearn.ensemble import GradientBoostingRegressor
from sklearn.neural_network import MLPRegressor
from sklearn.metrics import mean_absolute_error
import scipy.stats as stats
import joblib

RNG_SEED = 42
np.random.seed(RNG_SEED)

# Load data
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

# User-level split
unique_users = df["user_id"].unique()
rng = np.random.default_rng(RNG_SEED)
rng.shuffle(unique_users)

split_idx = int(len(unique_users) * 0.8)
train_users = set(unique_users[:split_idx])
test_users = set(unique_users[split_idx:])

train_df = df[df["user_id"].isin(train_users)].reset_index(drop=True)
test_df = df[df["user_id"].isin(test_users)].reset_index(drop=True)

MAX_TRAIN_ROWS = int(os.environ.get("MAX_TRAIN_ROWS", 120_000))
MAX_TEST_ROWS = int(os.environ.get("MAX_TEST_ROWS", 30_000))
if MAX_TRAIN_ROWS > 0 and len(train_df) > MAX_TRAIN_ROWS:
    train_df = train_df.sample(n=MAX_TRAIN_ROWS, random_state=RNG_SEED).reset_index(drop=True)
if MAX_TEST_ROWS > 0 and len(test_df) > MAX_TEST_ROWS:
    test_df = test_df.sample(n=MAX_TEST_ROWS, random_state=RNG_SEED).reset_index(drop=True)

print(f"Train: {len(train_df):,} rows, Test: {len(test_df):,} rows")

X_train = train_df[NUMERIC_FEATURES + CATEGORICAL_FEATURES]
y_train = train_df[TARGET]
X_test = test_df[NUMERIC_FEATURES + CATEGORICAL_FEATURES]
y_test = test_df[TARGET].values

preprocessor = ColumnTransformer([
    ("num", StandardScaler(), NUMERIC_FEATURES),
    ("cat", OneHotEncoder(handle_unknown="ignore"), CATEGORICAL_FEATURES),
])

# 1. Rule-based predictions
y_pred_rule = test_df["baseline_score"].values
errors_rule = np.abs(y_test - y_pred_rule)

# 2. Train k-NN
print("Training k-NN...")
knn_pipeline = Pipeline([
    ("prep", preprocessor),
    ("model", KNeighborsRegressor(n_neighbors=15, weights="distance", n_jobs=-1)),
])
knn_pipeline.fit(X_train, y_train)
y_pred_knn = knn_pipeline.predict(X_test)
errors_knn = np.abs(y_test - y_pred_knn)

# 3. Train Gradient Boosting
print("Training Gradient Boosting...")
gb_pipeline = Pipeline([
    ("prep", preprocessor),
    ("model", GradientBoostingRegressor(
        n_estimators=80, max_depth=3, learning_rate=0.1, random_state=RNG_SEED)),
])
gb_pipeline.fit(X_train, y_train)
y_pred_gbm = gb_pipeline.predict(X_test)
errors_gbm = np.abs(y_test - y_pred_gbm)

# 4. Load or Train MLP
mlp_path = "outputs/loseit_recommender_model.joblib"
if os.path.exists(mlp_path):
    print(f"Loading MLP from {mlp_path}...")
    mlp_pipeline = joblib.load(mlp_path)
else:
    print("Training MLP...")
    mlp_pipeline = Pipeline([
        ("prep", preprocessor),
        ("model", MLPRegressor(
            hidden_layer_sizes=(32, 16),
            activation="relu",
            solver="adam",
            alpha=1e-4,
            learning_rate_init=1e-3,
            max_iter=150,
            early_stopping=True,
            validation_fraction=0.1,
            n_iter_no_change=10,
            random_state=RNG_SEED,
        )),
    ])
    mlp_pipeline.fit(X_train, y_train)

y_pred_mlp = mlp_pipeline.predict(X_test)
errors_mlp = np.abs(y_test - y_pred_mlp)

mae_mlp = mean_absolute_error(y_test, y_pred_mlp)
mae_gbm = mean_absolute_error(y_test, y_pred_gbm)
mae_knn = mean_absolute_error(y_test, y_pred_knn)
mae_rule = mean_absolute_error(y_test, y_pred_rule)

print(f"\nMAEs:")
print(f"MLP:  {mae_mlp:.3f}")
print(f"GBM:  {mae_gbm:.3f} (diff = {mae_gbm - mae_mlp:.3f})")
print(f"k-NN: {mae_knn:.3f} (diff = {mae_knn - mae_mlp:.3f})")
print(f"Rule: {mae_rule:.3f} (diff = {mae_rule - mae_mlp:.3f})")

comparisons = [
    ("MLP vs Gradient boosting", errors_mlp, errors_gbm, mae_gbm - mae_mlp),
    ("MLP vs k-nearest neighbours", errors_mlp, errors_knn, mae_knn - mae_mlp),
    ("MLP vs Rule-based control", errors_mlp, errors_rule, mae_rule - mae_mlp),
]

print("\n" + "="*80)
print("TABLE 6.2 RESULTS")
print("="*80)

results_table = []

n_boot = 10_000
boot_rng = np.random.default_rng(RNG_SEED)

for name, e_mlp, e_other, mae_diff in comparisons:
    # Paired differences (other - mlp)
    paired_diff = e_other - e_mlp
    
    # Bootstrap 95% CI of the mean MAE difference
    # Generate bootstrap sample means
    n_samples = len(paired_diff)
    # Resample with replacement 10,000 times
    boot_indices = boot_rng.integers(0, n_samples, size=(n_boot, n_samples))
    boot_means = np.mean(paired_diff[boot_indices], axis=1)
    ci_lower = np.percentile(boot_means, 2.5)
    ci_upper = np.percentile(boot_means, 97.5)
    
    # Wilcoxon signed-rank test
    # scipy.stats.wilcoxon(e_mlp, e_other)
    res = stats.wilcoxon(e_mlp, e_other, alternative="two-sided")
    w_stat = res.statistic
    p_val = res.pvalue
    
    # Also check one-sided (less) if relevant, or two-sided standard
    res_less = stats.wilcoxon(e_mlp, e_other, alternative="less")
    
    results_table.append({
        "Comparison": name,
        "MAE difference": f"{mae_diff:.3f}",
        "95% CI": f"[{ci_lower:.3f}, {ci_upper:.3f}]",
        "W": f"{w_stat:,.1f}",
        "W_raw": w_stat,
        "p-value": "< 0.001" if p_val < 0.001 else f"{p_val:.4e}",
        "p_val_raw": p_val,
        "p_less": res_less.pvalue
    })
    
    print(f"Comparison: {name}")
    print(f"  MAE Difference: {mae_diff:.3f}")
    print(f"  95% CI: [{ci_lower:.3f}, {ci_upper:.3f}]")
    print(f"  Wilcoxon W: {w_stat:,.1f} (raw: {w_stat})")
    print(f"  p-value (two-sided): {p_val}")
    print(f"  p-value (one-sided mlp < other): {res_less.pvalue}")
    print("-" * 50)

summary_df = pd.DataFrame(results_table)
print("\nFormatted Table:")
print(summary_df[["Comparison", "MAE difference", "95% CI", "W", "p-value"]].to_string(index=False))
