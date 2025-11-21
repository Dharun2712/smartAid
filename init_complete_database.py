"""
Complete Database Initialization for Smart Ambulance System
Creates all necessary data for Clients, Drivers, Admins, Hospitals
"""
import bcrypt
from pymongo import MongoClient
from datetime import datetime
from bson import ObjectId

# MongoDB Connection
MONGO_URI = "mongodb+srv://Dharun:Dharun2712@cluster0.yr5quzl.mongodb.net/?retryWrites=true&w=majority&appName=Cluster0"
client = MongoClient(MONGO_URI)
db = client["smart_ambulance"]

# Collections
users_collection = db["users"]
ambulance_drivers_collection = db["ambulance_drivers"]
hospitals_collection = db["hospitals"]
patient_requests_collection = db["patient_requests"]

def create_password_hash(password):
    """Generate bcrypt hash for password"""
    return bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt())

def clear_all_collections():
    """Clear all collections for fresh start"""
    print("\n🗑️  Clearing existing data...")
    users_collection.delete_many({})
    ambulance_drivers_collection.delete_many({})
    hospitals_collection.delete_many({})
    patient_requests_collection.delete_many({})
    print("✅ All collections cleared!")

def create_users():
    """Create user accounts for all roles"""
    print("\n👥 Creating Users...")
    
    users = [
        # Client Users
        {
            "role": "client",
            "name": "John Doe",
            "email": "client@example.com",
            "phone": "9876543210",
            "password": create_password_hash("Client123"),
            "features": {"grok_code_fast_1": True},
            "created_at": datetime.utcnow()
        },
        {
            "role": "client",
            "name": "Client Two",
            "email": "client2@example.com",
            "phone": "9876543211",
            "password": create_password_hash("Client1234"),
            "features": {"grok_code_fast_1": True},
            "created_at": datetime.utcnow()
        },
        {
            "role": "client",
            "name": "Client Three",
            "email": "client3@example.com",
            "phone": "9876543212",
            "password": create_password_hash("Client123"),
            "features": {"grok_code_fast_1": True},
            "created_at": datetime.utcnow()
        },
        {
            "role": "client",
            "name": "Jane Smith",
            "email": "jane.smith@example.com",
            "phone": "9876543213",
            "password": create_password_hash("Client123"),
            "features": {"grok_code_fast_1": True},
            "created_at": datetime.utcnow()
        },
        # Driver Users
        {
            "role": "driver",
            "name": "Driver One",
            "driver_id": "drive123",
            "phone": "9999999999",
            "password": create_password_hash("drive@123"),
            "created_at": datetime.utcnow()
        },
        {
            "role": "driver",
            "name": "Driver Two",
            "driver_id": "drive456",
            "phone": "8888888888",
            "password": create_password_hash("drive@123"),
            "created_at": datetime.utcnow()
        },
        {
            "role": "driver",
            "name": "Driver Three",
            "driver_id": "drive789",
            "phone": "7777777777",
            "password": create_password_hash("drive@123"),
            "created_at": datetime.utcnow()
        },
        {
            "role": "driver",
            "name": "Driver Four",
            "driver_id": "drive101",
            "phone": "6666666666",
            "password": create_password_hash("drive@123"),
            "created_at": datetime.utcnow()
        },
        # Admin Users (Hospital Admins)
        {
            "role": "admin",
            "name": "Apollo Hospital Admin",
            "hospital_code": "hospital1",
            "password": create_password_hash("hospital@1"),
            "created_at": datetime.utcnow()
        },
        {
            "role": "admin",
            "name": "City Medical Center Admin",
            "hospital_code": "hospital2",
            "password": create_password_hash("hospital@2"),
            "created_at": datetime.utcnow()
        },
        {
            "role": "admin",
            "name": "Emergency Care Hospital Admin",
            "hospital_code": "hospital3",
            "password": create_password_hash("hospital@3"),
            "created_at": datetime.utcnow()
        }
    ]
    
    result = users_collection.insert_many(users)
    print(f"✅ Created {len(result.inserted_ids)} users")
    return result.inserted_ids, users

