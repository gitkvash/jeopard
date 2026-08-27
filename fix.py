import json
import codecs
with open('data/agy_packets/packet_35.json', 'r', encoding='utf-8-sig') as f:
    data = json.load(f)
with open('data/agy_packets/packet_35.json', 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
