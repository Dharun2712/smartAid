# app_extended.py - Complete Smart Ambulance Backend with End-to-End SOS Emergency Response Workflow
import os
import datetime
import time
import json
from functools import wraps
from flask import Flask, request, jsonify
from flask_socketio import SocketIO, emit, join_room, leave_room
from flask_cors import CORS
from pymongo import MongoClient, ASCENDING, DESCENDING
from bson import ObjectId
import bcrypt
import jwt
import threading

# Import models and database
from models import db, users, ambulance_drivers, hospitals, patient_requests

# New collection for admission offers
admission_offers = db["admission_offers"]

# ---------- CONFIG ----------
MONGO_URI = os.environ.get(
    "MONGO_URI",
    "mongodb+srv://Dharun:Dharun2712@cluster0.yr5quzl.mongodb.net/?retryWrites=true&w=majority&appName=Cluster0"
)
JWT_SECRET = os.environ.get("JWT_SECRET", "replace_this_with_env_secret")
JWT_ALGORITHM = "HS256"
JWT_EXP_DELTA_SECONDS = int(os.environ.get("JWT_EXP_SECONDS", 60 * 60 * 24))

# ---------- APP & SOCKETIO ----------
app = Flask(__name__)

# ---- Custom JSON Encoder for MongoDB ObjectId and datetime ----
class JSONEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, ObjectId):
            return str(obj)
        if isinstance(obj, datetime.datetime):
            return obj.isoformat()
        return super(JSONEncoder, self).default(obj)

app.json_encoder = JSONEncoder

CORS(app, resources={r"/api/*": {"origins": "*"}, r"/socket.io/*": {"origins": "*"}})
socketio = SocketIO(app, cors_allowed_origins="*", async_mode='threading', path='/socket.io')

# ---------- UTIL ----------
def create_jwt(user_id, role):
    payload = {
        "sub": str(user_id),
        "role": role,
        "iat": datetime.datetime.utcnow(),
        "exp": datetime.datetime.utcnow() + datetime.timedelta(seconds=JWT_EXP_DELTA_SECONDS)
    }
    token = jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)
    return token if isinstance(token, str) else token.decode("utf-8")

def verify_password(plain_password, hashed):
    return bcrypt.checkpw(plain_password.encode("utf-8"), hashed)

def json_error(msg, code=400):
    return jsonify({"success": False, "message": msg}), code

def token_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        token = None
        if 'Authorization' in request.headers:
            auth = request.headers.get('Authorization')
            if auth and auth.startswith('Bearer '):
                token = auth.split(' ')[1]
        if not token:
            return json_error("Token is missing", 401)
        try:
            data = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
            request.user_id = data["sub"]
            request.user_role = data["role"]
        except jwt.ExpiredSignatureError:
            return json_error("Token expired", 401)
        except Exception:
            return json_error("Invalid token", 401)
        return f(*args, **kwargs)
    return decorated

# ---------- AUTH ROUTES (Existing) ----------
@app.route("/api/login/client", methods=["POST"])
def login_client():
    data = request.get_json() or {}
    identifier = data.get("identifier", "").strip()
    password = data.get("password", "")
    if not identifier or not password:
        return json_error("Identifier and password are required", 400)
    
    query = {"email": identifier.lower()} if "@" in identifier else {"phone": identifier}
    query["role"] = "client"
    user = users.find_one(query)
    if not user:
        return json_error("User not found", 404)
    
    hashed = user.get("password")
    if not hashed or not verify_password(password, hashed):
        return json_error("Invalid credentials", 401)
    
    token = create_jwt(user_id=user["_id"], role="client")
    return jsonify({
        "success": True,
        "role": "client",
        "user_id": str(user["_id"]),
        "token": token
    }), 200

@app.route("/api/login/driver", methods=["POST"])
def login_driver():
    data = request.get_json() or {}
    driver_id = data.get("driver_id", "").strip()
    password = data.get("password", "")
    if not driver_id or not password:
        return json_error("driver_id and password are required", 400)
    
    # First find the driver in ambulance_drivers collection
    driver_record = ambulance_drivers.find_one({"driver_id": driver_id})
    if not driver_record:
        return json_error("Driver not found", 404)
    
    # Then get the user account using the user_id from driver record
    user = users.find_one({"_id": driver_record["user_id"], "role": "driver"})
    if not user:
        return json_error("Driver user account not found", 404)
    
    hashed = user.get("password")
    if not verify_password(password, hashed):
        return json_error("Invalid credentials", 401)
    
    token = create_jwt(user_id=user["_id"], role="driver")
    return jsonify({
        "success": True,
        "role": "driver",
        "user_id": str(user["_id"]),
        "driver_id": driver_id,
        "token": token
    }), 200

@app.route("/api/login/admin", methods=["POST"])
def login_admin():
    data = request.get_json() or {}
    hospital_code = data.get("hospital_code", "").strip()
    password = data.get("password", "")
    if not hospital_code or not password:
        return json_error("hospital_code and password are required", 400)
    
    user = users.find_one({"role": "admin", "hospital_code": hospital_code})
    if not user:
        return json_error("Admin not found", 404)
    
    hashed = user.get("password")
    if not verify_password(password, hashed):
        return json_error("Invalid credentials", 401)
    
    token = create_jwt(user_id=user["_id"], role="admin")
    return jsonify({
        "success": True,
        "role": "admin",
        "user_id": str(user["_id"]),
        "token": token
    }), 200

@app.route("/api/register/client", methods=["POST"])
def register_client():
    data = request.get_json() or {}
    identifier = data.get("identifier", "").strip()
    password = data.get("password", "")
    name = data.get("name", "").strip()
    blood_group = data.get("blood_group")
    has_medical_allergies = data.get("has_medical_allergies", False)
    
    if not identifier or not password or not name:
        return json_error("name, identifier (email/phone) and password are required", 400)
    
    # Check if user already exists with this email or phone
    is_email = "@" in identifier
    if is_email:
        # Check for existing email
        existing = users.find_one({"email": identifier.lower(), "role": "client"})
        if existing:
            return json_error("Email already registered", 409)
    else:
        # Check for existing phone
        existing = users.find_one({"phone": identifier, "role": "client"})
        if existing:
            return json_error("Phone number already registered", 409)
    
    hashed = bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt())
    document = {
        "role": "client",
        "name": name,
        "password": hashed,
        "verified": False,
        "google_auth": False,
        "created_at": datetime.datetime.utcnow()
    }
    
    # Add email or phone to document
    if is_email:
        document["email"] = identifier.lower()
    else:
        document["phone"] = identifier
    
    # Add medical information
    if blood_group:
        document["blood_group"] = blood_group
    if has_medical_allergies is not None:
        document["has_medical_allergies"] = bool(has_medical_allergies)
    
    res = users.insert_one(document)
    token = create_jwt(user_id=res.inserted_id, role="client")
    return jsonify({
        "success": True,
        "role": "client",
        "user_id": str(res.inserted_id),
        "token": token
    }), 201

