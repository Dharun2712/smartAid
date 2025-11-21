"""
FastAPI Backend for Smart-Aid
Converted from Flask for better performance
MongoDB Atlas connection
"""

import os
import datetime
import bcrypt
import jwt
import time
from typing import Optional, List, Dict, Any
from fastapi import FastAPI, HTTPException, Depends, Header, WebSocket, WebSocketDisconnect, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel, EmailStr, Field
from pymongo import MongoClient, GEOSPHERE
from bson import ObjectId
import socketio
from contextlib import asynccontextmanager
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    datefmt='%H:%M:%S'
)
logger = logging.getLogger(__name__)

# ---------- Configuration ----------
MONGODB_URI = "mongodb+srv://Dharun:Dharun2712@cluster0.yr5quzl.mongodb.net/?retryWrites=true&w=majority&appName=Cluster0"
# The production/testing DB in your cluster is named "smart_ambulance".
# Use that DB so existing driver and user documents are found.
DB_NAME = "smart_ambulance"
JWT_SECRET = "your_secret_key_here_change_in_production"
JWT_ALGORITHM = "HS256"

# ---------- MongoDB Setup ----------
mongo_client = MongoClient(
    MONGODB_URI,
    serverSelectionTimeoutMS=5000,
    connectTimeoutMS=10000,
    socketTimeoutMS=10000,
    retryWrites=True,
    w='majority',
    maxPoolSize=50,  # Increased connection pool for better performance
    minPoolSize=10,
    maxIdleTimeMS=45000
)
db = mongo_client[DB_NAME]

# Collections
users = db.users
patient_requests = db.patient_requests
ambulance_drivers = db.ambulance_drivers
hospitals = db.hospitals

# Create indexes
@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: Create indexes
    try:
        # Test connection first
        mongo_client.admin.command('ping')
        logger.info("MongoDB connection successful")

        # Create indexes
        patient_requests.create_index([("location", GEOSPHERE)])
        ambulance_drivers.create_index([("location", GEOSPHERE)])
        hospitals.create_index([("location", GEOSPHERE)])

        # Performance indexes for faster queries
        users.create_index([("email", 1), ("role", 1)])  # Fast email+role lookup
        users.create_index([("phone", 1), ("role", 1)])  # Fast phone+role lookup
        users.create_index([("hospital_code", 1), ("role", 1)])  # Fast hospital admin lookup
        ambulance_drivers.create_index([("driver_id", 1)])  # Fast driver_id lookup
        ambulance_drivers.create_index([("status", 1)])  # Fast driver status filtering
        patient_requests.create_index([("status", 1)])  # Fast request status filtering
        patient_requests.create_index([("user_id", 1)])  # Fast user request history

        logger.info("MongoDB indexes created successfully")
    except Exception as e:
        logger.warning(f"MongoDB connection/index error: {e}")
        logger.warning("Backend will start but database operations may fail")
    
    yield
    
    # Shutdown
    try:
        mongo_client.close()
        logger.info("MongoDB connection closed")
    except Exception as e:
        logger.warning(f"Error closing MongoDB connection: {e}")

# ---------- FastAPI App ----------
app = FastAPI(
    title="Smart-Aid API",
    description="Emergency ambulance service API",
    version="2.0.0",
    lifespan=lifespan
)

# CORS Configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Request Logging Middleware
@app.middleware("http")
async def log_requests(request: Request, call_next):
    start_time = time.time()
    
    # Get client IP
    client_ip = request.client.host if request.client else "unknown"
    
    # Process request
    response = await call_next(request)
    
    # Calculate duration
    duration = (time.time() - start_time) * 1000  # Convert to milliseconds
    
    # Log with status code flag
    status_flag = "OK" if response.status_code < 400 else "ERR"
    logger.info(
        f"{status_flag} {request.method:6} {request.url.path:40} | "
        f"Status: {response.status_code} | "
        f"Duration: {duration:.2f}ms | "
        f"Client: {client_ip}"
    )
    
    return response

# ---------- Socket.IO Setup ----------
sio = socketio.AsyncServer(
    async_mode="asgi",
    cors_allowed_origins="*",
    logger=True,
    engineio_logger=False
)

# Mount Socket.IO
socket_app = socketio.ASGIApp(sio, other_asgi_app=app, socketio_path="socket.io")

# ---------- Helper Functions ----------
def str_to_objectid(id_str: str) -> ObjectId:
    """Convert string to MongoDB ObjectId"""
    try:
        return ObjectId(id_str)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid ID format")

