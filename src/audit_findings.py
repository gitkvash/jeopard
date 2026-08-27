"""Cross-references the independent audits of the generated packets.

Two models that did not write the content audit every generated package, and
each writes findings as `FINDING | round=... | topic=... | value=... |
confidence=... | problem=... | correct=...` lines. This collects those lines and
groups them by the clue they point at.

The grouping is the point. A clue flagged by two different architectures is
real evidence. A clue flagged by one is a lead to check by hand -- and each
auditor produces some noise, so a single flag is not a verdict.

Usage:
    python src/audit_findings.py <log-dir>                 # summary + agreed findings
    python src/audit_findings.py <log-dir> --all           # every finding
    python src/audit_findings.py <log-dir> --packet 17     # one package
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import difflib
import re
import sys
from collections import defaultdict

FINDING = re.compile(r'^\s*FINDING\s*\|')
CHECKED = re.compile(r'^\s*CHECKED\s*\|')


def parse_fields(line: str) -> dict[str, str]:
    fields: dict[str, str] = {}
    for part in line.split('|')[1:]:
        if '=' not in part:
            continue
        key, _, value = part.partition('=')
        fields[key.strip().lower()] = value.strip()
    return fields


def norm_value(raw: str) -> str:
    raw = (raw or '').strip().lower()
    return 'final' if raw in ('null', 'none', '', '-') else raw


_CACHE: dict[str, dict] = {}


def packet_doc(packet: str) -> dict | None:
    """The packet as written, so findings can be resolved against reality."""
    if packet not in _CACHE:
        path = os.path.join('data', 'agy_packets', f'packet_{packet}.json')
        _CACHE[packet] = (json.load(open(path, encoding='utf-8'))
                          if os.path.exists(path) else None)
    return _CACHE[packet]


def resolve(packet: str, round_idx: str, value: str, topic: str):
    """Map a reported (round, topic, value) onto the actual clue.

    Two auditors describe the same clue differently -- one quotes the topic with
    Georgian quotation marks, the other translates or trims it -- so matching on
    the reported text alone makes every finding look unique. Resolving against
    the file gives both a canonical key, which is what makes agreement visible.
    """
    doc = packet_doc(packet)
    if doc is None:
        return None, None
    for rnd in doc['rounds']:
        if str(rnd['index']) != str(round_idx):
            continue
        candidates = []
        for idx, t in enumerate(rnd['topics']):
            for clue in t['clues']:
                if norm_value(str(clue.get('value'))) == value:
                    candidates.append((idx, t['name'], clue))
        if not candidates:
            continue
        if len(candidates) == 1:
            idx, name, clue = candidates[0]
            return (packet, str(round_idx), value, idx), clue
        # Strip the quotation marks each auditor decorates topic names with.
        wanted = re.sub(r'[„“”‘’()"]', '',
                        (topic or '')).strip().lower()
        best, score = None, 0.0
        for idx, name, clue in candidates:
            got = name.strip().lower()
            ratio = difflib.SequenceMatcher(None, wanted, got).ratio()
            if wanted and (wanted in got or got in wanted):
                ratio = max(ratio, 0.95)
            if ratio > score:
                best, score = (idx, name, clue), ratio
        if best and score >= 0.45:
            idx, name, clue = best
            return (packet, str(round_idx), value, idx), clue
    return None, None


def coordinates_exist(packet: str, round_idx: str, value: str) -> bool:
    """Whether a (round, value) pair is even possible in this packet.

    Worth checking per auditor rather than assuming: a model that reports
    `round=1 value=90` when round one runs 10-50 is not reading the file, and its
    other findings deserve the same suspicion.
    """
    doc = packet_doc(packet)
    if doc is None:
        return False
    for rnd in doc['rounds']:
        if str(rnd['index']) != str(round_idx):
            continue
        for t in rnd['topics']:
            for clue in t['clues']:
                if norm_value(str(clue.get('value'))) == value:
                    return True
    return False


def load(log_dir: str) -> tuple[dict, dict]:
    """Returns (findings by clue, per-auditor totals)."""
    findings: dict[tuple, list[dict]] = defaultdict(list)
    totals: dict[str, dict[str, int]] = defaultdict(
        lambda: {'runs': 0, 'flagged': 0, 'impossible': 0})

    for path in sorted(glob.glob(os.path.join(log_dir, '*_*.log'))):
        base = os.path.basename(path)[:-4]
        auditor, _, packet = base.partition('_')
        totals[auditor]['runs'] += 1
        with open(path, encoding='utf-8', errors='replace') as fh:
            for line in fh:
                if CHECKED.match(line):
                    continue
                if not FINDING.match(line):
                    continue
                f = parse_fields(line)
                value = norm_value(f.get('value', ''))
                if not coordinates_exist(packet, f.get('round', '?'), value):
                    totals[auditor]['impossible'] += 1
                    totals[auditor]['flagged'] += 1
                    continue
                key, _clue = resolve(packet, f.get('round', '?'),
                                     norm_value(f.get('value', '')),
                                     f.get('topic', ''))
                if key is None:
                    key = (packet, f.get('round', '?'),
                           norm_value(f.get('value', '')), f.get('topic', '?'))
                findings[key].append({
                    'auditor': auditor,
                    'confidence': (f.get('confidence') or '?').lower(),
                    'problem': f.get('problem', ''),
                    'correct': f.get('correct', ''),
                })
                totals[auditor]['flagged'] += 1
    return findings, totals


def clue_at(key: tuple):
    """The clue a canonical key points at, plus its topic name."""
    if len(key) != 4 or not isinstance(key[3], int):
        return None, None
    packet, round_idx, value, topic_idx = key
    doc = packet_doc(packet)
    if doc is None:
        return None, None
    for rnd in doc['rounds']:
        if str(rnd['index']) != str(round_idx):
            continue
        if topic_idx >= len(rnd['topics']):
            return None, None
        topic = rnd['topics'][topic_idx]
        for clue in topic['clues']:
            if norm_value(str(clue.get('value'))) == value:
                return clue, topic['name']
    return None, None


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('log_dir')
    ap.add_argument('--all', action='store_true', help='print single-auditor findings too')
    ap.add_argument('--packet', help='limit to one packet number')
    args = ap.parse_args(argv)

    findings, totals = load(args.log_dir)

    print('auditor coverage')
    for auditor, t in sorted(totals.items()):
        bad = t['impossible']
        note = (f', {bad} pointing at a (round, value) that does not exist'
                if bad else '')
        print(f'  {auditor:6s} {t["runs"]:3d} package(s), '
              f'{t["flagged"]:4d} finding(s){note}')

    keys = list(findings)
    if args.packet:
        keys = [k for k in keys if k[0] == args.packet.zfill(2)]

    agreed = [k for k in keys if len({f['auditor'] for f in findings[k]}) > 1]
    single = [k for k in keys if k not in agreed]

    print(f'\n{len(keys)} distinct clue(s) flagged: '
          f'{len(agreed)} by more than one auditor, {len(single)} by one')

    def show(key: tuple) -> None:
        packet, rnd, value, topic = key
        clue, name = clue_at(key)
        print(f'\n#{packet} R{rnd} | {name or topic} | {value}')
        if clue:
            print(f'  Q: {clue["question"][:200]}')
            print(f'  A: {clue["answer"]}')
        else:
            print('  (clue not found -- topic name may have been quoted loosely)')
        for f in findings[key]:
            print(f'  [{f["auditor"]}/{f["confidence"]}] {f["problem"][:220]}')
            if f['correct']:
                print(f'      -> {f["correct"][:180]}')

    print('\n' + '=' * 72)
    print('FLAGGED BY BOTH AUDITORS')
    print('=' * 72)
    for key in sorted(agreed):
        show(key)

    if args.all:
        print('\n' + '=' * 72)
        print('FLAGGED BY ONE AUDITOR')
        print('=' * 72)
        for key in sorted(single):
            show(key)

    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
