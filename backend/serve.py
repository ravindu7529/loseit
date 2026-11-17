"""
serve.py

FastAPI service that loads the trained MLP recommender and exposes it to
the Flutter app, integrated with a MongoDB database for recipes, user
profiles, recommendation logs, meal tracking, and favorites.

Run locally with:
    uvicorn serve:app --reload --port 8000 --host 0.0.0.0

Then test with:
    curl http://127.0.0.1:8000/health
    curl -X POST http://127.0.0.1:8000/recommend \
      -H "Content-Type: application/json" -d '{
        "age": 28, "gender": "Female", "height_cm": 162, "weight_kg": 78,
        "activity_level": "Light", "dietary_pref": "Vegetarian",
        "spice_pref": "Medium"
      }'
"""

from datetime import datetime
import json
import logging
import os
from pathlib import Path
import re
from typing import Any, Dict, List, Literal, Optional

import joblib
import pandas as pd
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from db import (
    check_db_connection,
    create_user,
    delete_meal_log,
    fetch_all_recipes_from_db,
    find_user_by_email,
    find_user_by_id,
    get_db,
    get_user_favorites,
    get_user_meal_logs,
    get_user_sync_data,
    get_user_weight_logs,
    save_meal_log,
    save_weight_log,
    seed_recipes_if_empty,
    toggle_favorite,
    update_user_profile,
    verify_password,
)
from recipe_generator import generate_sri_lankan_recipe

logger = logging.getLogger("loseit_api")

BASE_DIR = Path(__file__).resolve().parent
MODEL_PATH = BASE_DIR / "outputs" / "loseit_recommender_model.joblib"
RECIPES_PATH = BASE_DIR / "data" / "recipes.json"
METRICS_PATH = BASE_DIR / "outputs" / "metrics.json"

app = FastAPI(
    title="Spice & Scale Recommendation API with MongoDB",
    version="1.1.0",
    description="Serves the trained neural-network recipe recommender backed by MongoDB database.",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

if not MODEL_PATH.exists():
    raise RuntimeError(
        f"Trained model not found at {MODEL_PATH}. "
        "Run: python3 generate_dataset.py && python3 train.py"
    )

MODEL = joblib.load(MODEL_PATH)
with open(RECIPES_PATH) as f:
    RECIPES = pd.DataFrame(json.load(f))

METRICS = {}
if METRICS_PATH.exists():
    with open(METRICS_PATH) as f:
        METRICS = json.load(f)

ACTIVITY_MULTIPLIER = {
    "Sedentary": 1.2,
    "Light": 1.375,
    "Moderate": 1.55,
    "Active": 1.725,
}
DIET_RANK = {"Vegan": 0, "Vegetarian": 1, "Pescatarian": 2, "Non-Vegetarian": 3}

FEATURE_COLS = [
    "age", "height_cm", "weight_kg", "bmi", "daily_calorie_target",
    "per_meal_target", "recipe_calories", "recipe_protein", "recipe_carbs",
    "recipe_fat", "recipe_fiber", "recipe_prep_time", "gender",
    "activity_level", "spice_pref", "recipe_spice_level",
    "recipe_food_group", "recipe_meal_type",
]


class UserProfileRequest(BaseModel):
    user_id: Optional[str] = "default_user"
    name: Optional[str] = None
    email: Optional[str] = None
    age: int = Field(..., ge=13, le=100)
    gender: Literal["Male", "Female", "Other"]
    height_cm: float = Field(..., ge=100, le=250)
    weight_kg: float = Field(..., ge=25, le=300)
    target_weight_kg: Optional[float] = None
    activity_level: Literal["Sedentary", "Light", "Moderate", "Active"]
    dietary_pref: Literal["Vegan", "Vegetarian", "Pescatarian", "Non-Vegetarian"]
    spice_pref: Literal["Mild", "Medium", "Hot"]
    top_n: Optional[int] = Field(20, ge=1, le=300)
    meal_type: Optional[Literal["Breakfast", "Lunch", "Dinner", "Snack"]] = None
    allergies: Optional[str] = ""
    avoid_ingredients: Optional[List[str]] = None


class MealLogModel(BaseModel):
    id: Optional[str] = None
    recipe_id: str
    recipe_name: str
    calories: int
    protein: Optional[float] = 0.0
    carbs: Optional[float] = 0.0
    fat: Optional[float] = 0.0
    meal_type: Optional[str] = "Lunch"
    logged_at: Optional[str] = None


class WeightLogModel(BaseModel):
    id: Optional[str] = None
    weight_kg: float
    recorded_at: Optional[str] = None


class RegisterRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)
    email: str = Field(..., min_length=3, max_length=150)
    password: str = Field(..., min_length=6, max_length=100)


