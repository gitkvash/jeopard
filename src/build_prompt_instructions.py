"""Render one self-contained instruction file per planned new packet.

Each file is what gets handed to an agy (Gemini 3.1 Pro) session as "read this
file, then do exactly what it says" -- keeps the actual `-p` shell argument
short (avoids Windows quoting pain with a multi-paragraph prompt) and keeps the
schema/rules identical across all 20 so nothing drifts between them.

    python src/build_prompt_instructions.py
"""
import json
import os

PLAN = os.path.join('data', 'new_packets_plan.json')
OUT_DIR = os.path.join('data', 'prompts')
REPO_ROOT = 'C:/Users/giorg/Desktop/jeopard'

TEMPLATE = """# Task: author package #{n} for "ჯეოპარდი"

Working directory: {repo_root} -- every path below is relative to this.

You are writing one complete question package for a Georgian-language,
Jeopardy-style trivia game. Output a single JSON file at
`data/agy_packets/packet_{nn}.json` matching this exact schema:

```json
{{
  "number": {n},
  "title": "პაკეტი #{n}",
  "subtitle": "{subtitle}",
  "rounds": [
    {{"index": 1, "is_final": false, "playable": true, "topics": [ ...6 topics... ]}},
    {{"index": 2, "is_final": false, "playable": true, "topics": [ ...6 topics... ]}},
    {{"index": 3, "is_final": false, "playable": true, "topics": [ ...6 topics... ]}},
    {{"index": 4, "is_final": true,  "playable": false, "topics": [ ...2 topics... ]}}
  ]
}}
```

Each topic in rounds 1-3: `{{"name": "<Georgian topic name, <=40 chars>", "clues": [ ...5 clues... ]}}`.
Each topic in round 4 (final): `{{"name": "...", "clues": [ ...1 clue... ]}}`.

Each clue: `{{"value": <int or null>, "question": "<clue text, read aloud, Georgian>", "answer": "<the correct response>"}}`.

Value ladders, in order, one topic's 5 clues carry exactly these 5 values:
- Round 1: 10, 20, 30, 40, 50
- Round 2: 20, 40, 60, 80, 100
- Round 3: 30, 60, 90, 120, 150
- Round 4 (final): `null` for both clues, no ladder.

Total: 6 topics x 5 clues x 3 rounds = 90 board clues, plus 2 final clues = 92 clues.

## Content rules

- Everything is read aloud and played by ear -- no clue may reference an image,
  map, or video ("in the picture...", "shown here..."). Every clue must stand
  alone as pure text.
- Write in fluent, modern Georgian (Mkhedruli). Never use the archaic letters
  ჱ ჲ ჳ ჴ ჵ ჸ ჶ -- they left the alphabet in the 19th century, and their
  presence is the signature of machine-translated text pretending to be
  Georgian.
- **General/international knowledge only. This is explicitly NOT an American
  trivia set.** Do not write any clue that assumes American civics, geography,
  sports leagues (NFL/NBA/MLB/NHL/NCAA), presidents, or domestic pop culture as
  background knowledge. World history, world geography, science, the arts,
  mythology, nature -- anything a well-read person anywhere in the world could
  reasonably know or work out -- is exactly the target.
- Difficulty should climb with value: 10/20/30-point clues should be gettable
  by a reasonably well-read adult; 100/120/150-point clues can be genuinely
  hard and specific.
- Never spell the answer out inside the question.
- The answer field can be a Latin-script proper noun/title where that is
  natural (a film title, a Latin species name), but the question itself must
  be Georgian prose.
- No topic name may repeat within the same round of this package, and none may
  exceed 40 characters.
- **Avoid repeating a topic already used somewhere in this game's other 30
  packages.** The full list is in `data/used_topics.txt` -- read it first. Pick
  20 topic names (18 board + 2 final) that are not on that list and not
  near-duplicates of something on it.
- Every fact must be independently verifiable and correct. If you are not
  confident a fact is accurate, do not use it -- pick something you are sure of
  instead.

## Package theme

Subtitle: "{subtitle}" -- let this loosely color your topic choices, but the 6
topics in a round do not have to share one narrow subject: varied
general-knowledge topics under a loose umbrella is exactly the style of the
rest of this game. Read `data/agy_packets/packet_30.json` first for the tone,
phrasing style and difficulty this game is going for.

## Optional grounding

`data/grounding/packet_{nn}.txt` has real trivia facts pulled from a large
English-language archive, pre-filtered to remove USA-specific and
wordplay-dependent material. Treat them as inspiration only: verify each fact
against your own knowledge before using it, discard any that are still
US-flavored, obscure, or that you cannot confirm, and never translate one
verbatim -- write your own fresh Georgian clue once you have confirmed the
underlying fact. Feel free to write clues that are not from this file at all
if you know better material.

## Before you finish

1. Write the file.
2. Run: `python src/validate_packets.py --against data/packets_all.json data/agy_packets/packet_{nn}.json`
3. Fix every ERROR it reports (warnings are informational -- use judgement,
   but a warning about a visual reference or a very short question is worth a
   second look). Re-run until it reports the package clean.
4. Report back, briefly: the 20 topic names you used, and confirmation the
   validator is clean.
"""


def main():
    with open(PLAN, encoding='utf-8') as fh:
        plan = json.load(fh)

    os.makedirs(OUT_DIR, exist_ok=True)
    for entry in plan:
        n = entry['number']
        nn = f'{n:02d}'
        text = TEMPLATE.format(n=n, nn=nn, subtitle=entry['subtitle'], repo_root=REPO_ROOT)
        out_path = os.path.join(OUT_DIR, f'packet_{nn}_instructions.md')
        with open(out_path, 'w', encoding='utf-8') as out:
            out.write(text)
        print(f'-> {out_path}')


if __name__ == '__main__':
    main()
