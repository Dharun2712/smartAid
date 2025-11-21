#!/usr/bin/env python3
"""List all drivers with their login credentials"""

from pymongo import MongoClient

client = MongoClient("mongodb+srv://Dharun:Dharun2712@cluster0.yr5quzl.mongodb.net/")
db = client["smart_ambulance"]

print("\n" + "="*70)
print("ALL DRIVERS IN DATABASE")
print("="*70)

# Get all drivers
drivers = list(db.ambulance_drivers.find({}))
users_with_driver_role = list(db.users.find({"role": "driver"}))

print(f"\nFound {len(drivers)} drivers in ambulance_drivers collection")
print(f"Found {len(users_with_driver_role)} users with role='driver'\n")

if drivers:
    for driver in drivers:
        user_id = driver.get("user_id")
        user = db.users.find_one({"_id": user_id})
        
        print(f"\n🚗 Driver ID: {driver.get('driver_id')} ⭐ USE THIS TO LOGIN")
        print(f"   Name: {user.get('name') if user else 'N/A'}")
        print(f"   Email: {user.get('email') if user else 'N/A'}")
        print(f"   Phone: {user.get('phone') if user else 'N/A'}")
        print(f"   Vehicle: {driver.get('vehicle')}")
        print(f"   License: {driver.get('license_number')}")
        print(f"   Status: {driver.get('status')}")
        print(f"   Password: [Hashed - you must remember it or reset it]")
        print(f"   ---")
else:
    print("❌ No drivers found!")

print("\n" + "="*70 + "\n")
