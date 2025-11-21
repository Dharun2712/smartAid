from models import patient_requests
ids = [
'68fb5b4e19612cbaf5e5f2a6', '68ff6e15eb99b3f7509245eb', '68ff8add0f68d5b019e69603',
'68ff7649bb07f45e382e002d', '68ff834b278397006a271550', '68ff7fdb278397006a27154f',
'68ff7cdc49d1942d4255dd74', '68ff7b9c07564430e137984a', '68ff74d6bb07f45e382e002c',
'68ff6ff3a63463307bd2f709', '68ff792852a111b6382e7b29', '68ff71c2bb07f45e382e002b', '68fb5a67571c2f7bd110c106'
]
from bson import ObjectId
for _id in ids:
    doc = patient_requests.find_one({'_id': ObjectId(_id)})
    loc = doc.get('location') if doc else None
    print(_id, '->', loc)
