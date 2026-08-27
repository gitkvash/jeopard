import json

with open('data/agy_packets/packet_23.json', encoding='utf-8') as f:
    data = json.load(f)

with open('clues.txt', 'w', encoding='utf-8') as out:
    for r_idx, r in enumerate(data['rounds']):
        for t_idx, t in enumerate(r['topics']):
            for c_idx, c in enumerate(t['clues']):
                out.write(f"R{r_idx+1} T{t_idx+1} C{c_idx+1} (Value: {c.get('value')})\n")
                out.write(f"Q: {c.get('question')}\n")
                out.write(f"A: {c.get('answer')}\n\n")
