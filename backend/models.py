"""
Data models and database initialization for Smart Ambulance System
"""
from pymongo import MongoClient, GEOSPHERE
import os

MONGO_URI = os.environ.get(
    "MONGO_URI",
    "mongodb+srv://Dharun:Dharun2712@cluster0.yr5quzl.mongodb.net/?retryWrites=true&w=majority&appName=Cluster0"
)

client = MongoClient(MONGO_URI)
db = client["smart_ambulance"]

# Collections
users = db["users"]
ambulance_drivers = db["ambulance_drivers"]
hospitals = db["hospitals"]
patient_requests = db["patient_requests"]

def init_indexes():
    """Create geospatial indexes for location-based queries"""
    try:
        # Geospatial index on ambulance_drivers location
        ambulance_drivers.create_index([("location", GEOSPHERE)])
        
        # Geospatial index on hospitals location
        hospitals.create_index([("location", GEOSPHERE)])
        
        # Geospatial index on patient_requests location
        patient_requests.create_index([("location", GEOSPHERE)])
        
        # Regular indexes for faster queries
        users.create_index("email")
        users.create_index("phone")
        users.create_index("role")
        patient_requests.create_index("status")
        patient_requests.create_index("client_id")
        patient_requests.create_index("driver_id")
        
        print("✅ MongoDB indexes created successfully")
    except Exception as e:
        print(f"⚠️  Index creation warning: {e}")

# Call on module import
init_indexes()
