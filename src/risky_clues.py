"""Ranks clues by how easy they are to get wrong, for a human review pass.

Every error the independent audit actually confirmed belonged to one of a few
classes, and all of them are visible in the question text:

  superlatives and firsts   "the fastest-growing", "the only bird", "the first to"
  a stated date             the Bauhaus "in the 1920s", the calendar "in 1792"
  an etymology              the pound named after a 453 g weight
  a named attribution       who did the killing, who cut which ear
  a bare numeric claim      heights, counts, distances

A clue with none of those is usually just a definition and hard to get wrong. A
clue with three is where the errors live. This scores each clue on those signals
so a review pass can start at the top instead of reading 1,840 clues in file
order.

Usage:
    python src/risky_clues.py                       # top 40 across all generated packets
    python src/risky_clues.py --packets 11-30 --top 60
    python src/risky_clues.py --packet 17 --all
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import re
import sys

SIGNALS = [
    ('first/only', 3, re.compile(
        r'(პირველ|ერთადერთ|უძველეს|ბოლო\s+მეფ|თავდაპირველ)')),
    ('superlative', 3, re.compile(
        r'(ყველაზე|უდიდეს|უმაღლეს|უგრძეს|უმცირეს|უძლიერეს|ყველაზეც)')),
    ('etymology', 3, re.compile(
        r'(მომდინარეობს|ეტიმოლოგ|სიტყვიდან|ნიშნავს|სახელი\s+მიენიჭა|ეწოდა)')),
    ('date', 2, re.compile(r'\b1[0-9]{3}\b|\b20[0-2][0-9]\b|საუკუნე')),
    ('attribution', 2, re.compile(
        r'(მიერ|ავტორ|შექმნა|დააფუძნ|აღმოაჩინ|გამოიგონა|დაწერა)')),
    ('number', 1, re.compile(r'\b\d{2,}\b')),
    ('considered', 1, re.compile(r'(ითვლება|მიიჩნევა|მიჩნეულ)')),
]


def score(question: str) -> tuple[int, list[str]]:
    total = 0
    hits = []
    for name, weight, pattern in SIGNALS:
        if pattern.search(question):
            total += weight
            hits.append(name)
    return total, hits


def parse_range(spec: str) -> set[str]:
    out: set[str] = set()
    for part in spec.split(','):
        part = part.strip()
        if '-' in part:
            lo, _, hi = part.partition('-')
            out.update(f'{n:02d}' for n in range(int(lo), int(hi) + 1))
        elif part:
            out.add(f'{int(part):02d}')
    return out


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--packets', default='07-30', help='e.g. 11-30 or 17,18')
    ap.add_argument('--packet', help='shorthand for a single packet')
    ap.add_argument('--top', type=int, default=40)
    ap.add_argument('--all', action='store_true', help='ignore --top')
    ap.add_argument('--min-score', type=int, default=6)
    args = ap.parse_args(argv)

    wanted = parse_range(args.packet or args.packets)

    rows = []
    for path in sorted(glob.glob(os.path.join('data', 'agy_packets', 'packet_*.json'))):
        number = os.path.basename(path)[7:9]
        if number not in wanted:
            continue
        with open(path, encoding='utf-8') as fh:
            doc = json.load(fh)
        for rnd in doc['rounds']:
            for topic in rnd['topics']:
                for clue in topic['clues']:
                    s, hits = score(clue['question'])
                    rows.append((s, number, rnd['index'], topic['name'],
                                 clue.get('value'), clue['question'],
                                 clue['answer'], hits))

    rows.sort(key=lambda r: (-r[0], r[1], r[2]))
    shown = [r for r in rows if r[0] >= args.min_score]
    if not args.all:
        shown = shown[:args.top]

    for s, number, rnd, topic, value, question, answer, hits in shown:
        print(f'[{s}] #{number} R{rnd} | {topic} | {value}  ({", ".join(hits)})')
        print(f'  Q: {question}')
        print(f'  A: {answer}')

    print(f'\n{len(shown)} shown of {len(rows)} clue(s) in packets '
          f'{min(wanted)}-{max(wanted)}; '
          f'{sum(1 for r in rows if r[0] >= args.min_score)} at or above score '
          f'{args.min_score}')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
