import json

with open('data/agy_packets/packet_23.json', encoding='utf-8') as f:
    data = json.load(f)

for r in data['rounds']:
    for t in r['topics']:
        for c in t['clues']:
            q = c.get('question', '')
            
            # Fix 1: R1 T6 C4
            if 'ეს უფრთო (უფრო სწორად უთავო)' in q:
                c['question'] = q.replace('ეს უფრთო (უფრო სწორად უთავო)', 'ეს ფრთოსანი (თუმცა უთავო)')
                
            # Fix 2: R4 T2 C1
            if '21 წელი მუშაობდა აღმოსავლეთის კარებზე' in q:
                c['question'] = q.replace('21 წელი მუშაობდა აღმოსავლეთის კარებზე', '27 წელი მუშაობდა აღმოსავლეთის კარებზე')
                
            # Fix 3: Validator warnings
            if 'რენე მაგრიტის სურათზე' in q:
                c['question'] = q.replace('რენე მაგრიტის სურათზე', 'რენე მაგრიტის ტილოზე')
            if 'ამ შემზარავ სურათზე' in q:
                c['question'] = q.replace('ამ შემზარავ სურათზე', 'ამ შემზარავ ნამუშევარზე')
            if 'უფროსის სურათზე' in q:
                c['question'] = q.replace('უფროსის სურათზე', 'უფროსის ტილოზე')
            if 'დავიდის სურათზე' in q:
                c['question'] = q.replace('დავიდის სურათზე', 'დავიდის ტილოზე')
            if 'ეპიკურ სურათზე' in q:
                c['question'] = q.replace('ეპიკურ სურათზე', 'ეპიკურ ტილოზე')
            if 'გოგის სურათზე' in q:
                c['question'] = q.replace('გოგის სურათზე', 'გოგის ტილოზე')
            if 'იდუმალ სურათზე' in q:
                c['question'] = q.replace('იდუმალ სურათზე', 'იდუმალ ტილოზე')

with open('data/agy_packets/packet_23.json', 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)

print("Patch applied.")
