"""
Insert demo SOS requests into MongoDB for testing hospital dashboard
Run this script once to populate the database with sample data
"""
import os
import datetime
from pymongo import MongoClient
from bson import ObjectId

# MongoDB connection
MONGO_URI = os.environ.get(
    "MONGO_URI",
    "mongodb+srv://Dharun:Dharun2712@cluster0.yr5quzl.mongodb.net/?retryWrites=true&w=majority&appName=Cluster0"
)

client = MongoClient(MONGO_URI)
db = client["smart_ambulance"]
patient_requests = db["patient_requests"]
users = db["users"]

print("🔄 Inserting demo SOS requests into MongoDB...")

# Sample demo data
demo_requests = [
    {
        "client_id": ObjectId(),  # Will be replaced with actual client ID if found
        "user_name": "Ravi Kumar",
        "user_contact": "+919876543210",
        "driver_id": ObjectId(),  # Will be replaced with actual driver ID if found
        "driver_name": "John Doe",
        "driver_contact": "+911234567890",
        "vehicle": "Ambulance 12",
        "hospital_id": None,
        "location": {
            "type": "Point",
            "coordinates": [77.6143, 12.9345]  # [lng, lat] Bangalore
        },
        "condition": "trauma",
        "preliminary_severity": "high",
        "injury_level": "high",
        "injury_risk": "high",
        "injury_notes": "Fractured leg with severe bleeding. Patient conscious but in pain.",
        "status": "assessed",
        "auto_triggered": False,
        "sensor_data": {},
        "vitals": {"pulse": 95, "bp": "120/80"},
        "picked_up_at": datetime.datetime.utcnow(),
        "accepted_at": datetime.datetime.utcnow() - datetime.timedelta(minutes=10),
        "assigned_at": datetime.datetime.utcnow() - datetime.timedelta(minutes=10),
        "assessment_time": datetime.datetime.utcnow() - datetime.timedelta(minutes=2),
        "timestamp": datetime.datetime.utcnow() - datetime.timedelta(minutes=15)
    },
    {
        "client_id": ObjectId(),
        "user_name": "Priya Sharma",
        "user_contact": "+919823456789",
        "driver_id": ObjectId(),
        "driver_name": "Amit Patel",
        "driver_contact": "+919922334455",
        "vehicle": "Ambulance 07",
        "hospital_id": None,
        "location": {
            "type": "Point",
            "coordinates": [77.5946, 12.9716]  # Bangalore MG Road
        },
        "condition": "cardiac",
        "preliminary_severity": "medium",
        "injury_level": "medium",
        "injury_risk": "medium",
        "injury_notes": "Chest pain, suspected cardiac issue. Patient stable, conscious.",
        "status": "assessed",
        "auto_triggered": False,
        "sensor_data": {},
        "vitals": {"pulse": 88, "bp": "130/85"},
        "picked_up_at": datetime.datetime.utcnow() - datetime.timedelta(minutes=3),
        "accepted_at": datetime.datetime.utcnow() - datetime.timedelta(minutes=8),
        "assigned_at": datetime.datetime.utcnow() - datetime.timedelta(minutes=8),
        "assessment_time": datetime.datetime.utcnow() - datetime.timedelta(minutes=1),
        "timestamp": datetime.datetime.utcnow() - datetime.timedelta(minutes=10)
    },
    {
        "client_id": ObjectId(),
        "user_name": "Suresh Kumar",
        "user_contact": "+919977665544",
        "driver_id": ObjectId(),
        "driver_name": "Rajesh Singh",
        "driver_contact": "+919811223344",
        "vehicle": "Ambulance 15",
        "hospital_id": None,
        "location": {
            "type": "Point",
            "coordinates": [77.6412, 12.9082]  # HSR Layout Bangalore
        },
        "condition": "accident",
        "preliminary_severity": "low",
        "injury_level": "low",
        "injury_risk": "low",
        "injury_notes": "Minor head injury from bike accident. Patient alert and responsive.",
        "status": "assessed",
        "auto_triggered": False,
        "sensor_data": {},
        "vitals": {"pulse": 78, "bp": "115/75"},
        "picked_up_at": datetime.datetime.utcnow() - datetime.timedelta(minutes=5),
        "accepted_at": datetime.datetime.utcnow() - datetime.timedelta(minutes=12),
        "assigned_at": datetime.datetime.utcnow() - datetime.timedelta(minutes=12),
        "assessment_time": datetime.datetime.utcnow() - datetime.timedelta(minutes=3),
        "timestamp": datetime.datetime.utcnow() - datetime.timedelta(minutes=18)
    },
    {
        "client_id": ObjectId(),
        "user_name": "Anita Desai",
        "user_contact": "+919888776655",
        "driver_id": ObjectId(),
        "driver_name": "Vikram Rao",
        "driver_contact": "+919933445566",
        "vehicle": "Ambulance 03",
        "hospital_id": None,
        "location": {
            "type": "Point",
            "coordinates": [77.5837, 12.9352]  # Indiranagar Bangalore
        },
        "condition": "respiratory",
        "preliminary_severity": "high",
        "injury_level": "high",
        "injury_risk": "high",
        "injury_notes": "Difficulty breathing, possible asthma attack. Needs urgent attention.",
        "status": "assessed",
        "auto_triggered": False,
        "sensor_data": {},
        "vitals": {"pulse": 102, "bp": "125/82"},
        "picked_up_at": datetime.datetime.utcnow() - datetime.timedelta(minutes=2),
        "accepted_at": datetime.datetime.utcnow() - datetime.timedelta(minutes=6),
        "assigned_at": datetime.datetime.utcnow() - datetime.timedelta(minutes=6),
        "assessment_time": datetime.datetime.utcnow() - datetime.timedelta(minutes=1),
        "timestamp": datetime.datetime.utcnow() - datetime.timedelta(minutes=7)
    }
]

# Try to get real user IDs from database if they exist
try:
    client_user = users.find_one({"role": "client"})
    driver_user = users.find_one({"role": "driver"})
    
    if client_user:
        print(f"✅ Found client user: {client_user.get('name', 'Unknown')}")
        # Update all demo requests with real client ID
        for req in demo_requests:
            req["client_id"] = client_user["_id"]
    
    if driver_user:
        print(f"✅ Found driver user: {driver_user.get('name', 'Unknown')}")
        # Update demo requests with real driver ID
        for req in demo_requests:
            req["driver_id"] = driver_user["_id"]
except Exception as e:
    print(f"⚠️ Could not fetch real user IDs: {e}")
    print("   Using placeholder ObjectIds instead")

# Insert demo data
try:
    result = patient_requests.insert_many(demo_requests)
    print(f"\n✅ Successfully inserted {len(result.inserted_ids)} demo SOS requests!")
    print(f"\n📋 Inserted Request IDs:")
    for idx, req_id in enumerate(result.inserted_ids, 1):
        print(f"   {idx}. {req_id}")
    
    print(f"\n🏥 Hospital dashboard will now show these {len(demo_requests)} requests!")
    print("\n💡 To view them in your Flutter app:")
    print("   1. Open Hospital Dashboard")
    print("   2. Refresh or restart the page")
    print("   3. You'll see patients: Ravi Kumar, Priya Sharma, Suresh Kumar, Anita Desai")
    
except Exception as e:
    print(f"❌ Error inserting data: {e}")

print("\n✅ Done!")
