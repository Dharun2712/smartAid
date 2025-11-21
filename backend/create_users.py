"""
Create test users for Smart Ambulance System
This script creates Client, Driver, and Admin users in MongoDB
"""
import bcrypt
from pymongo import MongoClient
from datetime import datetime

# MongoDB Connection
MONGO_URI = "mongodb+srv://Dharun:Dharun2712@cluster0.yr5quzl.mongodb.net/?retryWrites=true&w=majority&appName=Cluster0"
client = MongoClient(MONGO_URI)
db = client["smart_ambulance"]
users_collection = db["users"]

def create_password_hash(password):
    """Generate bcrypt hash for password"""
    return bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt())

def create_client_user(email, phone, password, name):
    """Create a client user"""
    existing = users_collection.find_one({"$or": [{"email": email}, {"phone": phone}]})
    if existing:
        print(f"❌ Client user with email '{email}' or phone '{phone}' already exists!")
        return None
    
    user = {
        "role": "client",
        "name": name,
        "email": email,
        "phone": phone,
        "password": create_password_hash(password),
        "features": {
            "grok_code_fast_1": True
        },
        "created_at": datetime.utcnow()
    }
    result = users_collection.insert_one(user)
    print(f"✅ Client created: {email} / {phone} | Password: {password} | Grok Code Fast 1: Enabled")
    return result.inserted_id

def create_driver_user(driver_id, password, name, phone=None):
    """Create a driver user"""
    existing = users_collection.find_one({"driver_id": driver_id})
    if existing:
        print(f"❌ Driver with ID '{driver_id}' already exists!")
        return None
    
    user = {
        "role": "driver",
        "name": name,
        "driver_id": driver_id,
        "password": create_password_hash(password),
        "created_at": datetime.utcnow()
    }
    if phone:
        user["phone"] = phone
    
    result = users_collection.insert_one(user)
    print(f"✅ Driver created: {driver_id} | Password: {password}")
    return result.inserted_id

def enable_grok_fast_for_existing_clients():
    """Enable Grok Code Fast 1 feature for all existing clients"""
    result = users_collection.update_many(
        {"role": "client"},
        {"$set": {"features.grok_code_fast_1": True}}
    )
    print(f"✅ Enabled Grok Code Fast 1 for {result.modified_count} existing clients")
    return result.modified_count

def create_admin_user(hospital_code, password, name):
    """Create an admin user"""
    existing = users_collection.find_one({"hospital_code": hospital_code})
    if existing:
        print(f"❌ Admin with hospital code '{hospital_code}' already exists!")
        return None
    
    user = {
        "role": "admin",
        "name": name,
        "hospital_code": hospital_code,
        "password": create_password_hash(password),
        "created_at": datetime.utcnow()
    }
    result = users_collection.insert_one(user)
    print(f"✅ Admin created: {hospital_code} | Password: {password}")
    return result.inserted_id

def main():
    print("\n" + "="*60)
    print("🏥 Smart Ambulance - User Creation Script")
    print("="*60 + "\n")
    
    # Create Client User
    print("📱 Creating CLIENT user...")
    create_client_user(
        email="client@example.com",
        phone="9876543210",
        password="Client123",
        name="John Doe (Client)"
    )
    
    # Create Additional Client Users
    print("\n📱 Creating CLIENT2 user...")
    create_client_user(
        email="client2@example.com",
        phone="9876543211",
        password="Client1234",
        name="Client Two"
    )
    
    print("\n📱 Creating CLIENT3 user...")
    create_client_user(
        email="client3@example.com",
        phone="9876543212",
        password="Client123",
        name="Client Three"
    )
    
    # Create Driver User with your specifications
    print("\n🚗 Creating DRIVER user...")
    create_driver_user(
        driver_id="drive123",
        password="drive@123",
        name="Driver User",
        phone="9999999999"
    )
    
    # Create Admin User with your specifications
    print("\n👨‍⚕️ Creating ADMIN user...")
    create_admin_user(
        hospital_code="hospital1",
        password="hospital@1",
        name="Hospital Admin"
    )
    
    # Enable Grok Code Fast 1 for all clients
    print("\n⚡ Enabling Grok Code Fast 1 feature...")
    enable_grok_fast_for_existing_clients()
    
    print("\n" + "="*60)
    print("✅ User creation completed!")
    print("="*60)
    
    # Display login credentials
    print("\n📋 LOGIN CREDENTIALS:\n")
    print("CLIENT:")
    print("  Email: client@example.com")
    print("  Phone: 9876543210")
    print("  Password: Client123")
    print()
    print("CLIENT2:")
    print("  Email: client2@example.com")
    print("  Phone: 9876543211")
    print("  Password: Client123")
    print()
    print("CLIENT3:")
    print("  Email: client3@example.com")
    print("  Phone: 9876543212")
    print("  Password: Client123")
    print()
    print("DRIVER:")
    print("  Driver ID: drive123")
    print("  Password: drive@123")
    print()
    print("ADMIN:")
    print("  Hospital Code: hospital1")
    print("  Password: hospital@1")
    print("\n" + "="*60)
    
    # Show user count
    total_users = users_collection.count_documents({})
    clients = users_collection.count_documents({"role": "client"})
    drivers = users_collection.count_documents({"role": "driver"})
    admins = users_collection.count_documents({"role": "admin"})
    
    print(f"\n📊 Database Statistics:")
    print(f"  Total users: {total_users}")
    print(f"  Clients: {clients}")
    print(f"  Drivers: {drivers}")
    print(f"  Admins: {admins}")
    print("="*60 + "\n")

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