class LoginRequest(BaseModel):
    email: str = Field(..., min_length=3, max_length=150)
    password: str = Field(..., min_length=1)


class GenerateRecipeRequest(BaseModel):
    prompt: str = Field(..., description="Craving or mood description, e.g. 'something sweet' or 'spicy kottu'")
    dietary_pref: Optional[str] = "Vegetarian"
    spice_pref: Optional[str] = "Medium"
    meal_type: Optional[str] = "Dinner"
    allergies: Optional[str] = ""
    avoid_ingredients: Optional[List[str]] = None


@app.on_event("startup")
def startup_db_seed():
    """Attempt MongoDB connection & recipe seeding on backend startup."""
    if check_db_connection():
        seed_recipes_if_empty(RECIPES_PATH)


def compute_bmr(weight_kg: float, height_cm: float, age: int, gender: str) -> float:
    base = 10 * weight_kg + 6.25 * height_cm - 5 * age
    return base + 5 if gender == "Male" else base - 161


@app.get("/health")
def health():
    db_connected = check_db_connection()
    db_recipe_count = 0
    if db_connected:
        try:
            db_recipe_count = get_db()["recipes"].count_documents({})
        except Exception:
            pass

    return {
        "status": "ok",
        "model_loaded": MODEL is not None,
        "model": "Neural Network (MLP)",
        "recipes_loaded": int(len(RECIPES)),
        "mongodb_connected": db_connected,
        "mongodb_recipes_count": db_recipe_count,
        "metrics": METRICS.get("Neural Network (MLP)", {}),
    }


@app.get("/metrics")
def metrics():
    return METRICS


@app.get("/recipes")
def all_recipes():
    db_recipes = fetch_all_recipes_from_db()
    if db_recipes:
        return db_recipes
    return RECIPES.drop(columns=[c for c in RECIPES.columns if c.startswith("_")]).to_dict("records")


def _normalize_avoidance_terms(avoid_list: Optional[List[str]], allergies_str: Optional[str]) -> set:
    terms = set()
    raw_list = list(avoid_list or [])
    if allergies_str:
        raw_list.extend(re.split(r'[,;\n]', allergies_str))
    for raw in raw_list:
        if not raw:
            continue
        t = raw.strip().lower()
        if not t:
            continue
        terms.add(t)
        if t.endswith('ies') and len(t) > 4:
            terms.add(t[:-3] + 'y')
        elif t.endswith('es') and len(t) > 3:
            terms.add(t[:-2])
        elif t.endswith('s') and len(t) > 3:
            terms.add(t[:-1])
    return terms


