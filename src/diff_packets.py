"""Shows every clue that differs between two copies of a packet set.

Generated content gets repaired by the model that wrote it, which is efficient and
completely unauditable unless the edits are laid out side by side. This does that:
point it at a snapshot taken before the repair pass and at the current files, and
it prints each changed clue by (round, topic, value) with both versions.

Usage:
    python src/diff_packets.py <before-dir> <after-dir>
    python src/diff_packets.py <before-dir> <after-dir> --brief
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import sys


def clues(path: str) -> dict[tuple[int, str, object], dict]:
    """Index a packet by (round, topic, value) so edits can be matched up."""
    with open(path, encoding='utf-8') as fh:
        doc = json.load(fh)
    out: dict[tuple[int, str, object], dict] = {}
    for rnd in doc.get('rounds', []):
        for topic in rnd.get('topics', []):
            for clue in topic.get('clues', []):
                key = (rnd.get('index'), topic.get('name'), clue.get('value'))
                # A topic can hold two clues of the same value only if something
                # is already wrong; keep the first and let the validator shout.
                out.setdefault(key, clue)
    return out


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('before')
    ap.add_argument('after')
    ap.add_argument('--brief', action='store_true',
                    help='counts only, no clue text')
    args = ap.parse_args(argv)

    total_changed = 0
    total_clues = 0
    for before_path in sorted(glob.glob(os.path.join(args.before, 'packet_*.json'))):
        name = os.path.basename(before_path)
        after_path = os.path.join(args.after, name)
        if not os.path.exists(after_path):
            print(f'{name}: missing in {args.after}')
            continue

        before = clues(before_path)
        after = clues(after_path)
        total_clues += len(after)

        changed = []
        for key, old in before.items():
            new = after.get(key)
            if new is None:
                changed.append((key, old, None))
            elif (old.get('question') != new.get('question')
                  or old.get('answer') != new.get('answer')):
                changed.append((key, old, new))
        added = [k for k in after if k not in before]

        total_changed += len(changed)
        head = f'{name}: {len(changed)} clue(s) changed'
        if added:
            head += f', {len(added)} moved/added key(s)'
        print(f'\n=== {head}')

        if args.brief:
            continue

        for (rnd, topic, value), old, new in changed:
            print(f'\n  R{rnd} | {topic} | {value}')
            if new is None:
                print('    REMOVED (topic or value changed)')
                print(f'    was Q: {old.get("question")}')
                continue
            if old.get('question') != new.get('question'):
                print(f'    -Q {old.get("question")}')
                print(f'    +Q {new.get("question")}')
            if old.get('answer') != new.get('answer'):
                print(f'    -A {old.get("answer")}')
                print(f'    +A {new.get("answer")}')
        for key in added:
            print(f'\n  R{key[0]} | {key[1]} | {key[2]}  (new key)')
            print(f'    +Q {after[key].get("question")}')
            print(f'    +A {after[key].get("answer")}')

    print(f'\n{total_changed} clue(s) changed across {total_clues} clue(s)')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
