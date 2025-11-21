from bson import ObjectId
from models import patient_requests

TEST_ID = ObjectId("68ff93ee2818c98908e14c18")

doc = patient_requests.find_one({"_id": TEST_ID})
if not doc:
    print("Document not found for id:", TEST_ID)
else:
    import json
    from datetime import datetime
    # Convert ObjectId and datetime for pretty print
    def norm(v):
        if isinstance(v, ObjectId):
            return str(v)
        if isinstance(v, datetime):
            return v.isoformat()
        return v

    def clean(d):
        out = {}
        for k, val in d.items():
            if isinstance(val, dict):
                out[k] = {kk: norm(vv) for kk, vv in val.items()}
            else:
                out[k] = norm(val)
        return out

    print(json.dumps(clean(doc), indent=2))