@app.post("/recommend")
def recommend(req: UserProfileRequest):
    bmr = compute_bmr(req.weight_kg, req.height_cm, req.age, req.gender)
    maintenance = bmr * ACTIVITY_MULTIPLIER[req.activity_level]
    safe_min = 1500 if req.gender == "Male" else 1200
    daily_target = max(maintenance - 500, safe_min)
    per_meal_target = daily_target * 0.30
    bmi = req.weight_kg / ((req.height_cm / 100) ** 2)

    db_recipes = fetch_all_recipes_from_db()
    if db_recipes:
        recipe_df = pd.DataFrame(db_recipes)
    else:
        recipe_df = RECIPES.copy()

    pref_rank = DIET_RANK[req.dietary_pref]
    recipes = recipe_df[recipe_df["Dietary_Tag"].map(DIET_RANK) <= pref_rank].copy()

    # Apply strict allergy / food avoidance hard filter
    avoid_terms = _normalize_avoidance_terms(req.avoid_ingredients, req.allergies)

    if avoid_terms:
        def contains_avoided(row):
            combined = f"{row.get('Recipe_Name', '')} {row.get('Main_Ingredient', '')} {row.get('Key_Ingredients', '')} {row.get('Category', '')} {row.get('Short_Description', '')}".lower()
            return any(term in combined for term in avoid_terms)

        non_allergic = recipes[~recipes.apply(contains_avoided, axis=1)]
        recipes = non_allergic.copy()

    if req.meal_type:
        filtered = recipes[recipes["Meal_Type"] == req.meal_type]
        if not filtered.empty:
            recipes = filtered.copy()

    if recipes.empty:
        raise HTTPException(
            status_code=404,
            detail="No recipes match your dietary restrictions and allergy exclusions.",
        )

    recipes["age"] = req.age
    recipes["gender"] = req.gender
    recipes["height_cm"] = req.height_cm
    recipes["weight_kg"] = req.weight_kg
    recipes["bmi"] = bmi
    recipes["activity_level"] = req.activity_level
    recipes["spice_pref"] = req.spice_pref
    recipes["daily_calorie_target"] = daily_target
    recipes["per_meal_target"] = per_meal_target
    recipes["recipe_calories"] = recipes["Calories_kcal"]
    recipes["recipe_protein"] = recipes["Protein_g"]
    recipes["recipe_carbs"] = recipes["Carbs_g"]
    recipes["recipe_fat"] = recipes["Fat_g"]
    recipes["recipe_fiber"] = recipes["Fiber_g"]
    recipes["recipe_prep_time"] = recipes["Prep_Time_Min"]
    recipes["recipe_spice_level"] = recipes["Spice_Level"]
    recipes["recipe_food_group"] = recipes["Food_Group"]
    recipes["recipe_meal_type"] = recipes["Meal_Type"]

    recipes["predicted_score"] = MODEL.predict(recipes[FEATURE_COLS])
    recipes = recipes.sort_values("predicted_score", ascending=False).head(req.top_n)

    recommendations_list = [
        {
            "recipe_id": str(row["Recipe_ID"]),
            "name": row["Recipe_Name"],
            "calories": int(row["Calories_kcal"]),
            "protein_g": float(row["Protein_g"]),
            "carbs_g": float(row["Carbs_g"]),
            "fat_g": float(row["Fat_g"]),
            "meal_type": row["Meal_Type"],
            "spice_level": row["Spice_Level"],
            "predicted_score": round(float(row["predicted_score"]), 1),
        }
        for _, row in recipes.iterrows()
    ]

    response_payload = {
        "source": "mongodb-neural-network-api" if db_recipes else "trained-model-api",
        "model": "Neural Network (MLP)",
        "bmr": round(bmr),
        "maintenance_calories": round(maintenance),
        "daily_calorie_target": round(daily_target),
        "per_meal_target": round(per_meal_target),
        "bmi": round(bmi, 1),
        "eligible_recipe_count": int(len(recipe_df[recipe_df["Dietary_Tag"].map(DIET_RANK) <= pref_rank])),
        "recommendations": recommendations_list,
    }

    # Log to MongoDB recommendation_log if DB connected
    if check_db_connection():
        try:
            req_data = req.model_dump() if hasattr(req, "model_dump") else req.dict()
            get_db()["recommendations_log"].insert_one({
                "user_id": req.user_id,
                "timestamp": datetime.utcnow().isoformat(),
                "user_request": req_data,
                "calculated_metrics": {
                    "bmr": response_payload["bmr"],
                    "maintenance_calories": response_payload["maintenance_calories"],
                    "daily_calorie_target": response_payload["daily_calorie_target"],
                    "bmi": response_payload["bmi"],
                },
                "recommended_recipe_ids": [r["recipe_id"] for r in recommendations_list],
            })
        except Exception as e:
            logger.error(f"Failed to write recommendation log to MongoDB: {e}")

    return response_payload


@app.post("/generate-recipe")
def generate_recipe_endpoint(req: GenerateRecipeRequest):
    """
    Generates a brand-new Sri Lankan recipe from scratch inspired by the 300-recipe dataset,
    conditioned on user cravings, dietary restrictions, spice preferences, and allergy avoidances.
    """
    try:
        generated = generate_sri_lankan_recipe(
            prompt=req.prompt,
            dietary_pref=req.dietary_pref or "Vegetarian",
            spice_pref=req.spice_pref or "Medium",
            meal_type=req.meal_type or "Dinner",
            allergies=req.allergies,
            avoid_ingredients=req.avoid_ingredients,
        )
        return {
            "status": "success",
            "model": "Sri Lankan Recipe Generative Engine",
            "recipe": generated,
        }
    except Exception as e:
        logger.error(f"Error generating recipe: {e}")
        raise HTTPException(status_code=500, detail=f"Recipe generation error: {str(e)}")


