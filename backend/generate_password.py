import bcrypt

# Generate password hashes for test users
password = b"Test123"  # The password we'll use

hash1 = bcrypt.hashpw(password, bcrypt.gensalt())
print("Password: Test123")
print("Bcrypt hash (copy this to MongoDB):")
print(hash1)
print("\n" + "="*50 + "\n")

# You can also test if a password matches
test_password = b"Test123"
if bcrypt.checkpw(test_password, hash1):
    print("✓ Password verification works!")
else:
    print("✗ Password verification failed")