def hash_password(password: str) -> bytes:
    """Hash password using bcrypt"""
    return bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt())

def verify_password(password: str, hashed: bytes) -> bool:
    """Verify password against hash"""
    try:
        return bcrypt.checkpw(password.encode('utf-8'), hashed)
    except Exception:
        return False

def create_jwt_token(user_id: ObjectId, role: str) -> str:
    """Create JWT token"""
    payload = {
        "sub": str(user_id),
        "role": role,
        "exp": datetime.datetime.utcnow() + datetime.timedelta(days=30),
        "iat": datetime.datetime.utcnow()
    }
    return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)

def decode_jwt_token(token: str) -> Dict[str, Any]:
    """Decode and verify JWT token"""
    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
        return payload
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token expired")
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=401, detail="Invalid token")

async def get_current_user(authorization: str = Header(None)) -> Dict[str, Any]:
    """Dependency to get current authenticated user"""
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing or invalid authorization header")
    
    token = authorization.replace("Bearer ", "")
    payload = decode_jwt_token(token)
    
    user = users.find_one({"_id": str_to_objectid(payload["sub"])})
    if not user:
        raise HTTPException(status_code=401, detail="User not found")
    
    user["_id"] = str(user["_id"])
    return user

def serialize_doc(doc: Dict) -> Dict:
    """Serialize MongoDB document for JSON response"""
    if doc is None:
        return None
    if isinstance(doc, list):
        return [serialize_doc(d) for d in doc]
    if "_id" in doc:
        doc["_id"] = str(doc["_id"])
    for key, value in doc.items():
        if isinstance(value, ObjectId):
            doc[key] = str(value)
        elif isinstance(value, datetime.datetime):
            doc[key] = value.isoformat()
    return doc

# ---------- Pydantic Models ----------
class RegisterClientRequest(BaseModel):
    name: str
    identifier: str  # email or phone
    password: str = Field(min_length=6)
    blood_group: Optional[str] = None
    has_medical_allergies: Optional[bool] = False

class RegisterDriverRequest(BaseModel):
    name: str
    email: EmailStr
    phone: str
    password: str = Field(min_length=6)
    driver_id: str
    vehicle_type: str
    vehicle_plate: str
    vehicle_model: str
    license_number: str

class RegisterHospitalRequest(BaseModel):
    hospital_name: str
    hospital_code: str
    password: str = Field(min_length=6)
    address: str
    phone: str
    email: EmailStr

class LoginClientRequest(BaseModel):
    identifier: str  # email or phone
    password: str

class LoginDriverRequest(BaseModel):
    driver_id: str
    password: str

class LoginAdminRequest(BaseModel):
    hospital_code: str
    password: str

class SOSRequest(BaseModel):
    location: Dict[str, float]  # {"lat": float, "lng": float}
    condition: Optional[str] = "other"
    preliminary_severity: Optional[str] = "unknown"
    sensor_data: Optional[Dict] = {}
    auto_triggered: Optional[bool] = False
    contact: Optional[str] = ""

class AcceptRequestRequest(BaseModel):
    request_id: str

class InjuryAssessmentRequest(BaseModel):
    request_id: str
    injury_risk: str
    injury_notes: str

class UpdateLocationRequest(BaseModel):
    location: Dict[str, float]  # {"lat": float, "lng": float}

class ConfirmAdmissionRequest(BaseModel):
    request_id: str
    action: str  # "accept" or "reject"

class UpdateCapacityRequest(BaseModel):
    capacity: Dict[str, int]

# ---------- Authentication Endpoints ----------
@app.post("/api/register/client")
async def register_client(payload: RegisterClientRequest):
    """Register a new client"""
    identifier = payload.identifier.strip()
    is_email = "@" in identifier
    
    # Check if user already exists
    if is_email:
        existing = users.find_one({"email": identifier.lower(), "role": "client"})
        if existing:
            raise HTTPException(status_code=409, detail="Email already registered")
    else:
        existing = users.find_one({"phone": identifier, "role": "client"})
        if existing:
            raise HTTPException(status_code=409, detail="Phone number already registered")
    
    # Create user document
    user_doc = {
        "role": "client",
        "name": payload.name.strip(),
        "password": hash_password(payload.password),
        "verified": False,
        "google_auth": False,
        "created_at": datetime.datetime.utcnow()
    }
    
    # Add email or phone
    if is_email:
        user_doc["email"] = identifier.lower()
    else:
        user_doc["phone"] = identifier
    
    # Add medical information
    if payload.blood_group:
        user_doc["blood_group"] = payload.blood_group
    if payload.has_medical_allergies is not None:
        user_doc["has_medical_allergies"] = bool(payload.has_medical_allergies)
    
    # Insert user
    result = users.insert_one(user_doc)
    token = create_jwt_token(result.inserted_id, "client")
    
    return {
        "success": True,
        "role": "client",
        "user_id": str(result.inserted_id),
        "token": token
    }

