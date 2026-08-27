"""Scrape the native-Georgian Jeopardy ("სვოიაკი") packages from moazrovne.net.

These are original Georgian questions, so they avoid every translation
problem the machine-translated set has.

NOTE ON RIGHTS: moazrovne.net states that rights to the questions belong to
their respective authors (© ნოდარ დავითური). Fine for a local pilot; get
permission before shipping publicly. Author/date metadata is preserved on
every row so attribution is always available.

Output: data/moazrovne.json   Usage: python src/scrape_moazrovne.py
"""
import html
import json
import os
import re
import sys
import time
import urllib.request

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "data", "moazrovne.json")
BASE = "http://moazrovne.net/jeopardy/"
PACKAGES = range(1, 7)
UA = "Mozilla/5.0 (compatible; personal-archive-tool)"

TAG_RE = re.compile(r"<[^>]+>")
WS_RE = re.compile(r"\s+")

ROUND_RE = re.compile(
    r'<div class="jeopardy_round">(.*?)(?=<div class="jeopardy_round">|<div class="print_foot"|\Z)',
    re.S,
)
ROUND_HEAD_RE = re.compile(r'class="subtitle content_subtitle">(.*?)</strong>', re.S)
TOPIC_RE = re.compile(
    r'<li class="jeopardy_topic">(.*?)(?=<li class="jeopardy_topic">|\Z)', re.S
)
TOPIC_TITLE_RE = re.compile(r'class="topic_title">(.*?)</strong>', re.S)
QITEM_RE = re.compile(r'<li class="clearfix">(.*?)</li>', re.S)
SCORE_RE = re.compile(r'class="question_score">(.*?)</strong>', re.S)
QTEXT_RE = re.compile(r'<p class="question">(.*?)</p>', re.S)
ATEXT_RE = re.compile(r'class="answer_text">(.*?)</span>', re.S)
H2_RE = re.compile(r"<h2>(.*?)</h2>", re.S)
SUB_RE = re.compile(r'<strong class="subtitle">(.*?)</strong>', re.S)
IMG_RE = re.compile(r"<img\b", re.I)


def clean(s):
    if s is None:
        return None
    s = re.sub(r"<br\s*/?>", " ", s, flags=re.I)
    s = TAG_RE.sub("", s)
    return WS_RE.sub(" ", html.unescape(s)).strip()


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode("utf-8", errors="replace")


def parse_package(num, page):
    title = clean((H2_RE.search(page) or [None, ""])[1]) if H2_RE.search(page) else f"პაკეტი #{num}"
    subtitle = clean(SUB_RE.search(page).group(1)) if SUB_RE.search(page) else None

    rounds = []
    for r_i, rblock in enumerate(ROUND_RE.findall(page), 1):
        head = ROUND_HEAD_RE.search(rblock)
        topics = []
        for t_i, tblock in enumerate(TOPIC_RE.findall(rblock), 1):
            tt = TOPIC_TITLE_RE.search(tblock)
            topic_title = clean(tt.group(1)) if tt else f"თემა {t_i}"
            # "თემა 1: სრუტეები" -> "სრუტეები"
            topic_name = re.sub(r"^თემა\s*\d+\s*:\s*", "", topic_title).strip()
            clues = []
            for qblock in QITEM_RE.findall(tblock):
                sc = SCORE_RE.search(qblock)
                qt = QTEXT_RE.search(qblock)
                at = ATEXT_RE.search(qblock)
                if not (qt and at):
                    continue
                score_txt = clean(sc.group(1)) if sc else ""
                m = re.search(r"\d+", score_txt or "")
                clues.append({
                    "value": int(m.group(0)) if m else None,
                    "question": clean(qt.group(1)),
                    "answer": clean(at.group(1)),
                    "has_image": bool(IMG_RE.search(qblock)),
                })
            if clues:
                topics.append({"index": t_i, "name": topic_name, "clues": clues})
        if topics:
            rounds.append({
                "index": r_i,
                "header": clean(head.group(1)) if head else None,
                "topics": topics,
            })
    return {
        "package": num,
        "title": title,
        "subtitle": subtitle,
        "source_url": f"{BASE}{num}",
        "rounds": rounds,
    }


def main():
    packages = []
    for num in PACKAGES:
        url = f"{BASE}{num}"
        print(f"fetching {url}")
        pkg = parse_package(num, fetch(url))
        nq = sum(len(t["clues"]) for r in pkg["rounds"] for t in r["topics"])
        nt = sum(len(r["topics"]) for r in pkg["rounds"])
        print(f"  rounds {len(pkg['rounds'])}  topics {nt}  questions {nq}")
        packages.append(pkg)
        time.sleep(1.0)  # be polite

    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(packages, f, ensure_ascii=False, indent=1)

    tq = sum(len(t["clues"]) for p in packages for r in p["rounds"] for t in r["topics"])
    tt = sum(len(r["topics"]) for p in packages for r in p["rounds"])
    print(f"\ntotal: {len(packages)} packages, {tt} topics, {tq} questions")
    print(f"wrote {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