@app.route("/api/register/driver", methods=["POST"])
def register_driver():
    """Register a new ambulance driver"""
    data = request.get_json() or {}
    
    # Required fields
    name = data.get("name", "").strip()
    email = data.get("email", "").strip()
    phone = data.get("phone", "").strip()
    password = data.get("password", "")
    driver_id = data.get("driver_id", "").strip()
    license_number = data.get("license_number", "").strip()
    
    # Vehicle details
    vehicle_type = data.get("vehicle_type", "ambulance").strip()
    vehicle_plate = data.get("vehicle_plate", "").strip()
    vehicle_model = data.get("vehicle_model", "").strip()
    
    # Validate required fields
    if not all([name, (email or phone), password, driver_id, license_number, vehicle_plate]):
        return json_error("All fields are required: name, email/phone, password, driver_id, license_number, vehicle_plate", 400)
    
    # Check if driver ID already exists
    existing = users.find_one({"role": "driver", "$or": [
        {"email": email.lower()} if email else {},
        {"phone": phone} if phone else {}
    ]})
    if existing:
        return json_error("Driver already registered with this email/phone", 409)
    
    # Check if driver_id already taken
    existing_driver = ambulance_drivers.find_one({"driver_id": driver_id})
    if existing_driver:
        return json_error("Driver ID already in use", 409)
    
    # Create user account
    hashed = bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt())
    user_doc = {
        "role": "driver",
        "name": name,
        "password": hashed,
        "phone": phone,
        "verified": True,  # Auto-verify drivers
        "created_at": datetime.datetime.utcnow()
    }
    if email:
        user_doc["email"] = email.lower()
    
    user_result = users.insert_one(user_doc)
    user_id = user_result.inserted_id
    
    # Create ambulance_drivers entry
    driver_doc = {
        "user_id": user_id,
        "driver_id": driver_id,
        "license_number": license_number,
        "vehicle": {
            "type": vehicle_type,
            "plate": vehicle_plate,
            "model": vehicle_model
        },
        "status": "offline",
        "verified": True,
        "rating": 5.0,
        "total_rides": 0,
        "created_at": datetime.datetime.utcnow()
    }
    
    ambulance_drivers.insert_one(driver_doc)
    
    token = create_jwt(user_id=user_id, role="driver")
    return jsonify({
        "success": True,
        "role": "driver",
        "user_id": str(user_id),
        "driver_id": driver_id,
        "token": token,
        "message": "Driver registration successful"
    }), 201

@app.route("/api/register/hospital", methods=["POST"])
def register_hospital():
    """Register a new hospital admin"""
    data = request.get_json() or {}
    
    # Required fields
    name = data.get("name", "").strip()
    email = data.get("email", "").strip()
    phone = data.get("phone", "").strip()
    password = data.get("password", "")
    hospital_code = data.get("hospital_code", "").strip()
    hospital_name = data.get("hospital_name", "").strip()
    address = data.get("address", "").strip()
    
    # Validate required fields
    if not all([name, (email or phone), password, hospital_code, hospital_name, address]):
        return json_error("All fields are required: name, email/phone, password, hospital_code, hospital_name, address", 400)
    
    # Check if hospital code already exists
    existing = hospitals.find_one({"hospital_code": hospital_code})
    if existing:
        return json_error("Hospital code already registered", 409)
    
    # Check if admin email/phone already exists
    existing_admin = users.find_one({"role": "admin", "$or": [
        {"email": email.lower()} if email else {},
        {"phone": phone} if phone else {}
    ]})
    if existing_admin:
        return json_error("Admin already registered with this email/phone", 409)
    
    # Create admin user account
    hashed = bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt())
    user_doc = {
        "role": "admin",
        "name": name,
        "password": hashed,
        "phone": phone,
        "hospital_code": hospital_code,
        "verified": True,  # Auto-verify hospital admins
        "created_at": datetime.datetime.utcnow()
    }
    if email:
        user_doc["email"] = email.lower()
    
    user_result = users.insert_one(user_doc)
    user_id = user_result.inserted_id
    
    # Create hospital entry
    hospital_doc = {
        "user_id": user_id,
        "hospital_code": hospital_code,
        "name": hospital_name,
        "address": address,
        "phone": phone,
        "verified": True,
        "capacity": {
            "icu": 10,
            "beds": 50,
            "doctors": 15
        },
        "created_at": datetime.datetime.utcnow()
    }
    
    hospitals.insert_one(hospital_doc)
    
    token = create_jwt(user_id=user_id, role="admin")
    return jsonify({
        "success": True,
        "role": "admin",
        "user_id": str(user_id),
        "hospital_code": hospital_code,
        "token": token,
        "message": "Hospital registration successful"
    }), 201

