"""Mine JEOPARDY_CSV.csv for general/international-knowledge candidates.

Streams the ~217k-row American Jeopardy archive, drops anything that depends on
English wordplay (via linguistic_filter) or reads as USA-specific civics/geography/
sports (via a keyword blocklist), and writes what survives grouped by category so a
human can pick which categories are genuinely universal before any of it is used as
grounding material for newly-generated packets. Nothing here is meant to be used
verbatim -- it is inspiration/fact-checking material for prompts, not a translation
source.

    python src/mine_csv_candidates.py

Writes:
    data/csv_category_counts.txt   -- surviving categories, most frequent first
    data/csv_candidates.jsonl      -- every surviving row (category, question, answer, value, round)
"""
import csv
import json
import os
import re
import sys
from collections import Counter

sys.path.insert(0, os.path.dirname(__file__))
from linguistic_filter import analyze_adaptability  # noqa: E402

SRC = os.path.join('data', 'JEOPARDY_CSV.csv')
OUT_COUNTS = os.path.join('data', 'csv_category_counts.txt')
OUT_ROWS = os.path.join('data', 'csv_candidates.jsonl')

US_STATES = [
    'alabama', 'alaska', 'arizona', 'arkansas', 'california', 'colorado', 'connecticut',
    'delaware', 'florida', 'georgia(?!n)', 'hawaii', 'idaho', 'illinois', 'indiana', 'iowa',
    'kansas', 'kentucky', 'louisiana', 'maine', 'maryland', 'massachusetts', 'michigan',
    'minnesota', 'mississippi', 'missouri', 'montana', 'nebraska', 'nevada',
    'new hampshire', 'new jersey', 'new mexico', 'new york', 'north carolina',
    'north dakota', 'ohio', 'oklahoma', 'oregon', 'pennsylvania', 'rhode island',
    'south carolina', 'south dakota', 'tennessee', 'texas', 'utah', 'vermont',
    'virginia', 'washington', 'west virginia', 'wisconsin', 'wyoming',
]

US_MARKERS = [
    r'united states', r'u\.s\.', r'\busa\b', r'\bamerican\b', r'\bamericans\b',
    r'america\'s', r'congress(?!o)', r'senat(e|or)', r'white house', r'supreme court',
    r'\bgovernor\b', r'\bcounty\b', r'\bzip code\b', r'capitol hill', r'\bpentagon\b',
    r'\bnfl\b', r'\bnba\b', r'\bnhl\b', r'\bmlb\b', r'\bncaa\b', r'super bowl',
    r'world series', r'\bnascar\b', r'\bnasdaq\b', r'\birs\b', r'founding fathers',
    r'\bconstitution\b', r'declaration of indep', r'\bstate of the union\b',
    r'\bchicago\b', r'\bmanhattan\b', r'\bbrooklyn\b', r'\btexas\b', r'\bcalifornia\b',
    r'\bhollywood\b', r'\bwashington,? d\.?c\.?\b', r'\bpresident(s)?\b',
    r'\bvice president\b', r'\bcabinet\b', r'this state\b', r'\bstateline\b',
    r'\bnyc\b', r'new york city', r'republican party', r'democratic party',
    r'\bcongressman\b', r'\bcongresswoman\b', r'\bveep\b', r'electoral college',
    r'secretary of state', r'department of', r'wall street', r'\bcapitol\b',
]

# Rows sourced with an embedded image/video reference (J-Archive clue crew
# shots, maps, photos) are visual clues -- unplayable here regardless of topic.
HTML_RE = re.compile(r'<[a-z][^>]*>|href=|\.jpg|\.png|\.gif', re.IGNORECASE)

BLOCK_RE = re.compile('|'.join(US_STATES + US_MARKERS), re.IGNORECASE)

# Categories that are structurally about English (crosswords, "before & after",
# rhymes, ...) get caught by linguistic_filter already; this catches a few more
# category-name patterns that filter is not aimed at.
BLOCK_CATEGORY_RE = re.compile(
    r'state\b|capitals?\b.*state|americana|u\.s\.|usa\b|baseball|football|basketball|'
    r'hockey|olympi.*u\.s|pop culture|sitcom|award show',
    re.IGNORECASE,
)


def main():
    counts = Counter()
    kept = 0
    seen_total = 0
    with open(SRC, encoding='utf-8', errors='replace') as fh, \
         open(OUT_ROWS, 'w', encoding='utf-8') as out:
        reader = csv.DictReader(fh)
        # Header has leading spaces on some column names in this dataset.
        reader.fieldnames = [h.strip() for h in reader.fieldnames]
        for row in reader:
            seen_total += 1
            category = (row.get('Category') or '').strip()
            question = (row.get('Question') or '').strip()
            answer = (row.get('Answer') or '').strip()
            if not category or not question or not answer:
                continue
            if HTML_RE.search(question) or HTML_RE.search(answer):
                continue
            if BLOCK_RE.search(category) or BLOCK_RE.search(question) or BLOCK_RE.search(answer):
                continue
            if BLOCK_CATEGORY_RE.search(category):
                continue
            status, _ = analyze_adaptability(category, question, answer)
            if status != 'კი':
                continue

            kept += 1
            counts[category] += 1
            out.write(json.dumps({
                'category': category,
                'question': question,
                'answer': answer,
                'value': (row.get('Value') or '').strip(),
                'round': (row.get('Round') or '').strip(),
            }, ensure_ascii=False) + '\n')

    with open(OUT_COUNTS, 'w', encoding='utf-8') as fh:
        for cat, n in counts.most_common():
            fh.write(f'{n}\t{cat}\n')

    print(f'scanned {seen_total} rows, kept {kept} ({kept/seen_total:.1%}), '
          f'{len(counts)} distinct surviving categories')
    print(f'-> {OUT_COUNTS}')
    print(f'-> {OUT_ROWS}')


if __name__ == '__main__':
    main()
