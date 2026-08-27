"""Build new Georgian Jeopardy packages from the translated JEOPARDY_CSV.csv pool.

Source: data/jeopardy_translated.db (built by jeopardy_translator.py from the
American JEOPARDY_CSV.csv / J-Archive dataset). Only rows that are fully
translated (status='DONE') AND flagged linguistically adaptable
(is_adaptable='კი') are eligible.

Strategy per package, to keep boards feeling like real episodes rather than a
random grab-bag:
  - Round 1 + Round 2: pulled from a single real show that has a full clean
    6x5 Jeopardy! round AND a full clean 6x5 Double Jeopardy! round.
  - Round 3: pulled from a second, different show's full clean 6x5 round
    (Jeopardy! or Double Jeopardy!) -- there's no third round in real
    Jeopardy!, so this is a second episode's board reused as round 3.
  - Final: two distinct clean Final Jeopardy! clues from other shows.

Value ladders (matching the existing pilot.json convention, not real dollar
values): R1 10/20/30/40/50, R2 20/40/60/80/100, R3 30/60/90/120/150, assigned
by ascending rank of the original dollar value within the category.

Outputs a *candidate* bundle (data/csv_packets_candidate.json) that keeps the
English originals alongside the Georgian text, for review (by agy / by hand)
before it's stripped down to the shipped schema.

Pure stdlib. Usage: python src/build_csv_packets.py [--seed N] [--count 20]
"""
import argparse
import json
import os
import random
import re
import sqlite3
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = os.path.join(ROOT, "data", "jeopardy_translated.db")
OUT = os.path.join(ROOT, "data", "csv_packets_candidate.json")

R1 = [10, 20, 30, 40, 50]
R2 = [20, 40, 60, 80, 100]
R3 = [30, 60, 90, 120, 150]

GEORGIAN_RE = re.compile(r"[Ⴀ-ჿ]")

# Google Translate renders all-caps English (every Jeopardy! category, e.g.
# "MEDICINE") as Georgian Mtavruli -- a real "capital" letterform block
# (U+1C90-U+1CBF) distinct from the everyday Mkhedruli one Georgian is
# normally written in. Georgian doesn't do per-word capitalization, so left
# alone every category name in this set would render in the wrong script.
MTAVRULI_RE = re.compile(r"[Ა-Ჿ]")


def normalize_georgian_case(text):
    if not text:
        return text
    return MTAVRULI_RE.sub(lambda m: chr(ord(m.group(0)) - 3008), text)


def parse_value(v):
    if not v:
        return None
    try:
        return int(v.replace("$", "").replace(",", "").strip())
    except ValueError:
        return None


def translation_ok(row):
    """Reject rows where the translator silently fell back to English."""
    cat_en, cat_ka, q_en, q_ka, a_en, a_ka = row
    if not (cat_ka and q_ka and a_ka):
        return False
    if cat_ka.strip() == cat_en.strip():
        return False
    if q_ka.strip() == q_en.strip():
        return False
    if a_ka.strip() == a_en.strip():
        return False
    if "�" in q_ka or "�" in a_ka:
        return False
    if not GEORGIAN_RE.search(q_ka):
        return False
    if not GEORGIAN_RE.search(a_ka):
        return False
    return True


def load_clean_categories(conn, round_name):
    """(show_number, category_en) -> list of 5 clue dicts, sorted by value asc.

    Only kept if all 5 rows are DONE + adaptable + pass translation_ok.
    """
    cur = conn.cursor()
    cur.execute(
        """
        SELECT show_number, air_date, category_en, category_ka, value,
               question_en, question_ka, answer_en, answer_ka
        FROM translations
        WHERE round = ? AND status = 'DONE' AND is_adaptable = 'კი'
        """,
        (round_name,),
    )
    groups = {}
    for show, air_date, cat_en, cat_ka, value, q_en, q_ka, a_en, a_ka in cur.fetchall():
        if not translation_ok((cat_en, cat_ka, q_en, q_ka, a_en, a_ka)):
            continue
        val = parse_value(value)
        if val is None:
            continue
        cat_ka = normalize_georgian_case(cat_ka)
        key = (show, cat_en)
        groups.setdefault(key, {"air_date": air_date, "cat_ka": cat_ka, "clues": []})
        groups[key]["clues"].append(
            {"value": val, "q_en": q_en, "q_ka": q_ka, "a_en": a_en, "a_ka": a_ka}
        )

    clean = {}
    for key, g in groups.items():
        clues = g["clues"]
        values = [c["value"] for c in clues]
        if len(clues) == 5 and len(set(values)) == 5:
            clues.sort(key=lambda c: c["value"])
            clean[key] = {"air_date": g["air_date"], "cat_ka": g["cat_ka"], "clues": clues}
    return clean


def load_clean_finals(conn):
    cur = conn.cursor()
    cur.execute(
        """
        SELECT show_number, air_date, category_en, category_ka,
               question_en, question_ka, answer_en, answer_ka
        FROM translations
        WHERE round = 'Final Jeopardy!' AND status = 'DONE' AND is_adaptable = 'კი'
        """
    )
    out = []
    for show, air_date, cat_en, cat_ka, q_en, q_ka, a_en, a_ka in cur.fetchall():
        if not translation_ok((cat_en, cat_ka, q_en, q_ka, a_en, a_ka)):
            continue
        out.append(
            {
                "show": show,
                "air_date": air_date,
                "cat_en": cat_en,
                "cat_ka": normalize_georgian_case(cat_ka),
                "q_en": q_en,
                "q_ka": q_ka,
                "a_en": a_en,
                "a_ka": a_ka,
            }
        )
    return out


