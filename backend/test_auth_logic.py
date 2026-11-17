"""
test_auth_logic.py

Tests cryptographic password hashing, validation logic, and auth structures.
"""

import db

def test_password_security():
    print("Testing password hashing & verification...")
    password = "SuperSecretPassword123!"
    hashed, salt = db.hash_password(password)

    assert hashed != password
    assert len(salt) == 32  # 16 bytes hex
    assert len(hashed) == 64  # SHA256 hex string

    # Verify matching password
    assert db.verify_password(password, salt, hashed) is True
    print("Password verification with correct credentials passed.")

    # Verify wrong password fails
    assert db.verify_password("WrongPassword123!", salt, hashed) is False
    print("Password verification rejection of wrong password passed.")

    # Verify unique salts produce different hashes for the same password
    hashed2, salt2 = db.hash_password(password)
    assert salt != salt2
    assert hashed != hashed2
    print("Salt uniqueness check passed.")

    print("ALL AUTH SECURITY UNIT TESTS PASSED!")

if __name__ == "__main__":
    test_password_security()