def create_ambulance_drivers(user_ids, users):
    """Create ambulance driver profiles with locations"""
    print("\n🚑 Creating Ambulance Drivers...")
    
    # Get driver user IDs
    driver_users = [u for u in users if u.get("role") == "driver"]
    driver_user_ids = [uid for uid, u in zip(user_ids, users) if u.get("role") == "driver"]
    
    # Locations around Mountain View, CA (example area)
    driver_locations = [
        [-122.085, 37.422],  # Mountain View
        [-122.080, 37.425],  # Nearby
        [-122.090, 37.420],  # Nearby
        [-122.088, 37.418]   # Nearby
    ]
    
    ambulance_drivers = []
    for i, (driver_id, driver_user) in enumerate(zip(driver_user_ids, driver_users)):
        ambulance_drivers.append({
            "user_id": driver_id,
            "name": driver_user["name"],
            "phone": driver_user["phone"],
            "driver_id": driver_user["driver_id"],
            "status": "available",
            "active": True,
            "location": {
                "type": "Point",
                "coordinates": driver_locations[i]
            },
            "current_request": None,
            "vehicle": {
                "type": "ambulance",
                "plate": f"AMB-{i+1:03d}",
                "model": ["Mercedes Sprinter", "Ford Transit", "Toyota Hiace", "Nissan NV"][i % 4]
            },
            "rating": 4.5 + (i * 0.1),
            "total_trips": i * 50,
            "created_at": datetime.utcnow()
        })
    
    result = ambulance_drivers_collection.insert_many(ambulance_drivers)
    print(f"✅ Created {len(result.inserted_ids)} ambulance drivers")
    return result.inserted_ids

def create_hospitals(user_ids, users):
    """Create hospital profiles with locations"""
    print("\n🏥 Creating Hospitals...")
    
    # Get admin user IDs
    admin_users = [u for u in users if u.get("role") == "admin"]
    admin_user_ids = [uid for uid, u in zip(user_ids, users) if u.get("role") == "admin"]
    
    # Hospital locations around the area
    hospital_data = [
        {
            "name": "Apollo Medical Center",
            "code": "hospital1",
            "location": [-122.082, 37.424],
            "address": "123 Medical Plaza, Mountain View, CA 94043",
            "specializations": ["Emergency Care", "Trauma", "Cardiology", "Neurology"],
            "bed_capacity": 200,
            "available_beds": 45
        },
        {
            "name": "City General Hospital",
            "code": "hospital2",
            "location": [-122.088, 37.421],
            "address": "456 Health Street, Mountain View, CA 94041",
            "specializations": ["Emergency Care", "Orthopedics", "Pediatrics", "ICU"],
            "bed_capacity": 150,
            "available_beds": 32
        },
        {
            "name": "Emergency Care Center",
            "code": "hospital3",
            "location": [-122.092, 37.419],
            "address": "789 Care Avenue, Mountain View, CA 94040",
            "specializations": ["Emergency Care", "Surgery", "Critical Care"],
            "bed_capacity": 100,
            "available_beds": 28
        }
    ]
    
    hospitals = []
    for i, (admin_id, admin_user, hosp_data) in enumerate(zip(admin_user_ids, admin_users, hospital_data)):
        hospitals.append({
            "user_id": admin_id,
            "name": hosp_data["name"],
            "hospital_code": hosp_data["code"],
            "location": {
                "type": "Point",
                "coordinates": hosp_data["location"]
            },
            "address": hosp_data["address"],
            "phone": f"555-{1000+i:04d}",
            "emergency_phone": f"911-{2000+i:04d}",
            "specializations": hosp_data["specializations"],
            "facilities": {
                "emergency_room": True,
                "icu": True,
                "operation_theater": True,
                "ambulance_service": True,
                "blood_bank": True
            },
            "bed_capacity": hosp_data["bed_capacity"],
            "available_beds": hosp_data["available_beds"],
            "status": "active",
            "rating": 4.2 + (i * 0.2),
            "created_at": datetime.utcnow()
        })
    
    result = hospitals_collection.insert_many(hospitals)
    print(f"✅ Created {len(result.inserted_ids)} hospitals")
    return result.inserted_ids

def create_sample_requests(user_ids, driver_ids, hospital_ids, users):
    """Create sample patient requests for testing"""
    print("\n📋 Creating Sample Patient Requests...")
    
    # Get client user IDs
    client_user_ids = [uid for uid, u in zip(user_ids, users) if u.get("role") == "client"]
    client_users = [u for u in users if u.get("role") == "client"]
    
    # Sample requests
    sample_requests = [
        # Completed request
        {
            "client_id": client_user_ids[0],
            "user_name": client_users[0]["name"],
            "user_contact": client_users[0]["phone"],
            "driver_id": driver_ids[0],
            "hospital_id": hospital_ids[0],
            "location": {
                "type": "Point",
                "coordinates": [-122.084, 37.423]
            },
            "condition": "chest_pain",
            "preliminary_severity": "high",
            "injury_level": "critical",
            "status": "completed",
            "auto_triggered": False,
            "sensor_data": {},
            "vitals": {
                "heart_rate": 110,
                "blood_pressure": "140/90",
                "oxygen_level": 92
            },
            "picked_up_at": datetime.utcnow(),
            "accepted_at": datetime.utcnow(),
            "assigned_at": datetime.utcnow(),
            "completed_at": datetime.utcnow(),
            "timestamp": datetime.utcnow()
        },
        # In-transit request
        {
            "client_id": client_user_ids[1],
            "user_name": client_users[1]["name"],
            "user_contact": client_users[1]["phone"],
            "driver_id": driver_ids[1],
            "hospital_id": hospital_ids[1],
            "location": {
                "type": "Point",
                "coordinates": [-122.086, 37.421]
            },
            "condition": "accident",
            "preliminary_severity": "medium",
            "injury_level": "moderate",
            "status": "in_transit",
            "auto_triggered": True,
            "sensor_data": {
                "impact_force": 8.5,
                "sudden_stop": True
            },
            "vitals": {
                "heart_rate": 95,
                "blood_pressure": "130/85"
            },
            "picked_up_at": datetime.utcnow(),
            "accepted_at": datetime.utcnow(),
            "assigned_at": datetime.utcnow(),
            "timestamp": datetime.utcnow()
        }
    ]
    
    result = patient_requests_collection.insert_many(sample_requests)
    print(f"✅ Created {len(result.inserted_ids)} sample patient requests")