# ---------- CLIENT SOS ROUTES ----------
@app.route("/api/client/sos", methods=["POST"])
@token_required
def trigger_sos():
    """Trigger manual or auto SOS request - ENHANCED WORKFLOW"""
    if request.user_role != "client":
        return json_error("Only clients can trigger SOS", 403)
    
    data = request.get_json() or {}
    location = data.get("location")  # {"lat": float, "lng": float}
    condition = data.get("condition", "other")
    preliminary_severity = data.get("preliminary_severity", "unknown")
    sensor_data = data.get("sensor_data", {})
    auto_triggered = data.get("auto_triggered", False)
    contact = data.get("contact", "")
    
    if not location or "lat" not in location or "lng" not in location:
        return json_error("Location (lat, lng) is required", 400)
    
    # Get user info for driver notification
    user = users.find_one({"_id": ObjectId(request.user_id)})
    user_name = user.get("name", "Unknown") if user else "Unknown"
    user_contact = contact or user.get("phone", "") if user else ""
    blood_group = user.get("blood_group") if user else None
    has_medical_allergies = user.get("has_medical_allergies", False) if user else False
    
    # Create patient request
    sos_request = {
        "client_id": ObjectId(request.user_id),
        "user_name": user_name,
        "user_contact": user_contact,
        "blood_group": blood_group,
        "has_medical_allergies": has_medical_allergies,
        "driver_id": None,
        "hospital_id": None,
        "location": {
            "type": "Point",
            "coordinates": [location["lng"], location["lat"]]
        },
        "condition": condition,
        "preliminary_severity": preliminary_severity,
        "injury_level": None,  # Set after pickup
        "status": "pending",
        "auto_triggered": auto_triggered,
        "sensor_data": sensor_data,
        "vitals": {},
        "picked_up_at": None,
        "accepted_at": None,
        "assigned_at": None,
        "timestamp": datetime.datetime.utcnow()
    }
    
    result = patient_requests.insert_one(sos_request)
    request_id = str(result.inserted_id)
    
    # Find nearest 3 available drivers (within 20km)
    nearby_drivers = list(ambulance_drivers.find({
        "status": "available",
        "active": True,
        "location": {
            "$near": {
                "$geometry": {
                    "type": "Point",
                    "coordinates": [location["lng"], location["lat"]]
                },
                "$maxDistance": 20000  # 20km
            }
        }
    }).limit(3))
    
    if not nearby_drivers:
        # No drivers available - escalate
        return jsonify({
            "success": True,
            "request_id": request_id,
            "status": "pending",
            "nearby_drivers_count": 0,
            "message": "No drivers available nearby. Escalating to broader search..."
        }), 201
    
    # Emit SOS alert to top 3 nearest drivers with 30s TTL
    sos_alert_payload = {
        "request_id": request_id,
        "user_id": request.user_id,
        "user_name": user_name,
        "blood_group": blood_group,
        "has_medical_allergies": has_medical_allergies,
        "lat": location["lat"],
        "lng": location["lng"],
        "timestamp": datetime.datetime.utcnow().isoformat(),
        "sensor_data": sensor_data,
        "preliminary_severity": preliminary_severity,
        "contact": user_contact,
        "ttl_seconds": 30
    }
    
    for driver in nearby_drivers:
        driver_user_id = str(driver["user_id"])
        # Send to specific driver room
        socketio.emit('sos_alert', sos_alert_payload, room=f'driver_{driver_user_id}')
    
    # Also emit to general drivers room for backward compatibility
    socketio.emit('sos_alert', sos_alert_payload, room='drivers')
    
    # Set timeout for auto-escalation if no acceptance
    threading.Timer(30.0, escalate_sos_if_pending, args=[request_id]).start()
    
    return jsonify({
        "success": True,
        "request_id": request_id,
        "nearby_drivers_count": len(nearby_drivers),
        "status": "pending",
        "ttl_seconds": 30
    }), 201

def escalate_sos_if_pending(request_id):
    """Auto-escalate SOS if no driver accepts within TTL"""
    req = patient_requests.find_one({"_id": ObjectId(request_id)})
    if req and req.get("status") == "pending":
        # Escalate to broader radius (50km) and more drivers
        location = req["location"]["coordinates"]
        broader_drivers = list(ambulance_drivers.find({
            "status": "available",
            "active": True,
            "location": {
                "$near": {
                    "$geometry": {
                        "type": "Point",
                        "coordinates": location
                    },
                    "$maxDistance": 50000  # 50km
                }
            }
        }).limit(10))
        
        # Notify escalated drivers
        sos_alert_payload = {
            "request_id": request_id,
            "user_id": str(req["client_id"]),
            "user_name": req.get("user_name", "Unknown"),
            "lat": location[1],
            "lng": location[0],
            "timestamp": datetime.datetime.utcnow().isoformat(),
            "preliminary_severity": req.get("preliminary_severity", "unknown"),
            "contact": req.get("user_contact", ""),
            "escalated": True,
            "ttl_seconds": 60
        }
        
        for driver in broader_drivers:
            socketio.emit('sos_alert', sos_alert_payload, room=f'driver_{str(driver["user_id"])}')

@app.route("/api/client/my_requests", methods=["GET"])
@token_required
def get_client_requests():
    """Get all SOS requests for logged-in client"""
    if request.user_role != "client":
        return json_error("Access denied", 403)
    
    requests = list(patient_requests.find({"client_id": ObjectId(request.user_id)}).sort("timestamp", DESCENDING))
    for req in requests:
        req["_id"] = str(req["_id"])
        req["client_id"] = str(req["client_id"])
        if req.get("driver_id"):
            req["driver_id"] = str(req["driver_id"])
        if req.get("hospital_id"):
            req["hospital_id"] = str(req["hospital_id"])
    
    return jsonify({"success": True, "requests": requests}), 200

@app.route("/api/requests/<request_id>/status", methods=["GET"])
@token_required
def get_request_status(request_id):
    """Query status of a specific SOS request"""
    req = patient_requests.find_one({"_id": ObjectId(request_id)})
    
    if not req:
        return json_error("Request not found", 404)
    
    # Verify access
    if request.user_role == "client" and str(req["client_id"]) != request.user_id:
        return json_error("Access denied", 403)
    elif request.user_role == "driver" and str(req.get("driver_id")) != request.user_id:
        return json_error("Access denied", 403)
    elif request.user_role == "admin" and str(req.get("hospital_id")) != request.user_id:
        return json_error("Access denied", 403)
    
    # Sanitize and return
    req["_id"] = str(req["_id"])
    req["client_id"] = str(req["client_id"])
    if req.get("driver_id"):
        req["driver_id"] = str(req["driver_id"])
    if req.get("hospital_id"):
        req["hospital_id"] = str(req["hospital_id"])
    
    return jsonify({"success": True, "request": req}), 200

# ---------- DRIVER ROUTES ----------
@app.route("/api/driver/nearby_patients", methods=["GET"])
@token_required
def get_nearby_patients():
    """Get nearby SOS requests for driver"""
    if request.user_role != "driver":
        return json_error("Only drivers can access this", 403)
    
    # Get driver's current location from ambulance_drivers collection
    driver_info = ambulance_drivers.find_one({"user_id": ObjectId(request.user_id)})
    if not driver_info or not driver_info.get("location"):
        return json_error("Driver location not set", 400)
    
    # Find pending requests within 20km
    nearby_requests = list(patient_requests.find({
        "status": "pending",
        "location": {
            "$near": {
                "$geometry": driver_info["location"],
                "$maxDistance": 20000  # 20km
            }
        }
    }).limit(10))
    
    for req in nearby_requests:
        req["_id"] = str(req["_id"])
        req["client_id"] = str(req["client_id"])
    
    return jsonify({"success": True, "requests": nearby_requests}), 200