# ==============================================================================
# Authentication & MongoDB User Profile Management Endpoints
# ==============================================================================

@app.post("/auth/register")
def register_endpoint(req: RegisterRequest):
    """Registers a new user account with hashed credentials."""
    email_clean = req.email.strip().lower()
    if "@" not in email_clean or "." not in email_clean:
        raise HTTPException(status_code=400, detail="Please provide a valid email address.")

    existing = find_user_by_email(email_clean)
    if existing:
        raise HTTPException(status_code=400, detail="An account with this email address already exists.")

    try:
        user = create_user(name=req.name, email=email_clean, password=req.password)
        return {
            "status": "success",
            "message": "Account created successfully",
            "user_id": user["user_id"],
            "name": user["name"],
            "email": user["email"],
            "is_onboarded": user.get("is_onboarded", False),
            "profile": user.get("profile"),
        }
    except Exception as e:
        logger.error(f"Registration error: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to register account: {str(e)}")


@app.post("/auth/login")
def login_endpoint(req: LoginRequest):
    """Logs in an existing user with email and password, returning their saved profile."""
    email_clean = req.email.strip().lower()
    user = find_user_by_email(email_clean)
    if not user:
        raise HTTPException(status_code=401, detail="Invalid email or password.")

    salt = user.get("salt")
    password_hash = user.get("password_hash")
    if not salt or not password_hash or not verify_password(req.password, salt, password_hash):
        raise HTTPException(status_code=401, detail="Invalid email or password.")

    user_name = user.get("name", "Friend")
    user_email = user.get("email", email_clean)
    raw_profile = user.get("profile")
    profile = None
    if raw_profile and isinstance(raw_profile, dict):
        profile = dict(raw_profile)
        if not profile.get("name") or profile.get("name") == "Guest":
            profile["name"] = user_name
        if not profile.get("email"):
            profile["email"] = user_email

    return {
        "status": "success",
        "message": "Logged in successfully",
        "user_id": user["user_id"],
        "name": user_name,
        "email": user_email,
        "is_onboarded": user.get("is_onboarded", False),
        "profile": profile,
    }


