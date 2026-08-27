"""Puts back answer spellings that the repair pass dropped.

The fact-check pass was handed the validator's *warnings* as well as its errors,
and one of those warnings ("answer contains no Georgian letters") is advisory --
a year, an acronym or a Latin film title is a perfectly good answer. Taking it as
an instruction, the model rewrote answers like `M87` into `ემ-87` and stripped
parentheticals like `უკანასკნელ ამოსუნთქვაზე (À bout de souffle)` down to the
Georgian alone. Nothing became wrong, but the host lost the form they are most
likely to hear from a player.

This compares each changed answer against the snapshot taken before the repair
and restores what was lost:

  1. the new answer is just the old one with a parenthetical cut off  -> take the old
  2. the old answer had no Georgian at all (a year, an acronym, a title)
     and is not already quoted in the new one                        -> "new (old)"

Rule 2 keeps both forms, which is what the host actually wants: the Georgian to
read out and the original to recognise.

Usage:
    python src/restore_answer_forms.py <snapshot-dir> [--dry-run]
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import re
import sys

GEORGIAN = re.compile(r'[Ⴀ-ჿᲐ-Ჿ]')


def norm(text: str) -> str:
    return ' '.join(text.lower().split())


def index(doc: dict) -> dict:
    return {
        (rnd['index'], topic['name'], clue.get('value')): clue
        for rnd in doc['rounds']
        for topic in rnd['topics']
        for clue in topic['clues']
    }


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('snapshot', help='directory holding the pre-repair copies')
    ap.add_argument('--dry-run', action='store_true')
    args = ap.parse_args(argv)

    restored = 0
    combined = 0
    for old_path in sorted(glob.glob(os.path.join(args.snapshot, 'packet_*.json'))):
        name = os.path.basename(old_path)
        new_path = os.path.join('data', 'agy_packets', name)
        if not os.path.exists(new_path):
            continue

        with open(old_path, encoding='utf-8') as fh:
            old_doc = json.load(fh)
        with open(new_path, encoding='utf-8') as fh:
            new_doc = json.load(fh)

        old_clues = index(old_doc)
        new_clues = index(new_doc)
        touched = False

        for key, old in old_clues.items():
            new = new_clues.get(key)
            if new is None:
                continue
            old_a = (old.get('answer') or '').strip()
            new_a = (new.get('answer') or '').strip()
            if not old_a or old_a == new_a:
                continue

            dropped = ''
            if norm(new_a) in norm(old_a):
                dropped = norm(old_a).replace(norm(new_a), '', 1)

            # Only restore a cut-off tail that was in another script -- that is a
            # transliteration or an original title, and losing it costs the host
            # something. A tail in Georgian is an alternative answer, which the
            # repair pass may well have dropped on purpose.
            if dropped and not GEORGIAN.search(dropped):
                new['answer'] = old_a
                restored += 1
                touched = True
                print(f'{name} R{key[0]} | {key[1]} | {key[2]}\n'
                      f'  restored: {new_a!r} -> {old_a!r}')
            elif (not GEORGIAN.search(old_a)
                  and GEORGIAN.search(new_a)
                  and norm(old_a) not in norm(new_a)):
                combined_answer = f'{new_a} ({old_a})'
                new['answer'] = combined_answer
                combined += 1
                touched = True
                print(f'{name} R{key[0]} | {key[1]} | {key[2]}\n'
                      f'  combined: {new_a!r} + {old_a!r}')

        if touched and not args.dry_run:
            with open(new_path, 'w', encoding='utf-8') as fh:
                json.dump(new_doc, fh, ensure_ascii=False, indent=2)
                fh.write('\n')

    print(f'\n{restored} answer(s) restored, {combined} combined'
          f'{" (dry run, nothing written)" if args.dry_run else ""}')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
