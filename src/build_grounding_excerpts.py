"""Build one grounding excerpt file per planned new packet.

Reads data/new_packets_plan.json (theme -> relevant whitelisted CSV categories)
and data/csv_grounding_pool.jsonl (the already-filtered, non-US, non-wordplay
pool), and writes data/grounding/packet_NN.txt: up to 60 real fact lines for
that theme, explicitly labelled as inspiration to verify and rewrite, not to
translate verbatim.

    python src/build_grounding_excerpts.py
"""
import json
import os
import random
from collections import defaultdict

PLAN = os.path.join('data', 'new_packets_plan.json')
POOL = os.path.join('data', 'csv_grounding_pool.jsonl')
OUT_DIR = os.path.join('data', 'grounding')
PER_PACKET = 60

HEADER = (
    "Real trivia facts pulled from a large English-language trivia archive, already "
    "filtered to remove anything USA-specific and any English wordplay. They are RAW "
    "INSPIRATION ONLY: verify every fact yourself before use, discard anything that "
    "turns out to still be US-centric, obscure, or dated, and never translate one of "
    "these verbatim -- write your own fresh Georgian clue once you have confirmed the "
    "underlying fact.\n\n"
)


def main():
    random.seed(2026)
    with open(PLAN, encoding='utf-8') as fh:
        plan = json.load(fh)

    by_category = defaultdict(list)
    with open(POOL, encoding='utf-8') as fh:
        for line in fh:
            row = json.loads(line)
            by_category[row['category']].append(row)

    os.makedirs(OUT_DIR, exist_ok=True)
    for entry in plan:
        rows = []
        for cat in entry['categories']:
            rows.extend(by_category.get(cat, []))
        random.shuffle(rows)
        # de-dup by question text, cap the count
        seen = set()
        picked = []
        for row in rows:
            if row['question'] in seen:
                continue
            seen.add(row['question'])
            picked.append(row)
            if len(picked) >= PER_PACKET:
                break

        out_path = os.path.join(OUT_DIR, f'packet_{entry["number"]:02d}.txt')
        with open(out_path, 'w', encoding='utf-8') as out:
            out.write(HEADER)
            for row in picked:
                out.write(f'[{row["category"]}] {row["question"]} -> {row["answer"]}\n')

        print(f'packet {entry["number"]}: {len(picked)} facts -> {out_path}')


if __name__ == '__main__':
    main()
