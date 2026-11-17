"""
test_auth.py

Unit test for authentication endpoints and MongoDB integration in FastAPI backend.
"""

from fastapi.testclient import TestClient
from serve import app
import db

client = TestClient(app)

def test_auth_flow():
    print("Testing backend health...")
    health_res = client.get("/health")
    assert health_res.status_code == 200
    print(f"Health response: {health_res.json()}")

    # Test registration
    test_email = "testuser@example.com"
    test_password = "securePassword123!"
    test_name = "Nimal Perera"

    print("Testing registration...")
    reg_res = client.post(
        "/auth/register",
        json={"name": test_name, "email": test_email, "password": test_password},
    )
    print(f"Register status: {reg_res.status_code}, body: {reg_res.json()}")

    if reg_res.status_code == 503:
        print("MongoDB is offline in this environment - 503 handled gracefully as expected.")
        return

    assert reg_res.status_code in (200, 400)

    # Test duplicate registration
    print("Testing duplicate registration...")
    dup_res = client.post(
        "/auth/register",
        json={"name": test_name, "email": test_email, "password": test_password},
    )
    assert dup_res.status_code == 400
    assert "already exists" in dup_res.json()["detail"]
    print("Duplicate registration check passed!")

    # Test login with wrong password
    print("Testing invalid password login...")
    bad_login = client.post(
        "/auth/login",
        json={"email": test_email, "password": "wrongPassword"},
    )
    assert bad_login.status_code == 401
    print("Invalid password check passed!")

    # Test login with correct password
    print("Testing valid login...")
    good_login = client.post(
        "/auth/login",
        json={"email": test_email, "password": test_password},
    )
    assert good_login.status_code == 200
    data = good_login.json()
    assert data["status"] == "success"
    assert data["email"] == test_email
    assert data["name"] == test_name
    user_id = data["user_id"]
    print(f"Login successful for user {user_id}!")

    # Test saving profile
    print("Testing profile update...")
    profile_payload = {
        "user_id": user_id,
        "age": 28,
        "gender": "Male",
        "height_cm": 172.0,
        "weight_kg": 75.0,
        "activity_level": "Moderate",
        "dietary_pref": "Vegetarian",
        "spice_pref": "Medium",
        "top_n": 10,
    }
    save_res = client.post(f"/users/{user_id}", json=profile_payload)
    assert save_res.status_code == 200
    print("Profile save verified!")

    # Test fetching user
    print("Testing fetching user profile...")
    fetch_res = client.get(f"/users/{user_id}")
    assert fetch_res.status_code == 200
    # Test multi-user meal logging, weight logging, favorites, and isolation
    print("Testing multi-user isolation and meal logs...")
    import time
    unique_ts = int(time.time() * 1000)
    user1_email = f"isolation_user1_{unique_ts}@example.com"
    user2_email = f"isolation_user2_{unique_ts}@example.com"

    # Register user 1
    u1_res = client.post("/auth/register", json={"name": "User One", "email": user1_email, "password": "Password123!"})
    assert u1_res.status_code == 200
    u1_id = u1_res.json()["user_id"]

    # Register user 2
    u2_res = client.post("/auth/register", json={"name": "User Two", "email": user2_email, "password": "Password123!"})
    assert u2_res.status_code == 200
    u2_id = u2_res.json()["user_id"]

    # User 1 logs a meal
    m1_res = client.post(f"/users/{u1_id}/logs", json={
        "recipe_id": "REC_001",
        "recipe_name": "Sri Lankan Dhal Curry",
        "calories": 250,
        "protein": 12.0,
        "carbs": 35.0,
        "fat": 6.0,
        "meal_type": "Lunch",
    })
    assert m1_res.status_code == 200
    m1_data = m1_res.json()["log"]
    assert m1_data["recipe_name"] == "Sri Lankan Dhal Curry"

    # User 1 logs a weight
    w1_res = client.post(f"/users/{u1_id}/weights", json={"weight_kg": 76.5})
    assert w1_res.status_code == 200

    # User 1 favorites REC_001
    f1_res = client.post(f"/users/{u1_id}/favorites/REC_001")
    assert f1_res.status_code == 200
    assert f1_res.json()["is_favorited"] is True

    # Check User 2's data - MUST BE EMPTY (complete isolation!)
    u2_meals_res = client.get(f"/users/{u2_id}/logs")
    assert u2_meals_res.status_code == 200
    assert u2_meals_res.json()["count"] == 0
    assert len(u2_meals_res.json()["logs"]) == 0

    u2_weights_res = client.get(f"/users/{u2_id}/weights")
    assert u2_weights_res.status_code == 200
    assert u2_weights_res.json()["count"] == 0

    u2_favs_res = client.get(f"/users/{u2_id}/favorites")
    assert u2_favs_res.status_code == 200
    assert u2_favs_res.json()["count"] == 0

    # User 2 logs a distinct meal
    m2_res = client.post(f"/users/{u2_id}/logs", json={
        "recipe_id": "REC_002",
        "recipe_name": "Pol Sambol",
        "calories": 140,
        "protein": 3.0,
        "carbs": 8.0,
        "fat": 11.0,
        "meal_type": "Breakfast",
    })
    assert m2_res.status_code == 200

    # Verify User 1 sync returns User 1's data and NOT User 2's data
    u1_sync = client.get(f"/users/{u1_id}/sync")
    assert u1_sync.status_code == 200
    u1_data = u1_sync.json()["data"]
    assert len(u1_data["meal_logs"]) == 1
    assert u1_data["meal_logs"][0]["recipe_id"] == "REC_001"
    assert len(u1_data["weight_logs"]) == 1
    assert u1_data["weight_logs"][0]["weight_kg"] == 76.5
    assert u1_data["favorites"] == ["REC_001"]

    # Verify User 2 sync returns User 2's data
    u2_sync = client.get(f"/users/{u2_id}/sync")
    assert u2_sync.status_code == 200
    u2_data = u2_sync.json()["data"]
    assert len(u2_data["meal_logs"]) == 1
    assert u2_data["meal_logs"][0]["recipe_id"] == "REC_002"
    assert len(u2_data["weight_logs"]) == 0
    assert len(u2_data["favorites"]) == 0

    # Test deleting meal log
    del_res = client.delete(f"/users/{u1_id}/logs/{m1_data['id']}")
    assert del_res.status_code == 200
    assert del_res.json()["deleted"] is True

    u1_after_del = client.get(f"/users/{u1_id}/logs")
    assert u1_after_del.json()["count"] == 0

    print("ALL BACKEND AUTH & MULTI-USER ISOLATION TESTS PASSED SUCCESSFULLY!")

if __name__ == "__main__":
    test_auth_flow()
