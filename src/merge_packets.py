"""Builds the set of packages the backend seeds.

`data/pilot.json` stays exactly what `build_pilot_db.py` produced: the six
authentic moazrovne.net games, untouched, and the baseline the duplicate check
in `validate_packets.py` runs against. This script leaves it alone and writes a
second file that is the original six *plus* whatever validated packages are in
`data/agy_packets/` (Gemini), `data/argon_packets/` (Argon AI) and
`data/ai_packets/` (any other AI), in the order of the numbers they declare.

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

if sys.stdout and hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

# One scraped clue carries a stray glyph from the source page (U+F04A). No font
# has a private-use codepoint, so on web it makes the engine go looking for a
# fallback font mid-frame and paints a box when it fails. Stripped here rather
# than in data/pilot.json, which stays exactly as the pipeline produced it.
PRIVATE_USE = re.compile(r'[-\U000f0000-\U000ffffd]')

PILOT = os.path.join('data', 'pilot.json')
GEMINI_GLOB = os.path.join('data', 'agy_packets', 'packet_*.json')
ARGON_GLOB = os.path.join('data', 'argon_packets', 'packet_*.json')
# Generated packages from any other AI. They are listed with the Gemini ones,
# not in the Argon section.
AI_GLOB = os.path.join('data', 'ai_packets', 'packet_*.json')
MERGED = os.path.join('data', 'packets_all.json')
BACKEND_SEED = os.path.join('backend', 'src', 'main', 'resources', 'pilot.json')

GENERATED_NOTE_GEMINI = 'გენერირებული პაკეტი (Gemini)'
GENERATED_NOTE_ARGON = 'გენერირებული პაკეტი (Argon AI)'
GENERATED_NOTE_AI = 'გენერირებული პაკეტი (AI)'
# The seeder already reads source_url and the API already returns it, so this is
# how a client tells generated packages from archive ones without matching on
# subtitle text.
GENERATED_SOURCE_GEMINI = 'generated:gemini-3.1-pro'
GENERATED_SOURCE_ARGON = 'generated:argon'
GENERATED_SOURCE_AI = 'generated:ai'
SOURCES = (
    (GEMINI_GLOB, GENERATED_SOURCE_GEMINI, GENERATED_NOTE_GEMINI, 'Gemini AI-ით'),
    (ARGON_GLOB, GENERATED_SOURCE_ARGON, GENERATED_NOTE_ARGON, 'Argon AI-ით'),
    (AI_GLOB, GENERATED_SOURCE_AI, GENERATED_NOTE_AI, 'AI-ით'),
)
NOTES = {source: note for _, source, note, _ in SOURCES}
# A previous run's "პაკეტები #7-50: ..." sentences, stripped from the credit
# line before the current ranges are written into it.
OLD_CREDIT = re.compile(r'\s*პაკეტ(?:ი|ები) #[^.]*\.')


def load(path: str) -> dict:
    with open(path, encoding='utf-8') as fh:
        return json.load(fh)


def clue_count(pkg: dict) -> int:
    return sum(len(t.get('clues', []))
               for r in pkg.get('rounds', [])
               for t in r.get('topics', []))


def label(pkg: dict, source_url: str) -> str:
    """Mark a generated package so a host picking one knows what it is."""
    subtitle = (pkg.get('subtitle') or '').strip()
    prefix = NOTES[source_url]
    if prefix in subtitle:
        return subtitle
    for old_prefix in ('გენერირებული პაკეტი (AI) · ', 'გენერირებული პაკეტი (AI)'):
        if subtitle.startswith(old_prefix):
            subtitle = subtitle[len(old_prefix):].strip()
    return f'{prefix} · {subtitle}' if subtitle else prefix


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
    original = pilot['packages'][:6]
    notes = [f'{len(original)} original packages from {PILOT}']

    generated = []
    for pattern, source_url, _, _ in SOURCES:
        for path in sorted(glob.glob(pattern)):
            data = load(path)
            packages = data['packages'] if 'packages' in data else [data]
            for pkg in packages:
                generated.append((path, pkg, source_url))
    # Ordered by the number each file declares, not by directory: a package
    # added to an earlier directory must still land after everything already
    # seeded, or the seeder's positional ids would shift under live games.
    generated.sort(key=lambda g: g[1].get('number') or 0)

    number = len(original)
    merged = [*original]
    runs: list[list] = []
    for path, pkg, source_url in generated:
        number += 1
        if pkg.get('number') != number:
            raise SystemExit(f'{path} declares #{pkg.get("number")} but would be '
                             f'merged as #{number}; packages must be numbered '
                             f'contiguously from #{len(original) + 1}')
        if runs and runs[-1][0] == source_url:
            runs[-1][2] = number
        else:
            runs.append([source_url, number, number])
        pkg = dict(pkg)
        pkg['number'] = number
        pkg['title'] = f'პაკეტი #{number}'
        pkg['subtitle'] = label(pkg, source_url)
        pkg['source_url'] = source_url
        merged.append(pkg)
        notes.append(f'#{number} <- {os.path.basename(path)} '
                     f'({clue_count(pkg)} clues) {pkg["subtitle"]}')

    scrubbed = sum(scrub(pkg) for pkg in merged)
    if scrubbed:
        notes.append(f'stripped {scrubbed} unpaintable private-use character(s)')

    credit = OLD_CREDIT.sub('', pilot.get('attribution', '')).strip()
    by_source = {source: by for _, source, _, by in SOURCES}
    for source_url, first, last in runs:
        span = f'პაკეტი #{first}' if first == last else f'პაკეტები #{first}-{last}'
        credit = f'{credit} {span}: {by_source[source_url]} გენერირებული შეკითხვები.'

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
    shutil.copyfile(MERGED, PILOT)
    print(f'\nwrote {MERGED}')
    print(f'wrote {BACKEND_SEED}')
    print(f'wrote {PILOT}')
    print('\nThe seeder only runs on an empty content table, so an already '
          'seeded database will ignore this. Reseed with:\n'
          '    .\\backend\\reseed.ps1')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