@app.route("/api/driver/accept_request", methods=["POST"])
@token_required
def accept_sos_request():
    """Driver accepts an SOS request - ATOMIC with ACK"""
    if request.user_role != "driver":
        return json_error("Only drivers can accept requests", 403)
    
    data = request.get_json() or {}
    request_id = data.get("request_id")
    
    if not request_id:
        return json_error("request_id is required", 400)
    
    # Get driver info for confirmation
    driver = users.find_one({"_id": ObjectId(request.user_id)})
    driver_name = driver.get("name", "Unknown Driver") if driver else "Unknown Driver"
    driver_contact = driver.get("phone", "") if driver else ""
    
    driver_info = ambulance_drivers.find_one({"user_id": ObjectId(request.user_id)})
    vehicle = driver_info.get("vehicle", "Ambulance") if driver_info else "Ambulance"
    
    # Atomic update - only first driver wins
    result = patient_requests.update_one(
        {"_id": ObjectId(request_id), "status": "pending"},
        {
            "$set": {
                "status": "accepted",
                "driver_id": ObjectId(request.user_id),
                "driver_name": driver_name,
                "driver_contact": driver_contact,
                "vehicle": vehicle,
                "accepted_at": datetime.datetime.utcnow(),
                "assigned_at": datetime.datetime.utcnow()
            }
        }
    )
    
    if result.matched_count == 0:
        return jsonify({
            "success": False,
            "accepted": False,
            "reason": "Request already accepted by another driver"
        }), 409
    
    # Update driver status to assigned
    ambulance_drivers.update_one(
        {"user_id": ObjectId(request.user_id)},
        {"$set": {"status": "assigned"}}
    )
    
    # Calculate ETA (simplified - 3 min + 1 min per km)
    sos_req = patient_requests.find_one({"_id": ObjectId(request_id)})
    eta_minutes = 7  # Default
    
    if driver_info and driver_info.get("location") and sos_req:
        # Simple distance calculation
        driver_coords = driver_info["location"]["coordinates"]
        client_coords = sos_req["location"]["coordinates"]
        # Rough distance in km (not accurate but good enough)
        distance_km = abs(driver_coords[0] - client_coords[0]) + abs(driver_coords[1] - client_coords[1])
        distance_km *= 111  # Convert to rough km
        eta_minutes = int(3 + distance_km * 1.5)
    
    # Emit request_assigned to user (client) with clear acceptance message
    request_assigned_payload = {
        "request_id": request_id,
        "driver_id": request.user_id,
        "driver_name": driver_name,
        "vehicle": vehicle if isinstance(vehicle, str) else f"{vehicle.get('type', 'Ambulance')} ({vehicle.get('plate', '')})",
        "eta_minutes": eta_minutes,
        "contact": driver_contact,
        "status": "accepted",
        "message": f"Ambulance driver {driver_name} has accepted your request and is on the way. ETA: {eta_minutes} minutes."
    }
    
    socketio.emit('request_assigned', request_assigned_payload, room=str(sos_req["client_id"]))
    socketio.emit('driver_accepted', request_assigned_payload, room=str(sos_req["client_id"]))
    
    # Notify driver with mission details
    socketio.emit('request_assigned', {
        "request_id": request_id,
        "user_name": sos_req.get("user_name", "Unknown"),
        "user_contact": sos_req.get("user_contact", ""),
        "lat": sos_req["location"]["coordinates"][1],
        "lng": sos_req["location"]["coordinates"][0],
        "status": "accepted"
    }, room=f'driver_{request.user_id}')
    
    # Update status to enroute once driver starts moving
    patient_requests.update_one(
        {"_id": ObjectId(request_id)},
        {"$set": {"status": "enroute"}}
    )
    
    # NOTIFY HOSPITALS IMMEDIATELY when driver accepts (not just after assessment)
    # This makes the request visible in hospital dashboard right away
    hospital_notification_payload = {
        "request_id": request_id,
        "driver_name": driver_name,
        "driver_contact": driver_contact,
        "vehicle": vehicle,
        "patient_name": sos_req.get("user_name", "Patient"),
        "patient_contact": sos_req.get("user_contact", ""),
        "status": "enroute",
        "eta_minutes": eta_minutes,
        "location": {
            "lat": sos_req["location"]["coordinates"][1],
            "lng": sos_req["location"]["coordinates"][0]
        },
        "message": f"Driver {driver_name} is en route to patient"
    }
    
    # Broadcast to all hospitals and admin room
    socketio.emit('incoming_patient', hospital_notification_payload, room='admin')
    
    return jsonify({
        "success": True,
        "accepted": True,
        "assigned": True,
        "request_id": request_id,
        "eta_minutes": eta_minutes,
        "message": f"Request accepted! En route to patient. Hospitals have been notified."
    }), 200

@app.route("/api/driver/submit_assessment", methods=["POST"])
@token_required
def submit_injury_assessment():
    """Driver submits injury assessment after examining patient and notifies hospitals"""
    if request.user_role != "driver":
        return json_error("Only drivers can submit assessments", 403)
    
    data = request.get_json() or {}
    request_id = data.get("request_id")
    injury_risk = data.get("injury_risk")  # low, medium, high
    injury_notes = data.get("injury_notes", "")
    
    if not request_id or not injury_risk:
        return json_error("request_id and injury_risk are required", 400)
    
    # Get driver and user info FIRST to ensure we have all data
    driver = users.find_one({"_id": ObjectId(request.user_id)})
    driver_info = ambulance_drivers.find_one({"user_id": ObjectId(request.user_id)})
    
    # Prepare complete driver data with defaults
    driver_name = driver.get("name", "Unknown Driver") if driver else "Unknown Driver"
    driver_contact = driver.get("phone", "") if driver else ""
    vehicle = driver_info.get("vehicle", "Ambulance") if driver_info else "Ambulance"
    
    # Update the request with injury assessment AND ensure driver info is complete
    result = patient_requests.update_one(
        {"_id": ObjectId(request_id), "driver_id": ObjectId(request.user_id)},
        {
            "$set": {
                "injury_risk": injury_risk or "medium",  # Default to medium if not provided
                "injury_notes": injury_notes or "Assessment completed by driver",
                "injury_level": injury_risk or "medium",
                "assessment_time": datetime.datetime.utcnow(),
                "status": "assessed",
                # Ensure driver info is always present
                "driver_name": driver_name,
                "driver_contact": driver_contact,
                "vehicle": vehicle,
                # Add vitals if provided
                "vitals": data.get("vitals", {}),
                "driver_notes": injury_notes or "Assessment completed"
            }
        }
    )
    
    if result.matched_count == 0:
        return json_error("Request not found or not assigned to you", 404)
    
    # Get the updated request details
    sos_req = patient_requests.find_one({"_id": ObjectId(request_id)})
    user = users.find_one({"_id": sos_req["client_id"]})
    
    # Notify admin/hospital about the assessment
    assessment_data = {
        "request_id": request_id,
        "injury_risk": injury_risk,
        "injury_notes": injury_notes,
        "patient_name": sos_req.get("user_name", "Unknown"),
        "location": sos_req.get("location"),
        "driver_id": request.user_id,
        "driver_name": driver.get("name", "Unknown Driver") if driver else "Unknown Driver",
        "timestamp": datetime.datetime.utcnow().isoformat()
    }
    
    # Emit to admin room
    socketio.emit('injury_assessment_submitted', assessment_data, room='admin')
    
    # Emit to client
    socketio.emit('assessment_received', {
        "injury_risk": injury_risk,
        "status": "Driver has assessed your condition",
        "message": f"Injury Risk Level: {injury_risk.upper()}. Finding nearest hospital..."
    }, room=str(sos_req["client_id"]))
    
    # TRIGGER HOSPITAL NOTIFICATIONS - Find and notify nearby hospitals
    find_and_notify_hospitals(request_id, injury_risk, sos_req, driver_info, driver, user)
    
    return jsonify({
        "success": True,
        "message": f"Assessment submitted successfully! Injury risk: {injury_risk.upper()}. Nearby hospitals have been notified and will respond with admission availability.",
        "injury_risk": injury_risk,
        "status": "assessed",
        "hospitals_notified": True
    }), 200