@app.get("/auth/me")
def current_user_endpoint(user_id: str):
    """Fetches user details and onboarded status."""
    user = find_user_by_id(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found.")

    user_name = user.get("name", "Friend")
    user_email = user.get("email", "")
    raw_profile = user.get("profile")
    profile = None
    if raw_profile and isinstance(raw_profile, dict):
        profile = dict(raw_profile)
        if not profile.get("name") or profile.get("name") == "Guest":
            profile["name"] = user_name
        if not profile.get("email"):
            profile["email"] = user_email

    return {
        "status": "success",
        "user_id": user["user_id"],
        "name": user_name,
        "email": user_email,
        "is_onboarded": user.get("is_onboarded", False),
        "profile": profile,
    }


@app.get("/users/{user_id}")
def get_user_profile(user_id: str):
    user_doc = find_user_by_id(user_id)
    if not user_doc and check_db_connection():
        # Fallback to searching direct user_id key in mongo
        user_doc = get_db()["users"].find_one({"user_id": user_id})

    if not user_doc:
        raise HTTPException(status_code=404, detail=f"User '{user_id}' profile not found")

    safe_doc = dict(user_doc)
    safe_doc.pop("password_hash", None)
    safe_doc.pop("salt", None)
    safe_doc.pop("_id", None)
    return safe_doc


@app.post("/users/{user_id}")
def save_user_profile(user_id: str, profile: UserProfileRequest):
    profile_data = profile.model_dump() if hasattr(profile, "model_dump") else profile.dict()
    profile_data["user_id"] = user_id
    profile_data["updated_at"] = datetime.utcnow().isoformat()

    user_doc = find_user_by_id(user_id)
    if user_doc:
        if not profile_data.get("name") or profile_data.get("name") == "Guest":
            profile_data["name"] = user_doc.get("name", "Friend")
        if not profile_data.get("email"):
            profile_data["email"] = user_doc.get("email", "")

    success = update_user_profile(user_id, profile_data, is_onboarded=True)
    if not success and check_db_connection():
        try:
            get_db()["users"].update_one(
                {"user_id": user_id},
                {
                    "$set": {
                        "user_id": user_id,
                        "profile": profile_data,
                        "is_onboarded": True,
                        "updated_at": datetime.utcnow().isoformat(),
                    }
                },
                upsert=True,
            )
        except Exception as e:
            logger.error(f"Failed to upsert user profile in MongoDB: {e}")

    return {"status": "success", "message": f"Profile saved for user '{user_id}'", "profile": profile_data}


# ==============================================================================
# Multi-User Data Persistence Endpoints (MongoDB with Local Persistent Fallback)
# ==============================================================================

@app.post("/users/{user_id}/logs")
def log_meal(user_id: str, log: MealLogModel):
    """Saves a meal log for a specific user."""
    try:
        log_dict = log.model_dump() if hasattr(log, "model_dump") else log.dict()
        saved_entry = save_meal_log(user_id=user_id, log_data=log_dict)
        return {"status": "success", "message": "Meal logged successfully", "log": saved_entry}
    except Exception as e:
        logger.error(f"Failed to log meal for user {user_id}: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to log meal: {str(e)}")


@app.get("/users/{user_id}/logs")
def get_user_meals(user_id: str):
    """Fetches all meal logs for a specific user."""
    try:
        logs = get_user_meal_logs(user_id=user_id)
        return {"user_id": user_id, "count": len(logs), "logs": logs}
    except Exception as e:
        logger.error(f"Failed to fetch meal logs for user {user_id}: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to fetch meal logs: {str(e)}")


@app.delete("/users/{user_id}/logs/{log_id}")
def delete_user_meal(user_id: str, log_id: str):
    """Deletes a specific meal log for a user."""
    try:
        deleted = delete_meal_log(user_id=user_id, log_id=log_id)
        return {"status": "success" if deleted else "not_found", "deleted": deleted}
    except Exception as e:
        logger.error(f"Failed to delete meal log {log_id} for user {user_id}: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to delete meal log: {str(e)}")


@app.post("/users/{user_id}/weights")
def log_weight(user_id: str, weight: WeightLogModel):
    """Saves a weight entry for a specific user."""
    try:
        weight_dict = weight.model_dump() if hasattr(weight, "model_dump") else weight.dict()
        saved_entry = save_weight_log(user_id=user_id, weight_data=weight_dict)
        return {"status": "success", "message": "Weight recorded successfully", "weight": saved_entry}
    except Exception as e:
        logger.error(f"Failed to record weight for user {user_id}: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to record weight: {str(e)}")


@app.get("/users/{user_id}/weights")
def get_user_weights(user_id: str):
    """Fetches all weight history for a specific user."""
    try:
        weights = get_user_weight_logs(user_id=user_id)
        return {"user_id": user_id, "count": len(weights), "weights": weights}
    except Exception as e:
        logger.error(f"Failed to fetch weight logs for user {user_id}: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to fetch weight logs: {str(e)}")


@app.post("/users/{user_id}/favorites/{recipe_id}")
def toggle_user_favorite(user_id: str, recipe_id: str):
    """Toggles favorite recipe for a specific user."""
    try:
        res = toggle_favorite(user_id=user_id, recipe_id=recipe_id)
        return res
    except Exception as e:
        logger.error(f"Failed to toggle favorite for user {user_id}: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to toggle favorite: {str(e)}")


@app.get("/users/{user_id}/favorites")
def get_favorites(user_id: str):
    """Fetches all favorited recipe IDs for a specific user."""
    try:
        favs = get_user_favorites(user_id=user_id)
        return {"user_id": user_id, "count": len(favs), "favorites": favs}
    except Exception as e:
        logger.error(f"Failed to fetch favorites for user {user_id}: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to fetch favorites: {str(e)}")


@app.get("/users/{user_id}/sync")
def get_user_sync(user_id: str):
    """Fetches all assets for a user (profile, meals, weights, favorites) in one call."""
    try:
        data = get_user_sync_data(user_id=user_id)
        return {"status": "success", "data": data}
    except Exception as e:
        logger.error(f"Failed to fetch sync data for user {user_id}: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to fetch sync data: {str(e)}")


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=int(os.environ.get("PORT", 8000)))