@app.post("/api/register/driver")
async def register_driver(payload: RegisterDriverRequest):
    """Register a new driver"""
    # Check duplicates
    if users.find_one({"email": payload.email.lower()}):
        raise HTTPException(status_code=409, detail="Email already registered")
    if users.find_one({"phone": payload.phone}):
        raise HTTPException(status_code=409, detail="Phone already registered")
    if users.find_one({"driver_id": payload.driver_id}):
        raise HTTPException(status_code=409, detail="Driver ID already taken")
    
    # Create user
    user_doc = {
        "role": "driver",
        "name": payload.name.strip(),
        "email": payload.email.lower(),
        "phone": payload.phone,
        "password": hash_password(payload.password),
        "created_at": datetime.datetime.utcnow()
    }
    user_result = users.insert_one(user_doc)
    
    # Create driver profile
    driver_doc = {
        "user_id": user_result.inserted_id,
        "driver_id": payload.driver_id,
        "name": payload.name,
        "email": payload.email.lower(),
        "phone": payload.phone,
        "vehicle_type": payload.vehicle_type,
        "vehicle_plate": payload.vehicle_plate,
        "vehicle_model": payload.vehicle_model,
        "license_number": payload.license_number,
        "status": "available",
        "active": True,
        "location": None,
        "created_at": datetime.datetime.utcnow()
    }
    ambulance_drivers.insert_one(driver_doc)
    
    token = create_jwt_token(user_result.inserted_id, "driver")
    
    return {
        "success": True,
        "role": "driver",
        "user_id": str(user_result.inserted_id),
        "token": token
    }

@app.post("/api/register/hospital")
async def register_hospital(payload: RegisterHospitalRequest):
    """Register a new hospital"""
    # Check duplicates
    if users.find_one({"email": payload.email.lower(), "role": "admin"}):
        raise HTTPException(status_code=409, detail="Email already registered")
    if hospitals.find_one({"hospital_code": payload.hospital_code}):
        raise HTTPException(status_code=409, detail="Hospital code already exists")
    
    # Create user
    user_doc = {
        "role": "admin",
        "name": payload.hospital_name,
        "email": payload.email.lower(),
        "phone": payload.phone,
        "password": hash_password(payload.password),
        "hospital_code": payload.hospital_code,
        "created_at": datetime.datetime.utcnow()
    }
    user_result = users.insert_one(user_doc)
    
    # Create hospital profile
    hospital_doc = {
        "user_id": user_result.inserted_id,
        "hospital_name": payload.hospital_name,
        "hospital_code": payload.hospital_code,
        "address": payload.address,
        "phone": payload.phone,
        "email": payload.email.lower(),
        "capacity": {
            "icu_beds": 0,
            "general_beds": 0,
            "doctors_available": 0
        },
        "location": None,
        "active": True,
        "created_at": datetime.datetime.utcnow()
    }
    hospitals.insert_one(hospital_doc)
    
    token = create_jwt_token(user_result.inserted_id, "admin")
    
    return {
        "success": True,
        "role": "admin",
        "user_id": str(user_result.inserted_id),
        "token": token
    }

@app.post("/api/login/client")
async def login_client(payload: LoginClientRequest):
    """Client login - optimized with indexes"""
    identifier = payload.identifier.strip()
    is_email = "@" in identifier
    
    # Use indexed queries for faster lookup
    if is_email:
        user = users.find_one(
            {"email": identifier.lower(), "role": "client"},
            projection={"_id": 1, "password": 1, "role": 1}  # Only fetch needed fields
        )
    else:
        user = users.find_one(
            {"phone": identifier, "role": "client"},
            projection={"_id": 1, "password": 1, "role": 1}
        )
    
    if not user or not verify_password(payload.password, user["password"]):
        raise HTTPException(status_code=401, detail="Invalid credentials")
    
    token = create_jwt_token(user["_id"], "client")
    
    return {
        "success": True,
        "token": token,
        "role": "client",
        "user_id": str(user["_id"])
    }