@app.route("/api/driver/decline_request", methods=["POST"])
@token_required
def decline_sos_request():
    """Driver declines an SOS request"""
    if request.user_role != "driver":
        return json_error("Only drivers can decline requests", 403)
    
    data = request.get_json() or {}
    request_id = data.get("request_id")
    
    if not request_id:
        return json_error("request_id is required", 400)
    
    # Just log the decline, don't update anything
    return jsonify({"success": True, "message": "Request declined"}), 200

@app.route("/api/driver/update_location", methods=["POST"])
@token_required
def update_driver_location():
    """Update driver's live location and broadcast to client & hospital"""
    if request.user_role != "driver":
        return json_error("Only drivers can update location", 403)
    
    data = request.get_json() or {}
    location = data.get("location")
    
    if not location or "lat" not in location or "lng" not in location:
        return json_error("Location (lat, lng) is required", 400)
    
    # Update driver location
    result = ambulance_drivers.update_one(
        {"user_id": ObjectId(request.user_id)},
        {
            "$set": {
                "location": {
                    "type": "Point",
                    "coordinates": [location["lng"], location["lat"]]
                },
                "last_updated": datetime.datetime.utcnow()
            }
        },
        upsert=True
    )
    
    # Find active request assigned to this driver
    active_request = patient_requests.find_one({
        "driver_id": ObjectId(request.user_id),
        "status": {"$in": ["accepted", "enroute", "picked_up", "assessed"]}
    })
    
    location_payload = {
        "driver_id": request.user_id,
        "location": location,
        "timestamp": datetime.datetime.utcnow().isoformat()
    }
    
    # Broadcast to driver's own room
    socketio.emit('driver_location_update', location_payload, room=f'driver_{request.user_id}')
    
    # If driver has active request, broadcast to client and hospital
    if active_request:
        client_id = str(active_request["client_id"])
        
        # Broadcast to client (patient) for live tracking
        socketio.emit('driver_location_update', {
            **location_payload,
            "request_id": str(active_request["_id"]),
            "driver_name": active_request.get("driver_name", "Driver"),
            "vehicle": active_request.get("vehicle", "Ambulance"),
            "status": active_request.get("status")
        }, room=client_id)
        
        # If hospital is assigned, broadcast to hospital
        if active_request.get("hospital_id"):
            hospital_id = str(active_request["hospital_id"])
            socketio.emit('driver_location_update', {
                **location_payload,
                "request_id": str(active_request["_id"]),
                "driver_name": active_request.get("driver_name", "Driver"),
                "patient_name": active_request.get("user_name", "Patient"),
                "injury_risk": active_request.get("injury_risk", "unknown"),
                "status": active_request.get("status")
            }, room=f'hospital_{hospital_id}')
    
    return jsonify({"success": True}), 200

@app.route("/api/driver/toggle_status", methods=["POST"])
@token_required
def toggle_driver_status():
    """Toggle driver active/inactive"""
    if request.user_role != "driver":
        return json_error("Only drivers can toggle status", 403)
    
    data = request.get_json() or {}
    active = data.get("active", True)
    
    result = ambulance_drivers.update_one(
        {"user_id": ObjectId(request.user_id)},
        {
            "$set": {
                "active": active,
                "status": "available" if active else "offline"
            }
        },
        upsert=True
    )
    
    return jsonify({"success": True, "active": active}), 200

@app.route("/api/driver/arrived", methods=["POST"])
@token_required
def driver_arrived():
    """Driver marks as arrived at scene (optional step)"""
    if request.user_role != "driver":
        return json_error("Only drivers can mark arrival", 403)
    
    data = request.get_json() or {}
    request_id = data.get("request_id")
    
    if not request_id:
        return json_error("request_id is required", 400)
    
    result = patient_requests.update_one(
        {"_id": ObjectId(request_id), "driver_id": ObjectId(request.user_id)},
        {
            "$set": {
                "status": "arrived_at_scene",
                "arrived_at_scene_time": datetime.datetime.utcnow()
            }
        }
    )
    
    if result.matched_count == 0:
        return json_error("Request not found", 404)
    
    # Notify user
    sos_req = patient_requests.find_one({"_id": ObjectId(request_id)})
    socketio.emit('driver_arrived', {"request_id": request_id}, room=str(sos_req["client_id"]))
    
    return jsonify({"success": True, "status": "arrived_at_scene"}), 200

@app.route("/api/driver/picked_up", methods=["POST"])
@token_required
def patient_picked_up():
    """Driver submits Picked Up with injury assessment - CRITICAL WORKFLOW"""
    if request.user_role != "driver":
        return json_error("Only drivers can submit pickup", 403)
    
    data = request.get_json() or {}
    request_id = data.get("request_id")
    injury_level = data.get("injury_level")  # "high", "medium", "low"
    notes = data.get("notes", "")
    vitals = data.get("vitals", {})  # {"pulse": 110, "bp": "90/60"}
    
    if not request_id or not injury_level:
        return json_error("request_id and injury_level are required", 400)
    
    if injury_level not in ["high", "medium", "low"]:
        return json_error("injury_level must be 'high', 'medium', or 'low'", 400)
    
    # Update patient request with assessment
    picked_up_time = datetime.datetime.utcnow()
    result = patient_requests.update_one(
        {"_id": ObjectId(request_id), "driver_id": ObjectId(request.user_id)},
        {
            "$set": {
                "status": "in_transit",
                "picked_up_at": picked_up_time,
                "injury_level": injury_level,
                "driver_notes": notes,
                "vitals": vitals
            }
        }
    )
    
    if result.matched_count == 0:
        return json_error("Request not found or not assigned to you", 404)
    
    # Get full request details
    sos_req = patient_requests.find_one({"_id": ObjectId(request_id)})
    driver_info = ambulance_drivers.find_one({"user_id": ObjectId(request.user_id)})
    driver = users.find_one({"_id": ObjectId(request.user_id)})
    user = users.find_one({"_id": sos_req["client_id"]})
    
    # Notify user that they've been picked up
    socketio.emit('picked_up', {
        "request_id": request_id,
        "injury_level": injury_level,
        "status": "in_transit",
        "message": "You have been picked up. Finding nearest hospital..."
    }, room=str(sos_req["client_id"]))
    
    # TRIGGER HOSPITAL SELECTION LOGIC
    find_and_notify_hospitals(request_id, injury_level, sos_req, driver_info, driver, user)
    
    return jsonify({
        "success": True,
        "status": "in_transit",
        "injury_level": injury_level,
        "message": "Assessment submitted. Finding hospitals..."
    }), 200

