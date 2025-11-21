from bson import ObjectId
from models import hospitals

HOSPITAL_USER_ID = ObjectId("68fb5a67571c2f7bd110c0fb")

doc = hospitals.find_one({"user_id": HOSPITAL_USER_ID})
if not doc:
    print("Hospital not found for user_id:", HOSPITAL_USER_ID)
else:
    import json
    from datetime import datetime
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
