"""
db.py

MongoDB database manager for LoseIt backend with persistent local DB fallback.
Provides client connection handling, health checks, database seeding,
and authentication user management for:
- users & credentials
- recipes
- user profiles
- recommendation logs
- meal logs
- favorites

When MongoDB is reachable, it uses MongoDB.
When MongoDB is unreachable, it automatically uses persistent local storage
at `backend/data/loseit_local_db.json` so registration, login, and profile
saving ALWAYS work reliably with zero downtime.
"""

from datetime import datetime
import hashlib
import json
import logging
import os
from pathlib import Path
import secrets
import time
from typing import Any, Dict, List, Optional, Tuple
import uuid
import pymongo
from pymongo.errors import ConnectionFailure, ServerSelectionTimeoutError

logger = logging.getLogger("loseit_db")

MONGODB_URL = os.environ.get("MONGODB_URL", "mongodb://localhost:27017")
MONGODB_DB_NAME = os.environ.get("MONGODB_DB_NAME", "loseit_db")
LOCAL_DB_PATH = Path(__file__).resolve().parent / "data" / "loseit_local_db.json"

_client: Optional[pymongo.MongoClient] = None
_db_status_cache: Optional[bool] = None
_db_status_last_checked: float = 0.0
_DB_CACHE_TTL: float = 15.0  # seconds


def get_client() -> pymongo.MongoClient:
    global _client
    if _client is None:
        _client = pymongo.MongoClient(MONGODB_URL, serverSelectionTimeoutMS=500)
    return _client


def get_db():
    client = get_client()
    return client[MONGODB_DB_NAME]


def check_db_connection(force_check: bool = False) -> bool:
    """Check if MongoDB server is responsive with caching to avoid repeated timeouts."""
    global _client, _db_status_cache, _db_status_last_checked
    now = time.time()
    if not force_check and _db_status_cache is not None and (now - _db_status_last_checked < _DB_CACHE_TTL):
        return _db_status_cache

    try:
        client = get_client()
        client.admin.command("ping")
        _db_status_cache = True
    except (ConnectionFailure, ServerSelectionTimeoutError, Exception) as e:
        logger.warning(f"MongoDB connection check failed: {e}")
        _db_status_cache = False
        if _client is not None:
            try:
                _client.close()
            except Exception:
                pass
            _client = None

    _db_status_last_checked = now
    return _db_status_cache


