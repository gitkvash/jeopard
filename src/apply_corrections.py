"""Apply corrections.py to the scraped data, writing a corrected copy.

Never edits moazrovne.json -- output goes to moazrovne_corrected.json, so the
raw scrape stays the source of truth and this is safe to re-run.

Every touched clue keeps question_original / answer_original plus a note, so
the change is auditable and reversible.

Usage:  python src/apply_corrections.py
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from corrections import ANSWER_NOTES, CORRECTIONS

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "data", "moazrovne.json")
OUT = os.path.join(ROOT, "data", "moazrovne_corrected.json")


def flat(packages):
    """Same traversal order the index numbers were generated from."""
    for p in packages:
        for r in p["rounds"]:
            for t in r["topics"]:
                for c in t["clues"]:
                    yield c


def main():
    packages = json.load(open(SRC, encoding="utf-8"))
    clues = list(flat(packages))
    print(f"clues: {len(clues)}")

    errors = []
    applied = 0

    for fix in CORRECTIONS:
        i = fix["idx"]
        if i >= len(clues):
            errors.append(f"#{i}: index out of range")
            continue
        c = clues[i]
        if c["answer"].strip() != fix["answer"].strip():
            errors.append(f"#{i}: answer mismatch (expected {fix['answer']!r}, got {c['answer']!r})")
            continue
        if fix["old"] not in c["question"]:
            errors.append(f"#{i}: text to replace not found")
            continue
        c.setdefault("question_original", c["question"])
        c["question"] = c["question"].replace(fix["old"], fix["new"])
        c["correction_note"] = fix["note"]
        applied += 1

    for fix in ANSWER_NOTES:
        i = fix["idx"]
        c = clues[i]
        if c["answer"].strip() != fix["answer"].strip():
            errors.append(f"#{i}: answer mismatch for note")
            continue
        c.setdefault("answer_original", c["answer"])
        c["answer"] = fix["new_answer"]
        c["correction_note"] = fix["note"]
        applied += 1

    print(f"applied: {applied}")
    if errors:
        print("\nFAILED:")
        for e in errors:
            print(f"  {e}")

    json.dump(packages, open(OUT, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(f"\nwrote {OUT}")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
