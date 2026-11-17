"""
seed_mongodb.py

CLI tool to manually seed or verify MongoDB dataset for LoseIt backend.
Usage:
    python3 seed_mongodb.py
"""

import sys
from pathlib import Path

# Add backend directory to sys.path
sys.path.append(str(Path(__file__).resolve().parent))

from db import check_db_connection, seed_recipes_if_empty, get_db, MONGODB_URL, MONGODB_DB_NAME

RECIPES_PATH = Path(__file__).resolve().parent / "data" / "recipes.json"

def main():
    print(f"Connecting to MongoDB at: {MONGODB_URL}")
    print(f"Database Name: {MONGODB_DB_NAME}")
    
    if not check_db_connection():
        print("ERROR: Could not connect to MongoDB. Ensure MongoDB service is running.")
        sys.exit(1)
        
    print("SUCCESS: Connected to MongoDB successfully.")
    
    inserted_or_existing = seed_recipes_if_empty(RECIPES_PATH)
    print(f"Recipes in database: {inserted_or_existing}")
    
    db = get_db()
    collections = db.list_collection_names()
    print(f"Collections in '{MONGODB_DB_NAME}': {collections}")

if __name__ == "__main__":
    main()