def make_topic(cat_en, cat_ka, clues, ladder, show, air_date, round_name):
    entries = []
    for rank, clue in enumerate(clues):
        entries.append(
            {
                "value": ladder[rank],
                "question": clue["q_ka"],
                "answer": clue["a_ka"],
                "question_en": clue["q_en"],
                "answer_en": clue["a_en"],
                "original_value": clue["value"],
            }
        )
    return {
        "name": cat_ka,
        "name_en": cat_en,
        "source_show": show,
        "source_air_date": air_date,
        "source_round": round_name,
        "clues": entries,
    }


def build(seed, count, start_number):
    conn = sqlite3.connect(DB)

    clean_j = load_clean_categories(conn, "Jeopardy!")
    clean_dj = load_clean_categories(conn, "Double Jeopardy!")
    finals = load_clean_finals(conn)

    pool = []
    for (show, cat_en), g in clean_j.items():
        pool.append((show, "Jeopardy!", cat_en, g))
    for (show, cat_en), g in clean_dj.items():
        pool.append((show, "Double Jeopardy!", cat_en, g))

    need = count * 18
    if len(pool) < need:
        raise SystemExit(f"only {len(pool)} clean categories available, need {need}")
    if len(finals) < count * 2:
        raise SystemExit(f"only {len(finals)} clean final clues available, need {count * 2}")

    rng = random.Random(seed)
    rng.shuffle(pool)
    rng.shuffle(finals)

    packages = []
    pool_idx = 0
    final_idx = 0

    for i in range(count):
        pkg_number = start_number + i

        chosen = []
        used_names = set()
        used_shows_in_pkg = set()
        # first pass: prefer fresh category names and fresh shows for variety
        scan_from = pool_idx
        j = scan_from
        skipped = []
        while len(chosen) < 18 and j < len(pool):
            entry = pool[j]
            show, round_name, cat_en, g = entry
            if cat_en in used_names or show in used_shows_in_pkg:
                skipped.append(entry)
            else:
                chosen.append(entry)
                used_names.add(cat_en)
                used_shows_in_pkg.add(show)
            j += 1
        # second pass over skipped, relaxing the "one category per show" rule
        # if we still don't have 18 (only the category-name clash stays hard)
        k = 0
        while len(chosen) < 18 and k < len(skipped):
            show, round_name, cat_en, g = skipped[k]
            if cat_en not in used_names:
                chosen.append(skipped[k])
                used_names.add(cat_en)
            k += 1
        remaining_skipped = [e for e in skipped if e not in chosen]
        # rebuild pool: consumed entries removed, unused skipped ones go back in
        pool = pool[j:] + remaining_skipped
        pool_idx = 0
        if len(chosen) < 18:
            raise SystemExit(f"could not fill package {pkg_number}: only {len(chosen)} unique categories found")

        r1_src, r2_src, r3_src = chosen[0:6], chosen[6:12], chosen[12:18]
        r1_topics = [make_topic(cat_en, g["cat_ka"], g["clues"], R1, show, g["air_date"], rnd) for show, rnd, cat_en, g in r1_src]
        r2_topics = [make_topic(cat_en, g["cat_ka"], g["clues"], R2, show, g["air_date"], rnd) for show, rnd, cat_en, g in r2_src]
        r3_topics = [make_topic(cat_en, g["cat_ka"], g["clues"], R3, show, g["air_date"], rnd) for show, rnd, cat_en, g in r3_src]

        final_topics = []
        for _ in range(2):
            f = finals[final_idx]
            final_idx += 1
            final_topics.append(
                {
                    "name": f["cat_ka"],
                    "name_en": f["cat_en"],
                    "source_show": f["show"],
                    "source_air_date": f["air_date"],
                    "clues": [
                        {
                            "value": None,
                            "question": f["q_ka"],
                            "answer": f["a_ka"],
                            "question_en": f["q_en"],
                            "answer_en": f["a_en"],
                        }
                    ],
                }
            )

        package = {
            "number": pkg_number,
            "title": f"პაკეტი #{pkg_number}",
            "subtitle": "Jeopardy! Archive (J-Archive) — ინგლისურიდან თარგმნილი",
            "rounds": [
                {"index": 1, "is_final": False, "playable": True, "topics": r1_topics},
                {"index": 2, "is_final": False, "playable": True, "topics": r2_topics},
                {"index": 3, "is_final": False, "playable": True, "topics": r3_topics},
                {"index": 4, "is_final": True, "playable": False, "topics": final_topics},
            ],
        }
        packages.append(package)

    bundle = {
        "attribution": (
            "შეკითხვები: Jeopardy! (J-Archive არქივი, Sony Pictures Television / "
            "Jeopardy Productions). ორიგინალი ინგლისურენოვანია, ქართული თარგმანი -- "
            "მანქანური, human-reviewed შერჩევით. უფლებები ეკუთვნის მფლობელებს; "
            "პირადი, არაკომერციული გამოყენებისთვის."
        ),
        "source": "J-Archive / JEOPARDY_CSV.csv",
        "packages": packages,
    }
    return bundle


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--count", type=int, default=20)
    ap.add_argument("--start-number", type=int, default=7)
    ap.add_argument("--out", default=OUT)
    args = ap.parse_args()

    bundle = build(args.seed, args.count, args.start_number)

    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(bundle, f, ensure_ascii=False, indent=1)

    n_pkg = len(bundle["packages"])
    n_clues = sum(
        len(t["clues"])
        for p in bundle["packages"]
        for r in p["rounds"]
        for t in r["topics"]
    )
    print(f"packages {n_pkg}, clues {n_clues}")
    print(f"wrote {args.out} ({os.path.getsize(args.out)/1024:.0f} KB)")


if __name__ == "__main__":
    main()