def display_summary():
    """Display database summary"""
    print("\n" + "="*70)
    print("📊 DATABASE INITIALIZATION SUMMARY")
    print("="*70)
    
    # Users
    users = list(users_collection.find())
    clients = [u for u in users if u.get("role") == "client"]
    drivers = [u for u in users if u.get("role") == "driver"]
    admins = [u for u in users if u.get("role") == "admin"]
    
    print(f"\n👥 USERS: {len(users)} total")
    print(f"   📱 Clients: {len(clients)}")
    for c in clients:
        print(f"      • {c['email']} / {c.get('phone', 'N/A')} (Password: Client123 or Client1234)")
    
    print(f"\n   🚗 Drivers: {len(drivers)}")
    for d in drivers:
        print(f"      • {d['driver_id']} - {d['name']} (Password: drive@123)")
    
    print(f"\n   👨‍⚕️ Admins: {len(admins)}")
    for a in admins:
        print(f"      • {a['hospital_code']} - {a['name']} (Password: hospital@1/2/3)")
    
    # Ambulance Drivers
    amb_drivers = list(ambulance_drivers_collection.find())
    print(f"\n🚑 AMBULANCE DRIVERS: {len(amb_drivers)}")
    for ad in amb_drivers:
        coords = ad['location']['coordinates']
        print(f"   • {ad['driver_id']} - {ad['name']} ({ad['status']}) at [{coords[0]:.3f}, {coords[1]:.3f}]")
    
    # Hospitals
    hospitals = list(hospitals_collection.find())
    print(f"\n🏥 HOSPITALS: {len(hospitals)}")
    for h in hospitals:
        coords = h['location']['coordinates']
        print(f"   • {h['hospital_code']} - {h['name']}")
        print(f"     Location: [{coords[0]:.3f}, {coords[1]:.3f}]")
        print(f"     Beds: {h['available_beds']}/{h['bed_capacity']} available")
        print(f"     Specializations: {', '.join(h['specializations'][:3])}")
    
    # Patient Requests
    requests = list(patient_requests_collection.find())
    print(f"\n📋 PATIENT REQUESTS: {len(requests)}")
    for r in requests:
        print(f"   • {r['user_name']} - {r['condition']} ({r['status']})")
    
    print("\n" + "="*70)
    print("✅ DATABASE READY FOR TESTING!")
    print("="*70)
    
    print("\n🔐 LOGIN CREDENTIALS:")
    print("\n  CLIENT ACCOUNTS:")
    print("    client@example.com / Client123")
    print("    client2@example.com / Client1234")
    print("    client3@example.com / Client123")
    print("    jane.smith@example.com / Client123")
    
    print("\n  DRIVER ACCOUNTS:")
    print("    drive123 / drive@123")
    print("    drive456 / drive@123")
    print("    drive789 / drive@123")
    print("    drive101 / drive@123")
    
    print("\n  ADMIN ACCOUNTS:")
    print("    hospital1 / hospital@1")
    print("    hospital2 / hospital@2")
    print("    hospital3 / hospital@3")
    
    print("\n" + "="*70 + "\n")

def main():
    """Main initialization function"""
    print("\n" + "="*70)
    print("🚑 SMART AMBULANCE - COMPLETE DATABASE INITIALIZATION")
    print("="*70)
    
    try:
        # Clear existing data
        clear_all_collections()
        
        # Create all data
        user_ids, users = create_users()
        driver_ids = create_ambulance_drivers(user_ids, users)
        hospital_ids = create_hospitals(user_ids, users)
        create_sample_requests(user_ids, driver_ids, hospital_ids, users)
        
        # Display summary
        display_summary()
        
    except Exception as e:
        print(f"\n❌ Error during initialization: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    main()
