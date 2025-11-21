"""
Check and create ambulance drivers for testing
"""
from models import db, users, ambulance_drivers
from bson import ObjectId

# Check existing drivers
print("\n" + "="*60)
print("🚑 Checking Ambulance Drivers")
print("="*60 + "\n")

drivers = list(ambulance_drivers.find())
print(f"Total drivers in database: {len(drivers)}")

if drivers:
    for driver in drivers:
        print(f"\nDriver ID: {driver['_id']}")
        print(f"  User ID: {driver.get('user_id')}")
        print(f"  Name: {driver.get('name')}")
        print(f"  Status: {driver.get('status')}")
        print(f"  Active: {driver.get('active')}")
        print(f"  Has location: {'location' in driver}")
        if 'location' in driver:
            print(f"  Location: {driver['location']}")
else:
    print("❌ No ambulance drivers found!")
    print("\n💡 Creating test drivers...")
    
    # Find the driver user
    driver_user = users.find_one({"driver_id": "drive123"})
    
    if driver_user:
        # Create ambulance driver entry with location
        test_drivers = [
            {
                "user_id": driver_user["_id"],
                "name": driver_user.get("name", "Test Driver"),
                "phone": driver_user.get("phone", "9999999999"),
                "driver_id": "drive123",
                "status": "available",
                "active": True,
                "location": {
                    "type": "Point",
                    "coordinates": [-122.085, 37.422]  # Near Mountain View, CA
                },
                "current_request": None,
                "vehicle": {
                    "type": "ambulance",
                    "plate": "AMB-001",
                    "model": "Mercedes Sprinter"
                }
            },
            {
                "user_id": ObjectId(),  # Dummy ID for second driver
                "name": "Driver Two",
                "phone": "8888888888",
                "driver_id": "drive456",
                "status": "available",
                "active": True,
                "location": {
                    "type": "Point",
                    "coordinates": [-122.080, 37.425]  # Nearby location
                },
                "current_request": None,
                "vehicle": {
                    "type": "ambulance",
                    "plate": "AMB-002",
                    "model": "Ford Transit"
                }
            },
            {
                "user_id": ObjectId(),  # Dummy ID for third driver
                "name": "Driver Three",
                "phone": "7777777777",
                "driver_id": "drive789",
                "status": "available",
                "active": True,
                "location": {
                    "type": "Point",
                    "coordinates": [-122.090, 37.420]  # Nearby location
                },
                "current_request": None,
                "vehicle": {
                    "type": "ambulance",
                    "plate": "AMB-003",
                    "model": "Toyota Hiace"
                }
            }
        ]
        
        result = ambulance_drivers.insert_many(test_drivers)
        print(f"✅ Created {len(result.inserted_ids)} test drivers!")
        
        # Display created drivers
        for driver in test_drivers:
            print(f"\nCreated Driver:")
            print(f"  Name: {driver['name']}")
            print(f"  Driver ID: {driver['driver_id']}")
            print(f"  Status: {driver['status']}")
            print(f"  Location: {driver['location']['coordinates']}")
    else:
        print("❌ Driver user (drive123) not found in users collection!")
        print("Please run create_users.py first.")

print("\n" + "="*60)
print("✅ Check completed!")
print("="*60 + "\n")
