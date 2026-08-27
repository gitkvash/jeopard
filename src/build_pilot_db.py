"""Turn the scraped moazrovne.net packages into pilot app data.

These are authentic, curated Georgian tournament games, so the original
package/round/topic structure is preserved rather than assembling random
boards: one round == one playable Jeopardy board (6 topics x 5 clues).

Outputs
  data/pilot.db    SQLite, for querying
  data/pilot.json  bundle-ready asset (small enough to ship as-is)

Pure stdlib.  Usage:  python src/build_pilot_db.py
"""
import json
import os
import sqlite3
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "data", "moazrovne_corrected.json")
OUT_DB = os.path.join(ROOT, "data", "pilot.db")
OUT_JSON = os.path.join(ROOT, "data", "pilot.json")

ATTRIBUTION = ("შეკითხვები: moazrovne.net (რა? სად? როდის? არქივი). "
               "უფლებები ეკუთვნის ავტორებს.")

SCHEMA = """
PRAGMA journal_mode = OFF;
DROP TABLE IF EXISTS clue;
DROP TABLE IF EXISTS topic;
DROP TABLE IF EXISTS round;
DROP TABLE IF EXISTS package;

CREATE TABLE package (
    id         INTEGER PRIMARY KEY,
    number     INTEGER NOT NULL,
    title      TEXT    NOT NULL,
    subtitle   TEXT,
    source_url TEXT
);

CREATE TABLE round (
    id          INTEGER PRIMARY KEY,
    package_id  INTEGER NOT NULL REFERENCES package(id),
    idx         INTEGER NOT NULL,
    header      TEXT,
    is_final    INTEGER NOT NULL DEFAULT 0,
    topic_count INTEGER NOT NULL,
    playable    INTEGER NOT NULL DEFAULT 0   -- a full 6x5 board
);

CREATE TABLE topic (
    id       INTEGER PRIMARY KEY,
    round_id INTEGER NOT NULL REFERENCES round(id),
    idx      INTEGER NOT NULL,
    name     TEXT    NOT NULL
);

CREATE TABLE clue (
    id                INTEGER PRIMARY KEY,
    topic_id          INTEGER NOT NULL REFERENCES topic(id),
    value             INTEGER,
    question          TEXT NOT NULL,
    answer            TEXT NOT NULL,
    question_original TEXT,   -- set only where the 2008 wording was corrected
    answer_original   TEXT,
    correction_note   TEXT
);

CREATE INDEX idx_round_pkg   ON round(package_id);
CREATE INDEX idx_topic_round ON topic(round_id);
CREATE INDEX idx_clue_topic  ON clue(topic_id);
"""


def main():
    if not os.path.exists(SRC):
        print(f"missing {SRC} -- run scrape_moazrovne.py first")
        return 1
    packages = json.load(open(SRC, encoding="utf-8"))

    if os.path.exists(OUT_DB):
        os.remove(OUT_DB)
    db = sqlite3.connect(OUT_DB)
    db.executescript(SCHEMA)

    pid = rid = tid = cid = corrected = 0
    playable = finals = 0
    bundle = {"attribution": ATTRIBUTION, "source": "moazrovne.net", "packages": []}

    for pkg in packages:
        pid += 1
        db.execute(
            "INSERT INTO package (id,number,title,subtitle,source_url) VALUES (?,?,?,?,?)",
            (pid, pkg["package"], pkg["title"], pkg.get("subtitle"), pkg.get("source_url")),
        )
        b_pkg = {"number": pkg["package"], "title": pkg["title"],
                 "subtitle": pkg.get("subtitle"), "rounds": []}

        for rnd in pkg["rounds"]:
            rid += 1
            topics = rnd["topics"]
            # A board is 6 topics of 5 clues each; the last round is the final.
            is_board = len(topics) == 6 and all(len(t["clues"]) == 5 for t in topics)
            is_final = not is_board and all(len(t["clues"]) == 1 for t in topics)
            playable += int(is_board)
            finals += int(is_final)
            db.execute(
                "INSERT INTO round (id,package_id,idx,header,is_final,topic_count,playable)"
                " VALUES (?,?,?,?,?,?,?)",
                (rid, pid, rnd["index"], rnd.get("header"), int(is_final),
                 len(topics), int(is_board)),
            )
            b_rnd = {"index": rnd["index"], "is_final": is_final,
                     "playable": is_board, "topics": []}

            for t in topics:
                tid += 1
                db.execute("INSERT INTO topic (id,round_id,idx,name) VALUES (?,?,?,?)",
                           (tid, rid, t["index"], t["name"]))
                b_topic = {"name": t["name"], "clues": []}
                for c in sorted(t["clues"], key=lambda x: x["value"] or 0):
                    cid += 1
                    db.execute(
                        "INSERT INTO clue (id,topic_id,value,question,answer,"
                        "question_original,answer_original,correction_note) "
                        "VALUES (?,?,?,?,?,?,?,?)",
                        (cid, tid, c["value"], c["question"], c["answer"],
                         c.get("question_original"), c.get("answer_original"),
                         c.get("correction_note")),
                    )
                    entry = {"value": c["value"], "question": c["question"],
                             "answer": c["answer"]}
                    if c.get("correction_note"):
                        entry["correction_note"] = c["correction_note"]
                    b_topic["clues"].append(entry)
                    if c.get("correction_note"):
                        corrected += 1
                b_rnd["topics"].append(b_topic)
            b_pkg["rounds"].append(b_rnd)
        bundle["packages"].append(b_pkg)

    db.commit()
    db.execute("VACUUM")
    db.close()

    with open(OUT_JSON, "w", encoding="utf-8") as f:
        json.dump(bundle, f, ensure_ascii=False, indent=1)

    print(f"packages        {pid}")
    print(f"rounds          {rid}   (playable boards {playable}, finals {finals})")
    print(f"topics          {tid}")
    print(f"clues           {cid}   (corrected {corrected})")
    print(f"\n{OUT_DB}   {os.path.getsize(OUT_DB)/1024:.0f} KB")
    print(f"{OUT_JSON} {os.path.getsize(OUT_JSON)/1024:.0f} KB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