def find_and_notify_hospitals(request_id, injury_level, sos_req, driver_info, driver, user):
    """Find suitable hospitals based on injury level and notify them"""
    if not driver_info or not driver_info.get("location"):
        return
    
    ambulance_location = driver_info["location"]["coordinates"]
    
    # Query hospitals based on injury level
    hospital_query = {
        "verified": True,
        "location": {
            "$near": {
                "$geometry": {
                    "type": "Point",
                    "coordinates": ambulance_location
                },
                "$maxDistance": 50000  # 50km max
            }
        }
    }
    
    # Add capacity requirements based on injury level
    if injury_level == "high":
        hospital_query["capacity.icu"] = {"$gt": 0}
    elif injury_level == "medium":
        hospital_query["capacity.beds"] = {"$gt": 0}
    
    # Get top 3 hospitals
    suitable_hospitals = list(hospitals.find(hospital_query).limit(3))
    
    if not suitable_hospitals:
        # Fallback - no specific capacity requirements
        suitable_hospitals = list(hospitals.find({
            "verified": True,
            "location": {
                "$near": {
                    "$geometry": {"type": "Point", "coordinates": ambulance_location},
                    "$maxDistance": 50000
                }
            }
        }).limit(3))
    
    # Calculate ETA for each hospital (simplified)
    for hospital in suitable_hospitals:
        hospital_coords = hospital["location"]["coordinates"]
        distance_km = abs(ambulance_location[0] - hospital_coords[0]) + abs(ambulance_location[1] - hospital_coords[1])
        distance_km *= 111  # Rough conversion
        eta_minutes = int(distance_km * 2)  # Rough ETA
        
        # Create admission offer
        offer = {
            "request_id": ObjectId(request_id),
            "hospital_id": hospital["_id"],
            "status": "pending",
            "created_at": datetime.datetime.utcnow(),
            "expires_at": datetime.datetime.utcnow() + datetime.timedelta(seconds=15),
            "eta_minutes": eta_minutes
        }
        admission_offers.insert_one(offer)
        
        # Prepare admission offer payload
        admission_payload = {
            "request_id": request_id,
            "offer_id": str(offer["_id"]),
            "user": {
                "id": str(sos_req["client_id"]),
                "name": user.get("name", "Unknown") if user else "Unknown",
                "age": user.get("age", "Unknown") if user else "Unknown",
                "contact": sos_req.get("user_contact", "")
            },
            "location": {
                "lat": sos_req["location"]["coordinates"][1],
                "lng": sos_req["location"]["coordinates"][0]
            },
            "injury_level": injury_level,
            "injury_risk": sos_req.get("injury_risk", injury_level),  # Use injury_risk from assessment
            "injury_notes": sos_req.get("injury_notes", ""),  # Include driver's assessment notes
            "driver": {
                "id": str(driver["_id"]) if driver else "",
                "name": driver.get("name", "Unknown") if driver else "Unknown",
                "vehicle": driver_info.get("vehicle", "Ambulance") if driver_info else "Ambulance",
                "contact": driver.get("phone", "") if driver else ""
            },
            "eta_minutes": eta_minutes,
            "vitals": sos_req.get("vitals", {}),
            "notes": sos_req.get("driver_notes", ""),
            "ttl_seconds": 15
        }
        
        # Emit to specific hospital
        socketio.emit('admission_offer', admission_payload, room=f'hospital_{str(hospital["user_id"])}')

# ---------- HOSPITAL ROUTES ----------
@app.route("/api/hospital/update_capacity", methods=["POST"])
@token_required
def update_hospital_capacity():
    """Update hospital capacity (ICU, beds, doctors)"""
    if request.user_role != "admin":
        return json_error("Only hospital admins can update capacity", 403)
    
    data = request.get_json() or {}
    capacity = data.get("capacity", {})
    
    if not capacity:
        return json_error("Capacity data is required", 400)
    
    result = hospitals.update_one(
        {"user_id": ObjectId(request.user_id)},
        {
            "$set": {
                "capacity": capacity,
                "last_updated": datetime.datetime.utcnow()
            }
        },
        upsert=True
    )
    
    return jsonify({"success": True, "capacity": capacity}), 200

