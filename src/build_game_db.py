"""Convert the Google-translated Jeopardy data into a game-ready SQLite DB.

Source : data/jeopardy_translated.db  (translations table, filled by
         jeopardy_translator.py -- re-run this script as more rows finish)
Output : data/jeopardy_game.db

Boards are assembled by the app at runtime, not baked in here: it picks N
board_ready categories at random, which gives far more variety than a fixed
set of boards. A category is board_ready when all 5 clues are present with 5
distinct values and every one is marked adaptable to Georgian.

Pure stdlib -- no venv needed.  Usage:  python src/build_game_db.py
"""
import os
import re
import sqlite3
import sys
from collections import Counter, defaultdict

# The Windows console defaults to cp1252, which cannot print Georgian.
try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_DB = os.path.join(ROOT, "data", "jeopardy_translated.db")
OUT_DB = os.path.join(ROOT, "data", "jeopardy_game.db")

ADAPT_YES = "კი"
ADAPT_NO = "არა"
ADAPT_PARTIAL = "ნაწილობრივ"

BOARD_ROUNDS = ("Jeopardy!", "Double Jeopardy!")

# Archaic Georgian letters, dropped from the alphabet in 1879. Real modern
# Georgian never uses them, so they flag a mistranslation.
ARCHAIC_RE = re.compile(r"[ჱჲჳჴჵ]")
GEO_RE = re.compile(r"[ა-ჰ]")

SCHEMA = """
PRAGMA journal_mode = OFF;
DROP TABLE IF EXISTS clue;
DROP TABLE IF EXISTS category;

CREATE TABLE category (
    id          INTEGER PRIMARY KEY,
    name_ka     TEXT    NOT NULL,
    name_en     TEXT    NOT NULL,
    show_number INTEGER,
    air_date    TEXT,
    round       TEXT    NOT NULL,
    clue_count  INTEGER NOT NULL,
    board_ready INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE clue (
    id            INTEGER PRIMARY KEY,
    category_id   INTEGER NOT NULL REFERENCES category(id),
    value         INTEGER,
    question_ka   TEXT    NOT NULL,
    answer_ka     TEXT    NOT NULL,
    question_en   TEXT,
    answer_en     TEXT,
    is_adaptable  TEXT,
    adapt_reason  TEXT
);

CREATE INDEX idx_clue_category ON clue(category_id);
CREATE INDEX idx_clue_value    ON clue(value);
CREATE INDEX idx_cat_ready     ON category(board_ready, round);
"""


def parse_value(v):
    m = re.search(r"([\d,]+)", v or "")
    return int(m.group(1).replace(",", "")) if m else None


def main():
    if not os.path.exists(SRC_DB):
        print(f"missing source DB: {SRC_DB}")
        return 1

    src = sqlite3.connect(SRC_DB)
    src.row_factory = sqlite3.Row
    rows = src.execute(
        """SELECT * FROM translations
           WHERE status = 'DONE'
             AND TRIM(COALESCE(question_ka,'')) <> ''
             AND TRIM(COALESCE(answer_ka,''))   <> ''
             AND TRIM(COALESCE(category_ka,'')) <> ''"""
    ).fetchall()
    src.close()
    print(f"translated rows available: {len(rows):,}")

    groups = defaultdict(list)
    for r in rows:
        groups[(r["show_number"], r["round"], r["category_en"])].append(r)

    if os.path.exists(OUT_DB):
        os.remove(OUT_DB)
    db = sqlite3.connect(OUT_DB)
    db.executescript(SCHEMA)

    qc = Counter()
    cat_id = clue_id = ready = 0
    for (show, rnd, cat_en), items in groups.items():
        cat_id += 1
        values = [parse_value(i["value"]) for i in items]
        all_yes = all((i["is_adaptable"] or "") == ADAPT_YES for i in items)
        is_ready = int(
            rnd in BOARD_ROUNDS
            and len(items) == 5
            and len({v for v in values if v is not None}) == 5
            and all(v is not None for v in values)
            and all_yes
        )
        ready += is_ready
        first = items[0]
        db.execute(
            "INSERT INTO category (id,name_ka,name_en,show_number,air_date,"
            "round,clue_count,board_ready) VALUES (?,?,?,?,?,?,?,?)",
            (cat_id, first["category_ka"], cat_en,
             int(show) if str(show).isdigit() else None,
             first["air_date"], rnd, len(items), is_ready),
        )
        for item in sorted(items, key=lambda x: parse_value(x["value"]) or 0):
            clue_id += 1
            db.execute(
                "INSERT INTO clue (id,category_id,value,question_ka,answer_ka,"
                "question_en,answer_en,is_adaptable,adapt_reason) "
                "VALUES (?,?,?,?,?,?,?,?,?)",
                (clue_id, cat_id, parse_value(item["value"]),
                 item["question_ka"], item["answer_ka"],
                 item["question_en"], item["answer_en"],
                 item["is_adaptable"], item["adaptability_reason"]),
            )

            # read-only QC: report, never rewrite the translation
            for field in ("category_ka", "question_ka", "answer_ka"):
                if ARCHAIC_RE.search(item[field] or ""):
                    qc[f"archaic_letters:{field}"] += 1
            ans = (item["answer_ka"] or "").strip("\"“”'.,!?() ")
            if len(ans) >= 6 and ans.lower() in (item["question_ka"] or "").lower():
                if (item["question_en"] or "").count(",") < 2:
                    qc["answer_visible_in_question"] += 1
            if len(item["question_en"] or "") >= 40:
                ratio = len(item["question_ka"]) / len(item["question_en"])
                if ratio < 0.55:
                    qc["possibly_truncated"] += 1

    db.commit()
    db.execute("VACUUM")

    adapt = Counter(r["is_adaptable"] for r in rows)
    print(f"\ncategories        {cat_id:,}")
    print(f"  board_ready     {ready:,}  -> {ready // 6:,} full boards")
    print(f"clues             {clue_id:,}")
    print("\nadaptability (from their linguistic filter):")
    for k, v in adapt.most_common():
        print(f"  {k}: {v:,}")
    print("\nQC findings (reported only, text left untouched):")
    if qc:
        for k, v in qc.most_common():
            print(f"  {k}: {v:,}")
    else:
        print("  none")
    print(f"\nsize {os.path.getsize(OUT_DB)/1e6:.1f} MB -> {OUT_DB}")
    db.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
