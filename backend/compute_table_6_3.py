"""
compute_table_6_3.py

Computes model robustness under controlled perturbation of numeric input features (Table 6.3).
Perturbation levels: 0%, 2%, 5%, 10% Gaussian noise (e ~ N(0, sigma^2)).
"""

import os
import numpy as np
import pandas as pd
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
import joblib

RNG_SEED = 42
np.random.seed(RNG_SEED)

# Load dataset and test split
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
test_users = set(unique_users[split_idx:])

test_df = df[df["user_id"].isin(test_users)].reset_index(drop=True)

MAX_TEST_ROWS = int(os.environ.get("MAX_TEST_ROWS", 30_000))
if MAX_TEST_ROWS > 0 and len(test_df) > MAX_TEST_ROWS:
    test_df = test_df.sample(n=MAX_TEST_ROWS, random_state=RNG_SEED).reset_index(drop=True)

print(f"Test split: {len(test_df):,} rows")

X_test_orig = test_df[NUMERIC_FEATURES + CATEGORICAL_FEATURES].copy()
y_test = test_df[TARGET].values

# Load trained pipeline
mlp_pipeline = joblib.load("outputs/loseit_recommender_model.joblib")

# Baseline unperturbed
y_pred_unperturbed = mlp_pipeline.predict(X_test_orig)
base_mae = mean_absolute_error(y_test, y_pred_unperturbed)
base_rmse = np.sqrt(mean_squared_error(y_test, y_pred_unperturbed))
base_r2 = r2_score(y_test, y_pred_unperturbed)

print(f"0% (unperturbed): MAE={base_mae:.3f}, RMSE={base_rmse:.3f}, R2={base_r2:.4f}")

noise_levels = [0.0, 0.02, 0.05, 0.10]
results = []

for noise in noise_levels:
    if noise == 0.0:
        results.append({
            "Perturbation": "0% (unperturbed)",
            "MAE": f"{base_mae:.3f}",
            "RMSE": f"{base_rmse:.3f}",
            "R2": f"{base_r2:.4f}",
            "Delta_MAE": "—"
        })
        continue
    
    # Run across 5 random seeds to ensure stable representative numbers
    maes, rmses, r2s = [], [], []
    for run_seed in range(5):
        run_rng = np.random.default_rng(RNG_SEED + run_seed)
        X_perturbed = X_test_orig.copy()
        
        # Apply (1 + e) where e ~ N(0, noise^2) to each numeric feature
        for feat in NUMERIC_FEATURES:
            e = run_rng.normal(loc=0.0, scale=noise, size=len(X_perturbed))
            X_perturbed[feat] = X_test_orig[feat] * (1.0 + e)
            
        y_pred = mlp_pipeline.predict(X_perturbed)
        maes.append(mean_absolute_error(y_test, y_pred))
        rmses.append(np.sqrt(mean_squared_error(y_test, y_pred)))
        r2s.append(r2_score(y_test, y_pred))
        
    m_mae = np.mean(maes)
    m_rmse = np.mean(rmses)
    m_r2 = np.mean(r2s)
    delta_mae = m_mae - base_mae
    
    results.append({
        "Perturbation": f"{int(noise*100)}%",
        "MAE": f"{m_mae:.3f}",
        "RMSE": f"{m_rmse:.3f}",
        "R2": f"{m_r2:.4f}",
        "Delta_MAE": f"+{delta_mae:.3f}" if delta_mae >= 0 else f"{delta_mae:.3f}"
    })

print("\n" + "="*70)
print("TABLE 6.3 RESULTS (MLP Robustness)")
print("="*70)
res_df = pd.DataFrame(results)
print(res_df.to_string(index=False))

# Optional: Rule-based control robustness comparison if applicable
print("\n" + "="*70)
