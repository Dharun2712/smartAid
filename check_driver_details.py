#!/usr/bin/env python3
"""Check driver details including driver_id"""

from pymongo import MongoClient
from bson import ObjectId

# MongoDB connection
client = MongoClient("mongodb+srv://Dharun:Dharun2712@cluster0.yr5quzl.mongodb.net/")
db = client["smart_ambulance"]
users = db["users"]
ambulance_drivers = db["ambulance_drivers"]

# User ID
user_id = "68ff86c1d8a5d6f6c028cb4f"

print("\n" + "="*70)
print("DRIVER ACCOUNT DETAILS")
print("="*70 + "\n")

# Get user info
user = users.find_one({"_id": ObjectId(user_id)})
if user:
    print("👤 USER ACCOUNT:")
    print(f"   Name: {user.get('name')}")
    print(f"   Email: {user.get('email')}")
    print(f"   Phone: {user.get('phone')}")
    print(f"   Role: {user.get('role')}")
    print(f"   Verified: {user.get('verified')}")
    
    # Get driver details
    driver = ambulance_drivers.find_one({"user_id": ObjectId(user_id)})
    if driver:
        print(f"\n🚗 DRIVER DETAILS:")
        print(f"   Driver ID: {driver.get('driver_id')} ⭐ USE THIS TO LOGIN")
        print(f"   License: {driver.get('license_number')}")
        print(f"   Vehicle: {driver.get('vehicle')}")
        print(f"   Status: {driver.get('status')}")
        
        print(f"\n🔐 LOGIN CREDENTIALS:")
        print(f"   Driver ID: {driver.get('driver_id')}")
        print(f"   Password: [You need to remember or reset it]")
        
    else:
        print(f"\n⚠️ No driver record found in ambulance_drivers collection")
        print(f"   This user might not be properly registered as a driver")
else:
    print(f"❌ User not found with ID: {user_id}")

print("\n" + "="*70 + "\n")