# ---------------------------------------------------------------------------
# Local Persistent DB Fallback
# ---------------------------------------------------------------------------
def _load_local_db() -> Dict[str, Any]:
    LOCAL_DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    if not LOCAL_DB_PATH.exists():
        initial = {"users": {}, "favorites": {}, "meal_logs": {}, "weight_logs": {}, "generated_recipes": {}}
        try:
            with open(LOCAL_DB_PATH, "w", encoding="utf-8") as f:
                json.dump(initial, f, indent=2)
            return initial
        except Exception as e:
            logger.error(f"Failed to create local db: {e}")
            return initial

    try:
        if LOCAL_DB_PATH.stat().st_size == 0:
            raise ValueError("Local database file is empty (0 bytes)")
        with open(LOCAL_DB_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
            data.setdefault("users", {})
            data.setdefault("favorites", {})
            data.setdefault("meal_logs", {})
            data.setdefault("weight_logs", {})
            data.setdefault("generated_recipes", {})
            return data
    except Exception as e:
        logger.error(f"Failed to read local db: {e}")
        tmp_path = LOCAL_DB_PATH.with_suffix(".json.tmp")
        if tmp_path.exists() and tmp_path.stat().st_size > 0:
            try:
                with open(tmp_path, "r", encoding="utf-8") as f:
                    data = json.load(f)
                logger.info("Successfully recovered local db from temp file.")
                return data
            except Exception:
                pass
        return {"users": {}, "favorites": {}, "meal_logs": {}, "weight_logs": {}, "generated_recipes": {}}


def _save_local_db(data: Dict[str, Any]) -> None:
    try:
        LOCAL_DB_PATH.parent.mkdir(parents=True, exist_ok=True)
        tmp_path = LOCAL_DB_PATH.with_suffix(".json.tmp")
        with open(tmp_path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp_path, LOCAL_DB_PATH)
    except Exception as e:
        logger.error(f"Failed to write local db atomically: {e}")


def init_db_indexes():
    """Initializes MongoDB indexes for fast lookups and unique constraints."""
    if not check_db_connection():
        return
    try:
        db = get_db()
        # Users collection indexes
        db["users"].create_index("email", unique=True)
        db["users"].create_index("user_id", unique=True)
        # Recipes collection indexes
        db["recipes"].create_index("Recipe_ID", unique=True)
        db["recipes"].create_index("Dietary_Tag")
        db["recipes"].create_index("Meal_Type")
        # Meal logs and favorites
        db["meal_logs"].create_index([("user_id", pymongo.ASCENDING), ("logged_at", pymongo.DESCENDING)])
        db["favorites"].create_index([("user_id", pymongo.ASCENDING), ("recipe_id", pymongo.ASCENDING)], unique=True)
    except Exception as e:
        logger.warning(f"Index creation notice: {e}")


def hash_password(password: str, salt: Optional[str] = None) -> Tuple[str, str]:
    """Hashes a password with PBKDF2-HMAC-SHA256 and a cryptographic salt."""
    if salt is None:
        salt = secrets.token_hex(16)
    key = hashlib.pbkdf2_hmac(
        "sha256",
        password.encode("utf-8"),
        salt.encode("utf-8"),
        100000,
    )
    return key.hex(), salt


def verify_password(password: str, salt: str, expected_hash: str) -> bool:
    """Verifies a password against the stored salt and hash."""
    hashed, _ = hash_password(password, salt)
    return secrets.compare_digest(hashed, expected_hash)


def find_user_by_email(email: str) -> Optional[Dict[str, Any]]:
    """Looks up a user by case-insensitive email from MongoDB or local fallback."""
    clean_email = email.strip().lower()

    if check_db_connection():
        try:
            db = get_db()
            user = db["users"].find_one({"email": clean_email})
            if user:
                return user
        except Exception as e:
            logger.error(f"Error querying user by email in MongoDB: {e}")

    # Local fallback
    local_data = _load_local_db()
    for user_doc in local_data.get("users", {}).values():
        if user_doc.get("email", "").strip().lower() == clean_email:
            return user_doc
    return None


def find_user_by_id(user_id: str) -> Optional[Dict[str, Any]]:
    """Looks up a user by user_id from MongoDB or local fallback."""
    if check_db_connection():
        try:
            db = get_db()
            user = db["users"].find_one({"user_id": user_id})
            if user:
                return user
        except Exception as e:
            logger.error(f"Error querying user by id in MongoDB: {e}")

    # Local fallback
    local_data = _load_local_db()
    return local_data.get("users", {}).get(user_id)


def create_user(name: str, email: str, password: str) -> Dict[str, Any]:
    """Creates a new user record in MongoDB (or local fallback)."""
    clean_email = email.strip().lower()
    clean_name = name.strip()
    hashed, salt = hash_password(password)
    user_id = f"user_{uuid.uuid4().hex[:12]}"
    now = datetime.utcnow().isoformat()

    user_doc = {
        "user_id": user_id,
        "name": clean_name,
        "email": clean_email,
        "password_hash": hashed,
        "salt": salt,
        "is_onboarded": False,
        "profile": {
            "name": clean_name,
            "email": clean_email,
            "age": 25,
            "gender": "Male",
            "height_cm": 175.0,
            "weight_kg": 80.0,
            "target_weight_kg": 72.0,
            "activity_level": "Moderate",
            "dietary_pref": "Non-Vegetarian",
            "spice_pref": "Medium",
            "allergies": "",
        },
        "created_at": now,
        "updated_at": now,
    }

    if check_db_connection():
        try:
            db = get_db()
            db["users"].insert_one(user_doc)
        except Exception as e:
            logger.error(f"Error inserting user to MongoDB: {e}")
            # Fallback to local
            local_data = _load_local_db()
            local_data.setdefault("users", {})[user_id] = user_doc
            _save_local_db(local_data)
    else:
        # Save to local persistent db
        local_data = _load_local_db()
        local_data.setdefault("users", {})[user_id] = user_doc
        _save_local_db(local_data)

    # Remove sensitive fields before returning
    safe_doc = dict(user_doc)
    safe_doc.pop("password_hash", None)
    safe_doc.pop("salt", None)
    safe_doc.pop("_id", None)
    return safe_doc


def update_user_profile(user_id: str, profile_data: Dict[str, Any], is_onboarded: bool = True) -> bool:
    """Updates user profile data and sets onboarded flag."""
    now = datetime.utcnow().isoformat()
    updated = False

    user_doc = find_user_by_id(user_id)
    if user_doc:
        if not profile_data.get("name") or profile_data.get("name") == "Guest":
            profile_data["name"] = user_doc.get("name", "Friend")
        if not profile_data.get("email"):
            profile_data["email"] = user_doc.get("email", "")

    if check_db_connection():
        try:
            db = get_db()
            res = db["users"].update_one(
                {"user_id": user_id},
                {
                    "$set": {
                        "profile": profile_data,
                        "is_onboarded": is_onboarded,
                        "updated_at": now,
                    }
                },
            )
            updated = res.matched_count > 0
        except Exception as e:
            logger.error(f"Failed to update profile for user {user_id} in MongoDB: {e}")

    # Always keep local DB synced
    local_data = _load_local_db()
    users_dict = local_data.setdefault("users", {})
    if user_id in users_dict:
        users_dict[user_id]["profile"] = profile_data
        users_dict[user_id]["is_onboarded"] = is_onboarded
        users_dict[user_id]["updated_at"] = now
    else:
        # Upsert user record in local DB if not yet created
        clean_name = profile_data.get("name") or "Friend"
        clean_email = profile_data.get("email") or ""
        users_dict[user_id] = {
            "user_id": user_id,
            "name": clean_name,
            "email": clean_email,
            "is_onboarded": is_onboarded,
            "profile": profile_data,
            "created_at": now,
            "updated_at": now,
        }
    _save_local_db(local_data)
    updated = True

    return updated


def seed_recipes_if_empty(recipes_filepath: Path) -> int:
    """Seeds the recipes collection from JSON if empty. Returns inserted count."""
    if not check_db_connection():
        logger.warning("Skipping DB seed because MongoDB is unreachable.")
        return 0

    init_db_indexes()
    db = get_db()
    collection = db["recipes"]

    count = collection.count_documents({})
    if count > 0:
        logger.info(f"MongoDB recipes collection already contains {count} recipes.")
        return count

    if not recipes_filepath.exists():
        logger.error(f"Recipes file not found at {recipes_filepath}")
        return 0

    with open(recipes_filepath, "r", encoding="utf-8") as f:
        recipes_data = json.load(f)

    if recipes_data:
        result = collection.insert_many(recipes_data)
        inserted_count = len(result.inserted_ids)
        logger.info(f"Successfully seeded {inserted_count} recipes into MongoDB.")
        return inserted_count

    return 0


def fetch_all_recipes_from_db() -> Optional[List[Dict[str, Any]]]:
    """Fetches all recipes from MongoDB, omitting Mongo internal _id."""
    if not check_db_connection():
        return None

    try:
        db = get_db()
        recipes = list(db["recipes"].find({}, {"_id": 0}))
        return recipes if recipes else None
    except Exception as e:
        logger.error(f"Failed to fetch recipes from MongoDB: {e}")
        return None


# ---------------------------------------------------------------------------
# Meal Logging Operations (MongoDB with Local Persistent Fallback)
# ---------------------------------------------------------------------------

def save_meal_log(user_id: str, log_data: Dict[str, Any]) -> Dict[str, Any]:
    """Saves or updates a meal log for a specific user."""
    entry = dict(log_data)
    entry["user_id"] = user_id
    if not entry.get("id"):
        entry["id"] = f"meal_{uuid.uuid4().hex[:12]}"
    if not entry.get("logged_at"):
        entry["logged_at"] = datetime.utcnow().isoformat()

    if check_db_connection():
        try:
            db = get_db()
            db["meal_logs"].update_one(
                {"id": entry["id"], "user_id": user_id},
                {"$set": entry},
                upsert=True,
            )
        except Exception as e:
            logger.error(f"Error saving meal log to MongoDB for user {user_id}: {e}")

    # Keep local fallback synced
    local_data = _load_local_db()
    user_logs = local_data.setdefault("meal_logs", {}).setdefault(user_id, [])
    # Replace if exists or append
    existing_idx = next((i for i, item in enumerate(user_logs) if item.get("id") == entry["id"]), None)
    if existing_idx is not None:
        user_logs[existing_idx] = entry
    else:
        user_logs.append(entry)
    _save_local_db(local_data)

    safe_entry = dict(entry)
    safe_entry.pop("_id", None)
    return safe_entry


def get_user_meal_logs(user_id: str) -> List[Dict[str, Any]]:
    """Returns all meal logs for a specific user, sorted newest first."""
    if check_db_connection():
        try:
            db = get_db()
            logs = list(db["meal_logs"].find({"user_id": user_id}, {"_id": 0}).sort("logged_at", -1))
            if logs:
                return logs
        except Exception as e:
            logger.error(f"Error fetching meal logs from MongoDB for user {user_id}: {e}")

    # Fallback to local
    local_data = _load_local_db()
    logs = list(local_data.get("meal_logs", {}).get(user_id, []))
    logs.sort(key=lambda x: x.get("logged_at", ""), reverse=True)
    return logs


def delete_meal_log(user_id: str, log_id: str) -> bool:
    """Deletes a specific meal log for a user."""
    deleted = False
    if check_db_connection():
        try:
            db = get_db()
            res = db["meal_logs"].delete_one({"user_id": user_id, "id": log_id})
            deleted = res.deleted_count > 0
        except Exception as e:
            logger.error(f"Error deleting meal log in MongoDB for user {user_id}: {e}")

    local_data = _load_local_db()
    user_logs = local_data.get("meal_logs", {}).get(user_id, [])
    orig_len = len(user_logs)
    user_logs = [item for item in user_logs if item.get("id") != log_id]
    if len(user_logs) != orig_len:
        local_data["meal_logs"][user_id] = user_logs
        _save_local_db(local_data)
        deleted = True

    return deleted


# ---------------------------------------------------------------------------
# Weight Tracking Operations (MongoDB with Local Persistent Fallback)
# ---------------------------------------------------------------------------

def save_weight_log(user_id: str, weight_data: Dict[str, Any]) -> Dict[str, Any]:
    """Saves a weight entry for a specific user."""
    entry = dict(weight_data)
    entry["user_id"] = user_id
    if not entry.get("id"):
        entry["id"] = f"weight_{uuid.uuid4().hex[:12]}"
    if not entry.get("recorded_at"):
        entry["recorded_at"] = datetime.utcnow().isoformat()

    if check_db_connection():
        try:
            db = get_db()
            db["weight_logs"].update_one(
                {"id": entry["id"], "user_id": user_id},
                {"$set": entry},
                upsert=True,
            )
        except Exception as e:
            logger.error(f"Error saving weight entry in MongoDB for user {user_id}: {e}")

    local_data = _load_local_db()
    user_weights = local_data.setdefault("weight_logs", {}).setdefault(user_id, [])
    existing_idx = next((i for i, item in enumerate(user_weights) if item.get("id") == entry["id"]), None)
    if existing_idx is not None:
        user_weights[existing_idx] = entry
    else:
        user_weights.append(entry)
    _save_local_db(local_data)

    safe_entry = dict(entry)
    safe_entry.pop("_id", None)
    return safe_entry


def get_user_weight_logs(user_id: str) -> List[Dict[str, Any]]:
    """Returns all weight logs for a user, sorted newest first."""
    if check_db_connection():
        try:
            db = get_db()
            weights = list(db["weight_logs"].find({"user_id": user_id}, {"_id": 0}).sort("recorded_at", -1))
            if weights:
                return weights
        except Exception as e:
            logger.error(f"Error fetching weight logs from MongoDB for user {user_id}: {e}")

    local_data = _load_local_db()
    weights = list(local_data.get("weight_logs", {}).get(user_id, []))
    weights.sort(key=lambda x: x.get("recorded_at", ""), reverse=True)
    return weights


# ---------------------------------------------------------------------------
# Favorites Operations (MongoDB with Local Persistent Fallback)
# ---------------------------------------------------------------------------

def toggle_favorite(user_id: str, recipe_id: str) -> Dict[str, Any]:
    """Toggles a favorite recipe for a user."""
    is_favorited = False
    clean_recipe_id = str(recipe_id).strip()

    if check_db_connection():
        try:
            db = get_db()
            fav_coll = db["favorites"]
            existing = fav_coll.find_one({"user_id": user_id, "recipe_id": clean_recipe_id})
            if existing:
                fav_coll.delete_one({"user_id": user_id, "recipe_id": clean_recipe_id})
                is_favorited = False
            else:
                fav_coll.insert_one({
                    "user_id": user_id,
                    "recipe_id": clean_recipe_id,
                    "added_at": datetime.utcnow().isoformat(),
                })
                is_favorited = True
        except Exception as e:
            logger.error(f"Error toggling favorite in MongoDB for user {user_id}: {e}")

    local_data = _load_local_db()
    user_favs = local_data.setdefault("favorites", {}).setdefault(user_id, [])
    if clean_recipe_id in user_favs:
        user_favs.remove(clean_recipe_id)
        is_favorited = False
    else:
        user_favs.append(clean_recipe_id)
        is_favorited = True
    _save_local_db(local_data)

    action = "added" if is_favorited else "removed"
    return {
        "status": action,
        "is_favorited": is_favorited,
        "recipe_id": clean_recipe_id,
        "message": f"Recipe {clean_recipe_id} {action} {'to' if is_favorited else 'from'} favorites",
    }


def get_user_favorites(user_id: str) -> List[str]:
    """Returns list of recipe IDs favorited by the user."""
    if check_db_connection():
        try:
            db = get_db()
            favs = list(db["favorites"].find({"user_id": user_id}, {"_id": 0, "recipe_id": 1}))
            if favs:
                return [f["recipe_id"] for f in favs if "recipe_id" in f]
        except Exception as e:
            logger.error(f"Error fetching favorites from MongoDB for user {user_id}: {e}")

    local_data = _load_local_db()
    return list(local_data.get("favorites", {}).get(user_id, []))


# ---------------------------------------------------------------------------
# User Data Sync (Bundles All Scoped User Assets for Seamless Re-login)
# ---------------------------------------------------------------------------

def get_user_sync_data(user_id: str) -> Dict[str, Any]:
    """Fetches full state bundle (profile, meals, weights, favorites) for a user."""
    user_doc = find_user_by_id(user_id)
    profile = user_doc.get("profile") if user_doc else None
    is_onboarded = user_doc.get("is_onboarded", False) if user_doc else False
    name = user_doc.get("name", "Friend") if user_doc else "Friend"
    email = user_doc.get("email", "") if user_doc else ""

    meals = get_user_meal_logs(user_id)
    weights = get_user_weight_logs(user_id)
    favs = get_user_favorites(user_id)

    return {
        "user_id": user_id,
        "name": name,
        "email": email,
        "is_onboarded": is_onboarded,
        "profile": profile,
        "meal_logs": meals,
        "weight_logs": weights,
        "favorites": favs,
    }

