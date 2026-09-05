"""Finds clues that re-ask something the game already asks.

[`validate_packets.py`](validate_packets.py) compares question text for *exact*
equality after normalisation, and never looks at the answer field at all. That
catches a copy-paste and nothing else: a clue built from the same three facts in
a different order sails through it. Every one of packets 43-45 passed that gate
clean while still carrying a re-ask, and the shipped corpus has 47 of them.

Word-level comparison is not enough either, because Georgian inflects by suffix:
``მეურნეობა`` and ``მეურნეობისთვის`` are one root wearing two endings, and
comparing whole words scores two clues about the same thing as unrelated. So
tokens are truncated to a stem before they are compared -- the root sits at the
front of a Georgian word.

Four shapes, in descending order of how much they matter:

  A  a clue whose wording largely matches another clue           a re-ask
  B  the same answer used twice inside one package               a free point
  C  the same answer in two of the packages being checked        judgement
  D  the same answer as an existing clue, worded differently     usually fine

A and B are defects and set the exit code. C and D are reported for a human to
look at: a genuinely different angle on the same answer is normal, and the
corpus is full of them (the Nile is a river, a flood and a calendar).

Not wired into ``merge_packets.py``. The existing 42 packages contain 47 A-shaped
pairs and 37 B-shaped ones of their own, so making this a merge gate would block
every merge until the back catalogue is cleaned -- which is a content decision,
not a build step.

Usage:
    python src/near_duplicates.py data/packets_all.json data/agy_packets/packet_43.json
    python src/near_duplicates.py data/packets_all.json data/agy_packets/*.json
    python src/near_duplicates.py --self data/packets_all.json

Exit code is 0 only when no A or B pair is found.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import unicodedata
from itertools import combinations

WORD = re.compile(r'[^\wႠ-ჿᲐ-Ჿ]+')

# Georgian function words, plus the framing this game uses in nearly every clue
# ("this", "name the", "in the year"). Left in, they inflate every score.
STOP = set('''ეს ამ იგი მან მას რომ და თუ არის იყო არა მაგრამ როცა სადაც რომელიც
რომელსაც რომელმაც მისი მათი ერთ ერთი ორი სამი ამის იმ იმის მისმა დაასახელეთ
წელს წლის საუკუნეში ასევე უფრო ყველაზე შემდეგ დროს გამო შესახებ თავისი'''.split())

# Jaccard overlap of stemmed content words. 0.40 was picked against the known
# pairs in packets 43-45: the Tutankhamun and Nile re-asks score 0.50, and the
# highest-scoring legitimate pair found in review sits at 0.10.
THRESHOLD = 0.40

# Characters of a word kept as its stem. Six is long enough to keep distinct
# roots apart and short enough to survive Georgian case and postposition
# endings.
STEM = 6


def stems(text: str) -> set[str]:
    text = unicodedata.normalize('NFKC', text).lower()
    return {w[:STEM] for w in WORD.sub(' ', text).split()
            if len(w) > 3 and w not in STOP}


def norm_answer(answer: str) -> str:
    """Fold an answer for comparison, dropping any parenthetical gloss."""
    answer = unicodedata.normalize('NFKC', answer).lower()
    answer = re.sub(r'\(.*?\)', '', answer)
    return ' '.join(WORD.sub(' ', answer).split())


def clues(path: str, label: str) -> list[dict]:
    with open(path, encoding='utf-8') as fh:
        doc = json.load(fh)
    packages = doc['packages'] if 'packages' in doc else [doc]
    return [
        {
            'pkg': pkg.get('number'),
            'label': f'{label}#{pkg.get("number")}',
            'topic': topic['name'],
            'question': clue['question'],
            'answer': clue['answer'],
            'ans': norm_answer(clue['answer']),
            'stems': stems(clue['question']),
        }
        for pkg in packages
        for rnd in pkg['rounds']
        for topic in rnd['topics']
        for clue in topic['clues']
    ]


def overlap(a: set[str], b: set[str]) -> float:
    return len(a & b) / len(a | b) if a and b else 0.0


def report(pair: tuple[float, dict, dict]) -> None:
    # Each side prints its own answer. A pair can match on wording alone, and
    # showing one answer for both makes a legitimate pair look like a repeat.
    score, left, right = pair
    same = ' (same answer)' if left['ans'] and left['ans'] == right['ans'] else ''
    print()
    print(f'  [overlap {score:.2f}]{same}')
    for side, clue in (('A', left), ('B', right)):
        print(f'     {side}  {clue["label"]} / {clue["topic"]}  ->  {clue["answer"]}')
        print(f'        {clue["question"][:170]}')


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('corpus', help='the set already in the game, e.g. data/packets_all.json')
    ap.add_argument('candidates', nargs='*',
                    help='package files to check against it')
    ap.add_argument('--self', action='store_true',
                    help='check the corpus against itself instead')
    args = ap.parse_args(argv)

    if args.self:
        corpus = []
        fresh = clues(args.corpus, 'p')
        print(f'{len(fresh)} clues, checked against each other\n')
    else:
        if not args.candidates:
            ap.error('give at least one package file, or pass --self')
        corpus = clues(args.corpus, 'corpus')
        fresh = [c for path in args.candidates for c in clues(path, 'new')]
        print(f'{len(fresh)} candidate clues vs {len(corpus)} already in the game\n')

    reask, reworded = [], []
    for new in fresh:
        for old in corpus:
            score = overlap(new['stems'], old['stems'])
            if score >= THRESHOLD:
                reask.append((score, new, old))
            elif new['ans'] and new['ans'] == old['ans']:
                reworded.append((score, new, old))

    within, across = [], []
    for left, right in combinations(fresh, 2):
        score = overlap(left['stems'], right['stems'])
        if score >= THRESHOLD:
            reask.append((score, left, right))
        elif left['ans'] and left['ans'] == right['ans']:
            (within if left['pkg'] == right['pkg'] else across).append((score, left, right))

    print(f'=== A. re-ask, overlap >= {THRESHOLD}: {len(reask)} ===')
    for pair in sorted(reask, key=lambda p: -p[0]):
        report(pair)
    if not reask:
        print('  none')

    print(f'\n=== B. same answer twice in one package: {len(within)} ===')
    for pair in within:
        report(pair)
    if not within:
        print('  none')

    print(f'\n=== C. same answer in two different packages: {len(across)} ===')
    for _, left, right in across:
        print(f'  {left["answer"]:34.34}  {left["label"]}/{left["topic"][:24]:24.24}'
              f' vs {right["label"]}/{right["topic"][:24]}')
    if not across:
        print('  none')

    print(f'\n=== D. same answer as an existing clue, reworded: {len(reworded)} '
          f'(informational) ===')

    defects = len(reask) + len(within)
    print(f'\n{defects} defect(s)' if defects else '\nclean')
    return 1 if defects else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
