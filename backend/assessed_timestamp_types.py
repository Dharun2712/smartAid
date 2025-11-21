from models import patient_requests
from bson import ObjectId

for doc in patient_requests.find({"status": "assessed"}):
    ts = doc.get('timestamp')
    print(str(doc['_id']), type(ts), ts)
