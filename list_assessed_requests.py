from models import patient_requests
from bson import ObjectId

cursor = patient_requests.find({"status": "assessed"})
ids = [str(doc['_id']) for doc in cursor]
print('Assessed request ids:', ids)
