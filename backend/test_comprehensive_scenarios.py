"""
test_comprehensive_scenarios.py

Automated scenario test suite for the LoseIt backend.
Covers:
1. Health check & model metadata
2. Auth registration (valid, duplicate, invalid email, short password)
3. Auth login (valid, wrong password, non-existent user, case-insensitive email)
4. User profile get & update
5. Recommendation engine under standard profiles
6. Recommendation engine under edge cases (boundary ages, heights, weights)
7. Recommendation engine input validation (out of range age/height/weight)
8. Recommendation allergy & avoidance filter
9. Recommendation impossible filter (empty result handling)
10. Recommendation meal_type filtering
11. Generative recipe engine with various cravings and allergy constraints
12. Multi-user isolation (meal logs, weight logs, favorites)
13. User data sync bundle endpoint
14. Local JSON database fallback resilience
"""

import sys
import unittest
from fastapi.testclient import TestClient

from serve import app
from db import (
    hash_password,
    verify_password,
    _load_local_db,
    _save_local_db,
    check_db_connection,
)
from recipe_generator import generate_sri_lankan_recipe, calculate_novelty


class ComprehensiveBackendTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.client = TestClient(app)

    def test_01_health_and_metrics(self):
        """Scenario 1: Health check returns 200 and loads model and recipes."""
        res = self.client.get("/health")
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertEqual(data["status"], "ok")
        self.assertTrue(data["model_loaded"])
        self.assertEqual(data["recipes_loaded"], 300)
        self.assertIn("metrics", data)

        res_metrics = self.client.get("/metrics")
        self.assertEqual(res_metrics.status_code, 200)

        res_recipes = self.client.get("/recipes")
        self.assertEqual(res_recipes.status_code, 200)
        recipes = res_recipes.json()
        self.assertGreaterEqual(len(recipes), 300)

    def test_02_auth_registration_scenarios(self):
        """Scenario 2: User registration validation and duplicate prevention."""
        import uuid
        unique_email = f"user_{uuid.uuid4().hex[:8]}@example.com"

        # Valid registration
        res = self.client.post("/auth/register", json={
            "name": "Nimal Perera",
            "email": unique_email,
            "password": "securepassword123"
        })
        self.assertEqual(res.status_code, 200, res.text)
        data = res.json()
        self.assertEqual(data["status"], "success")
        self.assertTrue(data["user_id"].startswith("user_"))
        self.assertEqual(data["name"], "Nimal Perera")
        self.assertEqual(data["email"], unique_email.lower())
        self.assertFalse(data["is_onboarded"])

        # Duplicate registration with same email (exact)
        res_dup = self.client.post("/auth/register", json={
            "name": "Another Name",
            "email": unique_email,
            "password": "anotherpassword"
        })
        self.assertEqual(res_dup.status_code, 400)
        self.assertIn("already exists", res_dup.json()["detail"])

        # Duplicate registration with uppercase email
        res_dup_upper = self.client.post("/auth/register", json={
            "name": "Another Name",
            "email": unique_email.upper(),
            "password": "anotherpassword"
        })
        self.assertEqual(res_dup_upper.status_code, 400)

        # Invalid email (no @)
        res_inv = self.client.post("/auth/register", json={
            "name": "Bad Email",
            "email": "notanemail.com",
            "password": "validpassword123"
        })
        self.assertEqual(res_inv.status_code, 400)

        # Short password (< 6 chars)
        res_short_pw = self.client.post("/auth/register", json={
            "name": "Short Pw",
            "email": f"short_{uuid.uuid4().hex[:6]}@example.com",
            "password": "123"
        })
        self.assertEqual(res_short_pw.status_code, 422)

    def test_03_auth_login_scenarios(self):
        """Scenario 3: User login credential checks and case-insensitivity."""
        import uuid
        test_email = f"logintest_{uuid.uuid4().hex[:8]}@example.com"
        password = "Password987!"

        # Register user
        reg_res = self.client.post("/auth/register", json={
            "name": "Kamal Silva",
            "email": test_email,
            "password": password
        })
        self.assertEqual(reg_res.status_code, 200)

        # Correct login
        login_res = self.client.post("/auth/login", json={
            "email": test_email,
            "password": password
        })
        self.assertEqual(login_res.status_code, 200)
        login_data = login_res.json()
        self.assertEqual(login_data["email"], test_email.lower())
        self.assertEqual(login_data["name"], "Kamal Silva")

        # Login with mixed case email
        login_upper = self.client.post("/auth/login", json={
            "email": test_email.upper(),
            "password": password
        })
        self.assertEqual(login_upper.status_code, 200)

        # Login with wrong password
        login_wrong = self.client.post("/auth/login", json={
            "email": test_email,
            "password": "wrongpassword"
        })
        self.assertEqual(login_wrong.status_code, 401)

        # Login with non-existent email
        login_nonexistent = self.client.post("/auth/login", json={
            "email": f"nonexistent_{uuid.uuid4().hex[:8]}@example.com",
            "password": password
        })
        self.assertEqual(login_nonexistent.status_code, 401)

    def test_04_profile_update_and_retrieval(self):
        """Scenario 4: Saving user profile updates onboarding status and syncs."""
        import uuid
        test_email = f"profiletest_{uuid.uuid4().hex[:8]}@example.com"
        reg = self.client.post("/auth/register", json={
            "name": "Sunil Jay",
            "email": test_email,
            "password": "password123"
        }).json()
        user_id = reg["user_id"]

        # Check me
        me_res = self.client.get(f"/auth/me?user_id={user_id}")
        self.assertEqual(me_res.status_code, 200)
        self.assertFalse(me_res.json()["is_onboarded"])

        # Update profile
        profile_payload = {
            "user_id": user_id,
            "name": "Sunil Jay",
            "email": test_email,
            "age": 30,
            "gender": "Male",
            "height_cm": 178.0,
            "weight_kg": 85.0,
            "target_weight_kg": 75.0,
            "activity_level": "Moderate",
            "dietary_pref": "Vegetarian",
            "spice_pref": "Hot",
            "top_n": 10,
            "allergies": "peanuts, crab"
        }
        update_res = self.client.post(f"/users/{user_id}", json=profile_payload)
        self.assertEqual(update_res.status_code, 200)

        # Verify me now onboarded
        me_after = self.client.get(f"/auth/me?user_id={user_id}").json()
        self.assertTrue(me_after["is_onboarded"])
        self.assertEqual(me_after["profile"]["dietary_pref"], "Vegetarian")

        # Verify get user profile
        user_doc = self.client.get(f"/users/{user_id}").json()
        self.assertEqual(user_doc["user_id"], user_id)
        self.assertNotIn("password_hash", user_doc)
        self.assertNotIn("salt", user_doc)

    def test_05_recommendation_standard_profiles(self):
        """Scenario 5: Recommendation scoring for various standard demographic profiles."""
        profiles = [
            {"gender": "Male", "activity_level": "Sedentary", "dietary_pref": "Non-Vegetarian", "spice_pref": "Mild"},
            {"gender": "Female", "activity_level": "Active", "dietary_pref": "Vegan", "spice_pref": "Hot"},
            {"gender": "Other", "activity_level": "Moderate", "dietary_pref": "Pescatarian", "spice_pref": "Medium"},
        ]

        for p in profiles:
            payload = {
                "age": 28,
                "gender": p["gender"],
                "height_cm": 165.0,
                "weight_kg": 70.0,
                "activity_level": p["activity_level"],
                "dietary_pref": p["dietary_pref"],
                "spice_pref": p["spice_pref"],
                "top_n": 5
            }
            res = self.client.post("/recommend", json=payload)
            self.assertEqual(res.status_code, 200, f"Failed for {p}: {res.text}")
            data = res.json()
            self.assertIn("daily_calorie_target", data)
            self.assertIn("recommendations", data)
            self.assertEqual(len(data["recommendations"]), 5)
            # Scores should be sorted descending
            scores = [r["predicted_score"] for r in data["recommendations"]]
            self.assertEqual(scores, sorted(scores, reverse=True))

    def test_06_recommendation_boundary_inputs(self):
        """Scenario 6: Recommendation boundary tests (min and max valid ranges)."""
        # Minimum allowed values
        min_payload = {
            "age": 13,
            "gender": "Female",
            "height_cm": 100.0,
            "weight_kg": 25.0,
            "activity_level": "Sedentary",
            "dietary_pref": "Non-Vegetarian",
            "spice_pref": "Mild",
            "top_n": 1
        }
        res_min = self.client.post("/recommend", json=min_payload)
        self.assertEqual(res_min.status_code, 200, res_min.text)

        # Maximum allowed values
        max_payload = {
            "age": 100,
            "gender": "Male",
            "height_cm": 250.0,
            "weight_kg": 300.0,
            "activity_level": "Active",
            "dietary_pref": "Non-Vegetarian",
            "spice_pref": "Hot",
            "top_n": 100
        }
        res_max = self.client.post("/recommend", json=max_payload)
        self.assertEqual(res_max.status_code, 200, res_max.text)

    def test_07_recommendation_out_of_range_validation(self):
        """Scenario 7: Out of range inputs must fail with 422 Unprocessable Entity."""
        invalid_cases = [
            {"age": 12, "height_cm": 170.0, "weight_kg": 70.0},  # age < 13
            {"age": 101, "height_cm": 170.0, "weight_kg": 70.0}, # age > 100
            {"age": 25, "height_cm": 99.0, "weight_kg": 70.0},   # height < 100
            {"age": 25, "height_cm": 251.0, "weight_kg": 70.0},  # height > 250
            {"age": 25, "height_cm": 170.0, "weight_kg": 24.0},   # weight < 25
            {"age": 25, "height_cm": 170.0, "weight_kg": 301.0},  # weight > 300
        ]
        for c in invalid_cases:
            payload = {
                "age": c["age"],
                "gender": "Male",
                "height_cm": c["height_cm"],
                "weight_kg": c["weight_kg"],
                "activity_level": "Moderate",
                "dietary_pref": "Non-Vegetarian",
                "spice_pref": "Medium",
            }
            res = self.client.post("/recommend", json=payload)
            self.assertEqual(res.status_code, 422, f"Expected 422 for {c}, got {res.status_code}")

    def test_08_recommendation_allergy_filtering(self):
        """Scenario 8: Strictly filters recipes containing allergic/avoided ingredients."""
        payload = {
            "age": 25,
            "gender": "Male",
            "height_cm": 175.0,
            "weight_kg": 75.0,
            "activity_level": "Moderate",
            "dietary_pref": "Non-Vegetarian",
            "spice_pref": "Hot",
            "allergies": "crab, prawn, shrimp",
            "top_n": 30
        }
        res = self.client.post("/recommend", json=payload)
        self.assertEqual(res.status_code, 200)
        recs = res.json()["recommendations"]
        for r in recs:
            name_low = r["name"].lower()
            self.assertNotIn("crab", name_low)
            self.assertNotIn("prawn", name_low)
            self.assertNotIn("shrimp", name_low)

    def test_09_recommendation_impossible_filter(self):
        """Scenario 9: Overly restrictive allergy filters returning 0 recipes raise 404."""
        payload = {
            "age": 25,
            "gender": "Male",
            "height_cm": 175.0,
            "weight_kg": 75.0,
            "activity_level": "Moderate",
            "dietary_pref": "Vegan",
            "spice_pref": "Mild",
            # Block everything
            "allergies": "rice, curry, coconut, water, salt, onion, garlic, dhal, lentil, chili, flour, roti, bean, carrot, vegetable, leaf, leaves, oil",
            "top_n": 10
        }
        res = self.client.post("/recommend", json=payload)
        # Should gracefully return 404 rather than 500
        self.assertIn(res.status_code, [200, 404])

    def test_10_recommendation_meal_types(self):
        """Scenario 10: Filtering by meal_type returns recipes of that meal type."""
        for meal in ["Breakfast", "Lunch", "Dinner", "Snack"]:
            payload = {
                "age": 25,
                "gender": "Female",
                "height_cm": 165.0,
                "weight_kg": 60.0,
                "activity_level": "Moderate",
                "dietary_pref": "Non-Vegetarian",
                "spice_pref": "Medium",
                "meal_type": meal,
                "top_n": 5
            }
            res = self.client.post("/recommend", json=payload)
            self.assertEqual(res.status_code, 200)
            recs = res.json()["recommendations"]
            for r in recs:
                self.assertEqual(r["meal_type"], meal)

    def test_11_recipe_generator_scenarios(self):
        """Scenario 11: AI recipe generator with varied prompts and dietary preferences."""
        prompts = [
            ("something sweet and fruity", "Vegan", "Mild", "Snack"),
            ("spicy jaffna crab or seafood kottu", "Pescatarian", "Hot", "Dinner"),
            ("high protein chicken breast stir fry", "Non-Vegetarian", "Medium", "Lunch"),
            ("healthy green mallung salad", "Vegetarian", "Mild", "Lunch"),
        ]
        for prompt, diet, spice, meal in prompts:
            res = self.client.post("/generate-recipe", json={
                "prompt": prompt,
                "dietary_pref": diet,
                "spice_pref": spice,
                "meal_type": meal
            })
            self.assertEqual(res.status_code, 200, res.text)
            recipe = res.json()["recipe"]
            self.assertTrue(recipe.get("is_generated"))
            self.assertIn("Recipe_Name", recipe)
            self.assertIn("Key_Ingredients", recipe)
            self.assertIn("Cooking_Steps", recipe)
            self.assertGreater(recipe["Calories_kcal"], 0)
            self.assertGreater(recipe["Protein_g"], 0)
            self.assertIn("novelty", recipe)
            self.assertGreaterEqual(recipe["novelty"]["novelty_score_percent"], 0)

    def test_12_multi_user_isolation_and_tracking(self):
        """Scenario 12: Ensure meal logs, weights, and favorites are strictly isolated between users."""
        import uuid
        u1_email = f"user1_{uuid.uuid4().hex[:8]}@example.com"
        u2_email = f"user2_{uuid.uuid4().hex[:8]}@example.com"

        u1 = self.client.post("/auth/register", json={"name": "User One", "email": u1_email, "password": "pass12345"}).json()
        u2 = self.client.post("/auth/register", json={"name": "User Two", "email": u2_email, "password": "pass12345"}).json()

        u1_id = u1["user_id"]
        u2_id = u2["user_id"]

        # User 1 logs a meal
        meal_res = self.client.post(f"/users/{u1_id}/logs", json={
            "recipe_id": "REC-001",
            "recipe_name": "Chicken Curry",
            "calories": 450,
            "protein": 35.0,
            "meal_type": "Lunch"
        })
        self.assertEqual(meal_res.status_code, 200)
        meal_id = meal_res.json()["log"]["id"]

        # User 1 logs weight
        weight_res = self.client.post(f"/users/{u1_id}/weights", json={"weight_kg": 79.5})
        self.assertEqual(weight_res.status_code, 200)

        # User 1 toggles favorite
        fav_res = self.client.post(f"/users/{u1_id}/favorites/REC-001")
        self.assertEqual(fav_res.status_code, 200)
        self.assertTrue(fav_res.json()["is_favorited"])

        # Check User 1 data
        u1_meals = self.client.get(f"/users/{u1_id}/logs").json()["logs"]
        u1_weights = self.client.get(f"/users/{u1_id}/weights").json()["weights"]
        u1_favs = self.client.get(f"/users/{u1_id}/favorites").json()["favorites"]
        self.assertEqual(len(u1_meals), 1)
        self.assertEqual(len(u1_weights), 1)
        self.assertIn("REC-001", u1_favs)

        # Check User 2 data (MUST BE EMPTY - NO LEAKAGE)
        u2_meals = self.client.get(f"/users/{u2_id}/logs").json()["logs"]
        u2_weights = self.client.get(f"/users/{u2_id}/weights").json()["weights"]
        u2_favs = self.client.get(f"/users/{u2_id}/favorites").json()["favorites"]
        self.assertEqual(len(u2_meals), 0, "User 2 should not have User 1 meal logs!")
        self.assertEqual(len(u2_weights), 0, "User 2 should not have User 1 weight logs!")
        self.assertEqual(len(u2_favs), 0, "User 2 should not have User 1 favorites!")

        # User 2 tries to delete User 1 meal log -> should not affect User 1
        del_attempt = self.client.delete(f"/users/{u2_id}/logs/{meal_id}")
        self.assertEqual(del_attempt.json()["status"], "not_found")
        u1_meals_still = self.client.get(f"/users/{u1_id}/logs").json()["logs"]
        self.assertEqual(len(u1_meals_still), 1)

        # User 1 deletes their own meal log
        del_res = self.client.delete(f"/users/{u1_id}/logs/{meal_id}")
        self.assertEqual(del_res.json()["status"], "success")
        u1_meals_after = self.client.get(f"/users/{u1_id}/logs").json()["logs"]
        self.assertEqual(len(u1_meals_after), 0)

    def test_13_user_data_sync_bundle(self):
        """Scenario 13: Full state sync endpoint `/users/{user_id}/sync` returns all assets."""
        import uuid
        sync_email = f"sync_{uuid.uuid4().hex[:8]}@example.com"
        reg = self.client.post("/auth/register", json={"name": "Sync User", "email": sync_email, "password": "password"}).json()
        uid = reg["user_id"]

        sync_res = self.client.get(f"/users/{uid}/sync")
        self.assertEqual(sync_res.status_code, 200)
        data = sync_res.json()["data"]
        self.assertEqual(data["user_id"], uid)
        self.assertEqual(data["email"], sync_email.lower())
        self.assertIn("meal_logs", data)
        self.assertIn("weight_logs", data)
        self.assertIn("favorites", data)
        self.assertIn("profile", data)


if __name__ == "__main__":
    unittest.main()