@app.route("/api/hospital/patient_requests", methods=["GET"])
@token_required
def get_hospital_patient_requests():
    """Get incoming patient requests with live driver tracking for hospital dashboard"""
    if request.user_role != "admin":
        return json_error("Only hospital admins can access this", 403)
    
    # Get hospital location (optional for now)
    hospital_info = hospitals.find_one({"user_id": ObjectId(request.user_id)})
    
    # Build query - prioritize assessed and in-transit requests
    query = {
        "status": {"$in": ["accepted", "enroute", "picked_up", "assessed", "in_transit"]}
    }
    
    # If hospital has location, use proximity search but FALLBACK to global list if none found
    requests = []
    if hospital_info and hospital_info.get("location"):
        proximity_query = dict(query)
        proximity_query["location"] = {
            "$near": {
                "$geometry": hospital_info.get("location"),
                "$maxDistance": 50000  # 50km
            }
        }
        try:
            requests = list(patient_requests.find(proximity_query).limit(20))
        except Exception as e:
            # If $near fails (missing index or bad geometry), fallback to global
            print("Proximity query failed, falling back to global list:", e)
            requests = []

        # If proximity returned fewer than the limit, supplement with recent global assessed requests
        if requests and len(requests) < 20:
            prox_ids = [r['_id'] for r in requests if r.get('_id')]
            extra_needed = 20 - len(requests)
            extra_query = dict(query)
            extra_query["_id"] = {"$nin": prox_ids}
            extras = list(patient_requests.find(extra_query).sort("timestamp", -1).limit(extra_needed))
            # Append extras while avoiding duplicates
            requests.extend(extras)

        # If proximity returned nothing, fallback to the global recent assessed list
        if not requests:
            requests = list(patient_requests.find(query).sort("timestamp", -1).limit(20))
    else:
        # No location set - show all assessed requests sorted by time
        requests = list(patient_requests.find(query).sort("timestamp", -1).limit(20))
    
    

    # Enrich with driver live location
    for req in requests:
        # Convert ALL ObjectIds to strings first
        req["_id"] = str(req["_id"])
        req["client_id"] = str(req.get("client_id", ""))
        
        # Safe defaults for all fields to prevent null errors
        req["driver_name"] = req.get("driver_name", "") or "Unknown Driver"
        req["user_name"] = req.get("user_name", "") or "Patient"
        req["user_contact"] = req.get("user_contact", "") or ""
        req["driver_contact"] = req.get("driver_contact", "") or ""
        req["status"] = req.get("status", "") or "pending"
        req["injury_risk"] = req.get("injury_risk", "") or ""
        req["injury_notes"] = req.get("injury_notes", "") or ""
        req["injury_level"] = req.get("injury_level") or req.get("injury_risk", "") or ""
        req["condition"] = req.get("condition", "") or ""
        req["preliminary_severity"] = req.get("preliminary_severity", "") or ""
        
        # Handle driver info
        if req.get("driver_id"):
            driver_id_obj = req["driver_id"]
            req["driver_id"] = str(driver_id_obj)
            
            # Get driver's current location
            driver_info = ambulance_drivers.find_one({"user_id": driver_id_obj})
            if driver_info and driver_info.get("location"):
                last_updated = driver_info.get("last_updated", datetime.datetime.utcnow())
                last_updated_str = last_updated.isoformat() if hasattr(last_updated, 'isoformat') else str(last_updated)
                
                req["driver_current_location"] = {
                    "lat": driver_info["location"]["coordinates"][1],
                    "lng": driver_info["location"]["coordinates"][0],
                    "last_updated": last_updated_str
                }
            else:
                req["driver_current_location"] = None
            
            # Handle vehicle - convert dict to string if needed
            vehicle = req.get("vehicle")
            if isinstance(vehicle, dict):
                # Vehicle is a dict like {"type": "ambulance", "plate": "AMB-001"}
                req["vehicle"] = f"{vehicle.get('type', 'Ambulance')} ({vehicle.get('plate', '')})"
            elif vehicle:
                req["vehicle"] = str(vehicle)
            else:
                req["vehicle"] = "Ambulance"
        else:
            req["driver_id"] = ""
            req["driver_name"] = "Unknown Driver"
            req["vehicle"] = "Ambulance"
            req["driver_contact"] = ""
            req["driver_current_location"] = None
        
        # Convert timestamps to ISO strings
        for timestamp_field in ["timestamp", "accepted_at", "assessment_time", "created_at", "updated_at"]:
            if req.get(timestamp_field):
                ts = req[timestamp_field]
                req[timestamp_field] = ts.isoformat() if hasattr(ts, 'isoformat') else str(ts)
            elif timestamp_field == "timestamp":
                req[timestamp_field] = datetime.datetime.utcnow().isoformat()
            else:
                req[timestamp_field] = ""
        
        # Handle location coordinates
        if req.get("location") and req["location"].get("coordinates"):
            req["location"] = {
                "lat": req["location"]["coordinates"][1],
                "lng": req["location"]["coordinates"][0]
            }
        else:
            req["location"] = {"lat": 0.0, "lng": 0.0}
        
        # Final cleanup: Convert any remaining ObjectIds or datetime objects
        for key, value in list(req.items()):
            if isinstance(value, ObjectId):
                req[key] = str(value)
            elif isinstance(value, datetime.datetime):
                req[key] = value.isoformat()
            elif isinstance(value, dict):
                # Recursively clean nested dicts
                for nested_key, nested_value in list(value.items()):
                    if isinstance(nested_value, ObjectId):
                        value[nested_key] = str(nested_value)
                    elif isinstance(nested_value, datetime.datetime):
                        value[nested_key] = nested_value.isoformat()
    
    return jsonify({"success": True, "count": len(requests), "requests": requests}), 200

@app.route("/api/hospital/confirm_admission", methods=["POST"])
@token_required
def confirm_patient_admission():
    """Hospital confirms or rejects patient admission - ENHANCED"""
    if request.user_role != "admin":
        return json_error("Only hospital admins can confirm admission", 403)
    
    data = request.get_json() or {}
    request_id = data.get("request_id")
    offer_id = data.get("offer_id")
    action = data.get("action")  # "accept" or "reject"
    bed_number = data.get("bed_number", "")
    dock = data.get("dock", "")
    
    if not request_id or action not in ["accept", "reject"]:
        return json_error("request_id and action (accept/reject) are required", 400)
    
    sos_req = patient_requests.find_one({"_id": ObjectId(request_id)})
    if not sos_req:
        return json_error("Request not found", 404)
    
    if action == "accept":
        # Atomic update - first hospital to accept wins
        result = patient_requests.update_one(
            {"_id": ObjectId(request_id), "hospital_id": None},
            {
                "$set": {
                    "hospital_id": ObjectId(request.user_id),
                    "status": "accepted_by_hospital",
                    "admission_decision_at": datetime.datetime.utcnow(),
                    "bed_number": bed_number,
                    "arrival_dock": dock
                }
            }
        )
        
        if result.matched_count == 0:
            return jsonify({
                "success": False,
                "message": "Already accepted by another hospital"
            }), 409
        
        # Update hospital capacity (atomic decrement)
        hospital_doc = hospitals.find_one({"user_id": ObjectId(request.user_id)})
        injury_level = sos_req.get("injury_level", "low")
        
        if injury_level == "high" and hospital_doc:
            hospitals.update_one(
                {"user_id": ObjectId(request.user_id)},
                {"$inc": {"capacity.icu": -1}}
            )
        elif injury_level == "medium" and hospital_doc:
            hospitals.update_one(
                {"user_id": ObjectId(request.user_id)},
                {"$inc": {"capacity.beds": -1}}
            )
        
        # Update offer status
        if offer_id:
            admission_offers.update_one(
                {"_id": ObjectId(offer_id)},
                {"$set": {"status": "accepted"}}
            )
        
        # Get hospital info
        hospital_info = hospitals.find_one({"user_id": ObjectId(request.user_id)})
        hospital_name = hospital_info.get("name", "Hospital") if hospital_info else "Hospital"
        hospital_address = hospital_info.get("address", "") if hospital_info else ""
        
        # Notify driver with detailed hospital information
        hospital_confirm_payload = {
            "request_id": request_id,
            "hospital_id": str(request.user_id),
            "hospital_name": hospital_name,
            "hospital_address": hospital_address,
            "bed_number": bed_number,
            "dock": dock,
            "status": "accepted_by_hospital",
            "message": f"{hospital_name} has confirmed admission. Proceed to {dock or 'Emergency Entrance'}"
        }
        
        socketio.emit('hospital_confirmed', hospital_confirm_payload, room=f'driver_{str(sos_req["driver_id"])}')
        
        # Notify patient/client with reassuring message
        client_confirm_payload = {
            "request_id": request_id,
            "hospital_id": str(request.user_id),
            "hospital_name": hospital_name,
            "hospital_address": hospital_address,
            "bed_number": bed_number,
            "status": "accepted_by_hospital",
            "message": f"{hospital_name} has accepted your admission. Your ambulance is heading there now."
        }
        
        socketio.emit('hospital_confirmed', client_confirm_payload, room=str(sos_req["client_id"]))
        socketio.emit('hospital_accepted', client_confirm_payload, room=str(sos_req["client_id"]))
        
        return jsonify({
            "success": True,
            "status": "accepted_by_hospital",
            "hospital_name": hospital_name,
            "bed_number": bed_number
        }), 200
    
    else:  # reject
        # Mark offer as rejected
        if offer_id:
            admission_offers.update_one(
                {"_id": ObjectId(offer_id)},
                {"$set": {"status": "rejected"}}
            )
        
        # Notify driver to try next hospital
        socketio.emit('hospital_rejected', {
            "request_id": request_id,
            "hospital_id": str(request.user_id),
            "message": "Hospital rejected. Finding alternative..."
        }, room=f'driver_{str(sos_req["driver_id"])}')
        
        return jsonify({"success": True, "status": "rejected"}), 200