@app.post("/api/login/driver")
async def login_driver(payload: LoginDriverRequest):
    """Driver login - optimized with indexes"""
    # Use indexed query for faster lookup
    driver = ambulance_drivers.find_one(
        {"driver_id": payload.driver_id},
        projection={"_id": 1, "user_id": 1}
    )
    if not driver:
        raise HTTPException(status_code=401, detail="Driver not found")
    
    user = users.find_one(
        {"_id": driver["user_id"]},
        projection={"_id": 1, "password": 1, "role": 1}
    )
    if not user or not verify_password(payload.password, user["password"]):
        raise HTTPException(status_code=401, detail="Invalid credentials")
    
    token = create_jwt_token(user["_id"], "driver")
    
    return {
        "success": True,
        "token": token,
        "role": "driver",
        "user_id": str(user["_id"])
    }

@app.post("/api/login/admin")
async def login_admin(payload: LoginAdminRequest):
    """Hospital admin login - optimized with indexes"""
    # Use indexed query for faster lookup
    user = users.find_one(
        {"hospital_code": payload.hospital_code, "role": "admin"},
        projection={"_id": 1, "password": 1, "role": 1}
    )
    if not user or not verify_password(payload.password, user["password"]):
        raise HTTPException(status_code=401, detail="Invalid credentials")
    
    token = create_jwt_token(user["_id"], "admin")
    
    return {
        "success": True,
        "token": token,
        "role": "admin",
        "user_id": str(user["_id"])
    }

# ---------- Client Endpoints ----------
@app.post("/api/client/sos")
async def trigger_sos(payload: SOSRequest, current_user: Dict = Depends(get_current_user)):
    """Trigger SOS request"""
    if current_user.get("role") != "client":
        raise HTTPException(status_code=403, detail="Only clients can trigger SOS")
    
    location = payload.location
    if not location or "lat" not in location or "lng" not in location:
        raise HTTPException(status_code=400, detail="Location (lat, lng) is required")
    
    # Get user info
    user_name = current_user.get("name", "Unknown")
    user_contact = payload.contact or current_user.get("phone", "")
    blood_group = current_user.get("blood_group")
    has_medical_allergies = current_user.get("has_medical_allergies", False)
    
    # Create SOS request
    sos_doc = {
        "client_id": str_to_objectid(current_user["_id"]),
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
        "condition": payload.condition,
        "preliminary_severity": payload.preliminary_severity,
        "injury_level": None,
        "status": "pending",
        "auto_triggered": payload.auto_triggered,
        "sensor_data": payload.sensor_data,
        "vitals": {},
        "picked_up_at": None,
        "accepted_at": None,
        "assigned_at": None,
        "timestamp": datetime.datetime.utcnow()
    }
    
    result = patient_requests.insert_one(sos_doc)
    request_id = str(result.inserted_id)
    
    # Find nearby drivers
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
    
    # Emit socket event to drivers
    sos_alert_payload = {
        "request_id": request_id,
        "user_id": current_user["_id"],
        "user_name": user_name,
        "blood_group": blood_group,
        "has_medical_allergies": has_medical_allergies,
        "lat": location["lat"],
        "lng": location["lng"],
        "timestamp": datetime.datetime.utcnow().isoformat(),
        "sensor_data": payload.sensor_data,
        "preliminary_severity": payload.preliminary_severity,
        "contact": user_contact,
        "ttl_seconds": 30
    }
    
    await sio.emit('sos_alert', sos_alert_payload, room='drivers')
    
    for driver in nearby_drivers:
        driver_user_id = str(driver["user_id"])
        await sio.emit('sos_alert', sos_alert_payload, room=f'driver_{driver_user_id}')
    
    return {
        "success": True,
        "request_id": request_id,
        "status": "pending",
        "nearby_drivers_count": len(nearby_drivers)
    }

@app.get("/api/client/my_requests")
async def get_my_requests(current_user: Dict = Depends(get_current_user)):
    """Get client's SOS requests"""
    if current_user.get("role") != "client":
        raise HTTPException(status_code=403, detail="Only clients can access this")
    
    requests_list = list(patient_requests.find({
        "client_id": str_to_objectid(current_user["_id"])
    }).sort("timestamp", -1))
    
    return {
        "success": True,
        "requests": [serialize_doc(r) for r in requests_list]
    }

