"""Builds the set of packages the backend seeds.

`data/pilot.json` stays exactly what `build_pilot_db.py` produced: the six
authentic moazrovne.net games, untouched, and the baseline the duplicate check
in `validate_packets.py` runs against. This script leaves it alone and writes a
second file that is the original six *plus* whatever validated packages are in
`data/agy_packets/`, renumbered to follow on.

Provenance is not left implicit. Generated packages say so in their subtitle,
which is what the host sees while picking one, and the credit line the app shows
names both origins -- the 2008 questions belong to their authors and the new ones
were not written by them.

Usage:
    python src/merge_packets.py                 # write data/packets_all.json + backend copy
    python src/merge_packets.py --check         # report what would change, write nothing
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import re
import shutil
import subprocess
import sys

# One scraped clue carries a stray glyph from the source page (U+F04A). No font
# has a private-use codepoint, so on web it makes the engine go looking for a
# fallback font mid-frame and paints a box when it fails. Stripped here rather
# than in data/pilot.json, which stays exactly as the pipeline produced it.
PRIVATE_USE = re.compile(r'[-\U000f0000-\U000ffffd]')

PILOT = os.path.join('data', 'pilot.json')
GENERATED_GLOB = os.path.join('data', 'agy_packets', 'packet_*.json')
MERGED = os.path.join('data', 'packets_all.json')
BACKEND_SEED = os.path.join('backend', 'src', 'main', 'resources', 'pilot.json')

GENERATED_NOTE = 'გენერირებული პაკეტი (AI)'
# The seeder already reads source_url and the API already returns it, so this is
# how a client tells generated packages from archive ones without matching on
# subtitle text.
GENERATED_SOURCE = 'generated:gemini-3.1-pro'
GENERATED_CREDIT = 'პაკეტები #7 და შემდეგ: AI-ით გენერირებული შეკითხვები.'


def load(path: str) -> dict:
    with open(path, encoding='utf-8') as fh:
        return json.load(fh)


def clue_count(pkg: dict) -> int:
    return sum(len(t.get('clues', []))
               for r in pkg.get('rounds', [])
               for t in r.get('topics', []))


def label(pkg: dict) -> str:
    """Mark a generated package so a host picking one knows what it is."""
    subtitle = (pkg.get('subtitle') or '').strip()
    if GENERATED_NOTE in subtitle:
        return subtitle
    return f'{GENERATED_NOTE} · {subtitle}' if subtitle else GENERATED_NOTE


def scrub(pkg: dict) -> int:
    """Remove characters no bundled font can paint. Returns how many."""
    removed = 0
    for rnd in pkg.get('rounds', []):
        for topic in rnd.get('topics', []):
            for field in ('name',):
                if isinstance(topic.get(field), str):
                    cleaned, n = PRIVATE_USE.subn('', topic[field])
                    topic[field], removed = cleaned, removed + n
            for clue in topic.get('clues', []):
                for field in ('question', 'answer', 'correction_note'):
                    if isinstance(clue.get(field), str):
                        cleaned, n = PRIVATE_USE.subn('', clue[field])
                        clue[field], removed = cleaned, removed + n
    return removed


def build() -> tuple[dict, list[str]]:
    pilot = load(PILOT)
    original = pilot['packages']
    notes = [f'{len(original)} original packages from {PILOT}']

    generated = []
    for path in sorted(glob.glob(GENERATED_GLOB)):
        data = load(path)
        packages = data['packages'] if 'packages' in data else [data]
        for pkg in packages:
            generated.append((path, pkg))

    number = len(original)
    merged = [*original]
    for path, pkg in generated:
        number += 1
        pkg = dict(pkg)
        pkg['number'] = number
        pkg['title'] = f'პაკეტი #{number}'
        pkg['subtitle'] = label(pkg)
        pkg['source_url'] = GENERATED_SOURCE
        merged.append(pkg)
        notes.append(f'#{number} <- {os.path.basename(path)} '
                     f'({clue_count(pkg)} clues) {pkg["subtitle"]}')

    scrubbed = sum(scrub(pkg) for pkg in merged)
    if scrubbed:
        notes.append(f'stripped {scrubbed} unpaintable private-use character(s)')

    credit = pilot.get('attribution', '').strip()
    if generated and GENERATED_CREDIT not in credit:
        credit = f'{credit} {GENERATED_CREDIT}'.strip()

    return {
        'attribution': credit,
        'source': pilot.get('source', 'moazrovne.net'),
        'packages': merged,
    }, notes


def validate(path: str) -> bool:
    """Run the same gate the generated packets had to pass, on the merged file.

    Duplicate detection is against the file itself here (--against ""), because
    comparing the merged set to pilot.json would flag every original clue as a
    duplicate of itself.
    """
    result = subprocess.run(
        [sys.executable, os.path.join('src', 'validate_packets.py'),
         '--against', '', path],
        capture_output=True, text=True, encoding='utf-8', errors='replace',
    )
    tail = [line for line in result.stdout.splitlines() if 'ERROR' in line]
    print(result.stdout.splitlines()[-1] if result.stdout else '(no output)')
    for line in tail[:20]:
        print(f'  {line}')
    return result.returncode == 0


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--check', action='store_true',
                    help='report and validate, but write nothing')
    args = ap.parse_args(argv)

    doc, notes = build()
    for note in notes:
        print(note)

    total = sum(clue_count(p) for p in doc['packages'])
    print(f'\n{len(doc["packages"])} packages, {total} clues')
    print(f'credit line: {doc["attribution"]}')

    target = MERGED + ('.check' if args.check else '')
    with open(target, 'w', encoding='utf-8') as fh:
        json.dump(doc, fh, ensure_ascii=False, indent=2)
        fh.write('\n')

    print()
    ok = validate(target)

    if args.check:
        os.remove(target)
        print('\n--check: nothing written')
        return 0 if ok else 1

    if not ok:
        os.remove(target)
        print('\nvalidation failed -- nothing written')
        return 1

    shutil.copyfile(MERGED, BACKEND_SEED)
    print(f'\nwrote {MERGED}')
    print(f'wrote {BACKEND_SEED}')
    print('\nThe seeder only runs on an empty content table, so an already '
          'seeded database will ignore this. Reseed with:\n'
          '    .\\backend\\reseed.ps1')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