@app.route("/api/driver/reached_hospital", methods=["POST"])
@token_required
def driver_reached_hospital():
    """Driver marks as reached hospital - FINAL HANDOFF"""
    if request.user_role != "driver":
        return json_error("Only drivers can mark hospital arrival", 403)
    
    data = request.get_json() or {}
    request_id = data.get("request_id")
    
    if not request_id:
        return json_error("request_id is required", 400)
    
    result = patient_requests.update_one(
        {"_id": ObjectId(request_id), "driver_id": ObjectId(request.user_id)},
        {
            "$set": {
                "status": "arrived",
                "arrived_at_hospital_time": datetime.datetime.utcnow()
            }
        }
    )
    
    if result.matched_count == 0:
        return json_error("Request not found", 404)
    
    # Update driver status back to available
    ambulance_drivers.update_one(
        {"user_id": ObjectId(request.user_id)},
        {"$set": {"status": "available"}}
    )
    
    sos_req = patient_requests.find_one({"_id": ObjectId(request_id)})
    
    # Notify hospital
    socketio.emit('reached_hospital', {
        "request_id": request_id,
        "status": "arrived",
        "message": "Ambulance has arrived"
    }, room=f'hospital_{str(sos_req["hospital_id"])}')
    
    # Notify user
    socketio.emit('reached_hospital', {
        "request_id": request_id,
        "status": "arrived",
        "message": "Arrived at hospital"
    }, room=str(sos_req["client_id"]))
    
    return jsonify({
        "success": True,
        "status": "arrived",
        "message": "Mission completed"
    }), 200

@app.route("/api/hospital/nearby_hospitals", methods=["GET"])
def get_nearby_hospitals():
    """Get nearby hospitals with available capacity (for driver)"""
    lat = request.args.get("lat", type=float)
    lng = request.args.get("lng", type=float)
    
    if not lat or not lng:
        return json_error("lat and lng query params are required", 400)
    
    # Find hospitals within 30km with available capacity
    nearby = list(hospitals.find({
        "verified": True,
        "location": {
            "$near": {
                "$geometry": {
                    "type": "Point",
                    "coordinates": [lng, lat]
                },
                "$maxDistance": 30000  # 30km
            }
        }
    }).limit(10))
    
    for h in nearby:
        h["_id"] = str(h["_id"])
        h["user_id"] = str(h["user_id"])
    
    return jsonify({"success": True, "hospitals": nearby}), 200

# ---------- SOCKETIO EVENTS ----------
@socketio.on('connect')
def handle_connect():
    print(f"Client connected: {request.sid}")

@socketio.on('disconnect')
def handle_disconnect():
    print(f"Client disconnected: {request.sid}")

@socketio.on('join')
def handle_join(data):
    """Join a room for targeted updates (driver_{id}, hospital_{id}, user_id, etc.)"""
    room = data.get('room')
    user_id = data.get('user_id')
    role = data.get('role')
    
    if room:
        join_room(room)
        emit('joined', {'room': room}, room=request.sid)
    
    # Auto-join role-specific rooms
    if role == "driver" and user_id:
        join_room(f'driver_{user_id}')
        join_room('drivers')  # General drivers room
        emit('joined', {'room': f'driver_{user_id}'}, room=request.sid)
    elif role == "admin" and user_id:
        join_room(f'hospital_{user_id}')
        join_room('hospitals')  # General hospitals room
        emit('joined', {'room': f'hospital_{user_id}'}, room=request.sid)
    elif role == "client" and user_id:
        join_room(str(user_id))
        emit('joined', {'room': str(user_id)}, room=request.sid)

@socketio.on('leave')
def handle_leave(data):
    """Leave a room"""
    room = data.get('room')
    if room:
        leave_room(room)
        emit('left', {'room': room})

@socketio.on('sos_response')
def handle_sos_response(data):
    """Handle driver's accept/decline response"""
    request_id = data.get('request_id')
    driver_id = data.get('driver_id')
    action = data.get('action')  # "accept" or "decline"
    
    if action == "accept":
        # Use the REST API logic via internal call
        emit('sos_response_ack', {
            "request_id": request_id,
            "action": "accept",
            "message": "Processing acceptance..."
        })
    elif action == "decline":
        emit('sos_response_ack', {
            "request_id": request_id,
            "action": "decline",
            "message": "Declined"
        })

@socketio.on('driver_location_update')
def handle_driver_location_realtime(data):
    """Real-time driver location updates via Socket.IO"""
    driver_id = data.get('driver_id')
    location = data.get('location')
    request_id = data.get('request_id')
    
    if not location or not driver_id:
        return
    
    # Update driver location in database
    ambulance_drivers.update_one(
        {"user_id": ObjectId(driver_id)},
        {
            "$set": {
                "location": {
                    "type": "Point",
                    "coordinates": [location["lng"], location["lat"]]
                },
                "last_updated": datetime.datetime.utcnow()
            }
        }
    )
    
    # Broadcast to subscribed clients
    if request_id:
        # Find the client for this request
        req = patient_requests.find_one({"_id": ObjectId(request_id)})
        if req:
            emit('driver_location_update', {
                "driver_id": driver_id,
                "location": location,
                "request_id": request_id
            }, room=str(req["client_id"]))
            
            # Also send to hospital if assigned
            if req.get("hospital_id"):
                emit('driver_location_update', {
                    "driver_id": driver_id,
                    "location": location,
                    "request_id": request_id
                }, room=f'hospital_{str(req["hospital_id"])}')

# Health check
@app.route("/api/health", methods=["GET"])
def health():
    return jsonify({"success": True, "message": "OK"}), 200

# ---------- RUN ----------
if __name__ == "__main__":
    socketio.run(app, host="0.0.0.0", port=5000, debug=False, use_reloader=False)

