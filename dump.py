import json
with open('data/agy_packets/packet_24.json', encoding='utf-8') as f:
    d = json.load(f)
with open('temp_clues.txt', 'w', encoding='utf-8') as out:
    for r in d['rounds']:
        for t in r['topics']:
            for c in t['clues']:
                out.write(f'R{r["index"]} {t["name"]} {c.get("value")}\nQ: {c["question"]}\nA: {c["answer"]}\n\n')