# ---------- Driver Endpoints ----------
@app.get("/api/driver/nearby_patients")
async def get_nearby_patients(current_user: Dict = Depends(get_current_user)):
    """Get nearby patient requests for driver"""
    if current_user.get("role") != "driver":
        raise HTTPException(status_code=403, detail="Only drivers can access this")
    
    # Get driver profile
    driver = ambulance_drivers.find_one({"user_id": str_to_objectid(current_user["_id"])})
    if not driver or not driver.get("location"):
        return {"success": True, "requests": []}
    
    # Find nearby requests
    nearby_requests = list(patient_requests.find({
        "status": "pending",
        "location": {
            "$near": {
                "$geometry": driver["location"],
                "$maxDistance": 20000  # 20km
            }
        }
    }).limit(10))
    
    return {
        "success": True,
        "requests": [serialize_doc(r) for r in nearby_requests]
    }

@app.post("/api/driver/accept_request")
async def accept_request(payload: AcceptRequestRequest, current_user: Dict = Depends(get_current_user)):
    """Driver accepts a request"""
    if current_user.get("role") != "driver":
        raise HTTPException(status_code=403, detail="Only drivers can accept requests")
    
    # Get driver profile
    driver = ambulance_drivers.find_one({"user_id": str_to_objectid(current_user["_id"])})
    if not driver:
        raise HTTPException(status_code=404, detail="Driver profile not found")
    
    # Find and update request
    sos_req = patient_requests.find_one({"_id": str_to_objectid(payload.request_id), "status": "pending"})
    if not sos_req:
        raise HTTPException(status_code=404, detail="Request not found or already accepted")
    
    # Update request
    patient_requests.update_one(
        {"_id": sos_req["_id"]},
        {
            "$set": {
                "status": "accepted",
                "driver_id": driver["user_id"],
                "accepted_at": datetime.datetime.utcnow()
            }
        }
    )
    
    # Update driver status
    ambulance_drivers.update_one(
        {"_id": driver["_id"]},
        {"$set": {"status": "busy"}}
    )
    
    # Notify client
    await sio.emit('driver_accepted', {
        "request_id": payload.request_id,
        "driver_name": driver.get("name"),
        "vehicle": driver.get("vehicle_type")
    }, room=str(sos_req["client_id"]))
    
    # Notify hospitals
    await sio.emit('incoming_patient', {
        "request_id": payload.request_id,
        "patient_name": sos_req.get("user_name"),
        "blood_group": sos_req.get("blood_group"),
        "has_medical_allergies": sos_req.get("has_medical_allergies"),
        "severity": sos_req.get("preliminary_severity")
    }, room='admin')
    
    return {"success": True}

@app.post("/api/driver/submit_assessment")
async def submit_injury_assessment(payload: InjuryAssessmentRequest, current_user: Dict = Depends(get_current_user)):
    """Driver submits injury assessment"""
    if current_user.get("role") != "driver":
        raise HTTPException(status_code=403, detail="Only drivers can submit assessments")
    
    # Update request with assessment
    result = patient_requests.update_one(
        {"_id": str_to_objectid(payload.request_id)},
        {
            "$set": {
                "injury_risk": payload.injury_risk,
                "injury_notes": payload.injury_notes,
                "status": "assessed",
                "assessment_time": datetime.datetime.utcnow()
            }
        }
    )
    
    if result.modified_count == 0:
        raise HTTPException(status_code=404, detail="Request not found")
    
    # Get request details
    req = patient_requests.find_one({"_id": str_to_objectid(payload.request_id)})
    
    # Notify hospital admins
    await sio.emit('injury_assessment_submitted', {
        "request_id": payload.request_id,
        "patient_name": req.get("user_name"),
        "injury_risk": payload.injury_risk,
        "injury_notes": payload.injury_notes,
        "blood_group": req.get("blood_group"),
        "has_medical_allergies": req.get("has_medical_allergies")
    }, room='admin')
    
    return {"success": True}

@app.post("/api/driver/update_location")
async def update_driver_location(payload: UpdateLocationRequest, current_user: Dict = Depends(get_current_user)):
    """Update driver's current location"""
    if current_user.get("role") != "driver":
        raise HTTPException(status_code=403, detail="Only drivers can update location")
    
    location = payload.location
    ambulance_drivers.update_one(
        {"user_id": str_to_objectid(current_user["_id"])},
        {
            "$set": {
                "location": {
                    "type": "Point",
                    "coordinates": [location["lng"], location["lat"]]
                }
            }
        }
    )
    
    return {"success": True}

