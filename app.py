# app.py
import os
import datetime
from functools import wraps
from flask import Flask, request, jsonify
from pymongo import MongoClient
import bcrypt
import jwt

# ---------- CONFIG ----------
MONGO_URI = os.environ.get(
    "MONGO_URI",
    "mongodb+srv://Dharun:Dharun2712@cluster0.yr5quzl.mongodb.net/?retryWrites=true&w=majority&appName=Cluster0"
)
JWT_SECRET = os.environ.get("JWT_SECRET", "replace_this_with_env_secret")
JWT_ALGORITHM = "HS256"
JWT_EXP_DELTA_SECONDS = int(os.environ.get("JWT_EXP_SECONDS", 60 * 60 * 24))  # default: 1 day

# ---------- APP & DB ----------
app = Flask(__name__)
client = MongoClient(MONGO_URI)
db = client["smart_ambulance"]  # Specify database name
users = db.get_collection("users")  # one collection for all roles with role field

# ---------- UTIL ----------
def create_jwt(user_id, role):
    payload = {
        "sub": str(user_id),
        "role": role,
        "iat": datetime.datetime.utcnow(),
        "exp": datetime.datetime.utcnow() + datetime.timedelta(seconds=JWT_EXP_DELTA_SECONDS)
    }
    token = jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)
    if isinstance(token, bytes):
        token = token.decode("utf-8")
    return token

def verify_password(plain_password, hashed):
    return bcrypt.checkpw(plain_password.encode("utf-8"), hashed)

def json_error(msg, code=400):
    return jsonify({"success": False, "message": msg}), code

# Optional decorator to protect routes in the future
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

# ---------- ROUTES ----------
@app.route("/", methods=["GET"])
def health_check():
    """Health check endpoint"""
    return jsonify({
        "status": "ok",
        "message": "Smart Ambulance Backend API is running"
    }), 200

@app.route("/api/login/client", methods=["POST"])
def login_client():
    data = request.get_json() or {}
    # Accept either phone or email + password
    identifier = data.get("identifier", "").strip()
    password = data.get("password", "")

    if not identifier or not password:
        return json_error("Identifier and password are required", 400)

    # detect email or phone (simple heuristic)
    query = {}
    if "@" in identifier:
        query["email"] = identifier.lower()
    else:
        query["phone"] = identifier

    query["role"] = "client"
    user = users.find_one(query)
    if not user:
        return json_error("User not found", 404)

    hashed = user.get("password")
    if not hashed:
        return json_error("User has no password set", 400)

    if not verify_password(password, hashed):
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

    user = users.find_one({"role": "driver", "driver_id": driver_id})
    if not user:
        return json_error("Driver not found", 404)

    hashed = user.get("password")
    if not verify_password(password, hashed):
        return json_error("Invalid credentials", 401)

    token = create_jwt(user_id=user["_id"], role="driver")
    return jsonify({
        "success": True,
        "role": "driver",
        "user_id": str(user["_id"]),
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

# Optional: client registration endpoint (phone/email)
@app.route("/api/register/client", methods=["POST"])
def register_client():
    data = request.get_json() or {}
    identifier = data.get("identifier", "").strip()
    password = data.get("password", "")
    name = data.get("name", "").strip()

    if not identifier or not password or not name:
        return json_error("name, identifier (email/phone) and password are required", 400)

    query = {}
    if "@" in identifier:
        query["email"] = identifier.lower()
    else:
        query["phone"] = identifier

    # check uniqueness
    if users.find_one({"$or":[{"email": query.get("email")}, {"phone": query.get("phone")}] }):
        return json_error("User already exists", 409)

    hashed = bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt())
    document = {
        "role": "client",
        "name": name,
        "password": hashed,
        "created_at": datetime.datetime.utcnow()
    }
    if "email" in query:
        document["email"] = query["email"]
    if "phone" in query:
        document["phone"] = query["phone"]

    res = users.insert_one(document)
    token = create_jwt(user_id=res.inserted_id, role="client")
    return jsonify({
        "success": True,
        "role": "client",
        "user_id": str(res.inserted_id),
        "token": token
    }), 201

# Health check
@app.route("/api/health", methods=["GET"])
def health():
    return jsonify({"success": True, "message": "OK"}), 200

# ---------- RUN ----------
if __name__ == "__main__":
    # For development only. For production, run behind gunicorn / nginx with TLS.
    app.run(host="0.0.0.0", port=5000, debug=False)
