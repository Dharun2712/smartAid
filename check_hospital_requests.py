#!/usr/bin/env python3
"""Check what requests should be visible in hospital dashboard"""

from pymongo import MongoClient
from bson import ObjectId
import datetime

# MongoDB connection
client = MongoClient("mongodb+srv://Dharun:Dharun2712@cluster0.yr5quzl.mongodb.net/")
db = client["smart_ambulance"]
patient_requests = db["patient_requests"]

print("\n" + "="*70)
print("HOSPITAL DASHBOARD - VISIBLE REQUESTS")
print("="*70)

# Query what hospital endpoint looks for
query = {
    "status": {"$in": ["accepted", "enroute", "picked_up", "assessed", "in_transit"]}
}

requests = list(patient_requests.find(query).sort("timestamp", -1))

if not requests:
    print("\n❌ NO REQUESTS FOUND matching hospital query!")
    print("\nQuery used:")
    print(query)
    
    # Show what statuses DO exist
    print("\n📊 All statuses in database:")
    all_requests = list(patient_requests.find({}, {"status": 1, "user_name": 1, "driver_name": 1}))
    for req in all_requests:
        print(f"  - Status: {req.get('status', 'NONE')}, Patient: {req.get('user_name', 'N/A')}, Driver: {req.get('driver_name', 'N/A')}")
else:
    print(f"\n✅ Found {len(requests)} request(s) that should be visible:\n")
    
    for i, req in enumerate(requests, 1):
        print(f"\n{'='*70}")
        print(f"REQUEST {i}:")
        print(f"{'='*70}")
        print(f"  ID: {req['_id']}")
        print(f"  Status: {req.get('status', 'NONE')}")
        print(f"  Patient Name: {req.get('user_name', 'MISSING')}")
        print(f"  Patient Contact: {req.get('user_contact', 'MISSING')}")
        print(f"  Driver Name: {req.get('driver_name', 'MISSING')}")
        print(f"  Driver Contact: {req.get('driver_contact', 'MISSING')}")
        print(f"  Vehicle: {req.get('vehicle', 'MISSING')}")
        print(f"  Injury Risk: {req.get('injury_risk', 'MISSING')}")
        print(f"  Injury Notes: {req.get('injury_notes', 'MISSING')}")
        print(f"  Timestamp: {req.get('timestamp', 'MISSING')}")
        print(f"  Accepted At: {req.get('accepted_at', 'MISSING')}")
        print(f"  Assessment Time: {req.get('assessment_time', 'MISSING')}")
        
        # Check if any required fields are null
        null_fields = []
        for field in ['user_name', 'driver_name', 'vehicle', 'status']:
            if not req.get(field):
                null_fields.append(field)
        
        if null_fields:
            print(f"\n  ⚠️ WARNING - NULL/MISSING FIELDS: {', '.join(null_fields)}")
        else:
            print(f"\n  ✅ All required fields have values")

print("\n" + "="*70 + "\n")