# ---------- Hospital/Admin Endpoints ----------
@app.get("/api/hospital/patient_requests")
async def get_hospital_patient_requests(current_user: Dict = Depends(get_current_user)):
    """Get incoming patient requests for hospital"""
    if current_user.get("role") != "admin":
        raise HTTPException(status_code=403, detail="Only hospital admins can access this")
    
    # Get requests that are accepted or in transit
    requests_list = list(patient_requests.find({
        "status": {"$in": ["accepted", "enroute", "en_route", "picked_up", "assessed", "in_transit"]}
    }).sort("timestamp", -1))
    
    return {
        "success": True,
        "requests": [serialize_doc(r) for r in requests_list]
    }

@app.post("/api/hospital/confirm_admission")
async def confirm_admission(payload: ConfirmAdmissionRequest, current_user: Dict = Depends(get_current_user)):
    """Hospital confirms or rejects patient admission"""
    if current_user.get("role") != "admin":
        raise HTTPException(status_code=403, detail="Only hospital admins can confirm admissions")
    
    # Update request
    status = "admitted" if payload.action == "accept" else "rejected"
    result = patient_requests.update_one(
        {"_id": str_to_objectid(payload.request_id)},
        {
            "$set": {
                "status": status,
                "hospital_id": str_to_objectid(current_user["_id"]),
                "admission_time": datetime.datetime.utcnow()
            }
        }
    )
    
    if result.modified_count == 0:
        raise HTTPException(status_code=404, detail="Request not found")
    
    # Get request details
    req = patient_requests.find_one({"_id": str_to_objectid(payload.request_id)})
    
    # Notify driver and client
    if payload.action == "accept":
        await sio.emit('hospital_accepted', {
            "request_id": payload.request_id,
            "hospital_name": current_user.get("name")
        }, room=str(req.get("client_id")))
    
    return {"success": True, "status": status}

@app.post("/api/hospital/update_capacity")
async def update_hospital_capacity(payload: UpdateCapacityRequest, current_user: Dict = Depends(get_current_user)):
    """Update hospital capacity"""
    if current_user.get("role") != "admin":
        raise HTTPException(status_code=403, detail="Only hospital admins can update capacity")
    
    hospitals.update_one(
        {"user_id": str_to_objectid(current_user["_id"])},
        {"$set": {"capacity": payload.capacity}}
    )
    
    return {"success": True}

# ---------- Socket.IO Events ----------
@sio.event
async def connect(sid, environ):
    """Client connected"""
    logger.info(f"Client connected: {sid}")
    await sio.emit('connection_established', {'status': 'connected'}, to=sid)

@sio.event
async def disconnect(sid):
    """Client disconnected"""
    logger.info(f"Client disconnected: {sid}")

@sio.event
async def join(sid, data):
    """Join a room"""
    room = data.get('room')
    if room:
        # `enter_room` is not awaitable for the AsyncServer instance
        sio.enter_room(sid, room)
        logger.info(f"Client {sid} joined room: {room}")

@sio.event
async def leave(sid, data):
    """Leave a room"""
    room = data.get('room')
    if room:
        # `leave_room` is not awaitable for the AsyncServer instance
        sio.leave_room(sid, room)
        logger.info(f"Client {sid} left room: {room}")

# ---------- Health Check ----------
@app.get("/")
async def root():
    """API health check"""
    try:
        mongo_client.server_info()
        db_status = "connected"
    except Exception as e:
        db_status = f"error: {str(e)[:100]}"
    
    return {
        "status": "running",
        "service": "Smart-Aid FastAPI",
        "version": "2.0.0",
        "database": db_status
    }

@app.get("/health")
async def health(request: Request):
    """Detailed health check"""
    try:
        mongo_client.server_info()
        db_status = "connected"
    except Exception as e:
        db_status = f"error: {str(e)}"
    
    client_ip = request.client.host
    logger.info(f"OK GET    /health                                  | Status: 200 | Database: {db_status} | Client: {client_ip}")
    
    return {
        "status": "healthy",
        "database": db_status,
        "timestamp": datetime.datetime.utcnow().isoformat()
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "app_fastapi:socket_app",
        host="0.0.0.0",
        port=8000,
        reload=False,
        log_level="info"
    )
