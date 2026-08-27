"""Structural and linguistic gate for new question packages.

Anything that is going to be merged into ``data/pilot.json`` has to pass this
first. The rules are the ones the app and the seeder already assume -- three
playable boards of 6 topics x 5 clues on the right value ladder, one final with
two single-clue topics -- plus the language checks that catch the two failure
modes machine-written Georgian actually has: text that is not Georgian at all,
and text that is Georgian letters spelling another language.

Usage:
    python src/validate_packets.py data/agy_packets/*.json
    python src/validate_packets.py --against data/pilot.json data/new_packet.json

Exit code is 0 only when every file is clean.
"""

from __future__ import annotations

import argparse
import glob
import json
import re
import sys
import unicodedata

# R1 10..50, R2 20..100, R3 30..150 -- the ladders of the 2008 originals.
LADDERS = {
    1: [10, 20, 30, 40, 50],
    2: [20, 40, 60, 80, 100],
    3: [30, 60, 90, 120, 150],
}
TOPICS_PER_BOARD = 6
CLUES_PER_TOPIC = 5
FINAL_TOPICS = 2

GEORGIAN = re.compile(r'[Ⴀ-ჿᲐ-Ჿⴀ-⴯]')
# Mkhedruli letters retired in the 19th century. Present-day Georgian never
# uses them; open MT models emit them when they are really writing another
# language in Georgian script.
ARCHAIC = re.compile(r'[ჱჲჳჴჵჸჶ]')
CYRILLIC = re.compile(r'[Ѐ-ӿ]')
LATIN = re.compile(r'[A-Za-z]')

# A clue that tells the player to look at something is unplayable here: every
# clue in this data set is pure text. Matched in the locative ("in the picture")
# only -- questions *about* paintings are perfectly fine and common.
VISUAL = re.compile(
    r'(სურათზე|ფოტოზე|ილუსტრაციაზე|ეკრანზე|რუკაზე\s+ნაჩვენებ|ვიდეო(ში|ზე)'
    r'|see\s+the\s+(image|picture))',
    re.IGNORECASE,
)


def norm(text: str) -> str:
    """Fold a question down to something comparable across packages."""
    text = unicodedata.normalize('NFKC', text).lower()
    text = re.sub(r'[^\wႠ-ჿᲐ-Ჿ]+', ' ', text)
    return ' '.join(text.split())


class Report:
    def __init__(self, label: str) -> None:
        self.label = label
        self.errors: list[str] = []
        self.warnings: list[str] = []

    def error(self, where: str, message: str) -> None:
        self.errors.append(f'{where}: {message}')

    def warn(self, where: str, message: str) -> None:
        self.warnings.append(f'{where}: {message}')

    @property
    def ok(self) -> bool:
        return not self.errors


def check_text(rep: Report, where: str, field: str, text: object,
               *, prose: bool = True) -> None:
    """Language checks on one string.

    ``prose`` marks the fields that are read aloud -- questions, topic names,
    titles. Those must actually be written in Georgian. Answers are held to a
    looser standard on purpose: a year, a score line, a Latin film title or a
    transliterated name is a perfectly good answer, and the originals are full
    of them.
    """
    if not isinstance(text, str) or not text.strip():
        rep.error(where, f'{field} is empty')
        return

    if text.strip() != text:
        rep.warn(where, f'{field} has surrounding whitespace')

    fail = rep.error if prose else rep.warn

    if ARCHAIC.search(text):
        # The one signal that is never legitimate: these letters left the
        # alphabet in the 19th century, and open MT models emit them when they
        # are really writing another language in Georgian script.
        rep.error(
            where,
            f'{field} uses archaic Georgian letters (ჱჲჳჴჵ) -- the signature of '
            f'machine-translated text: {text[:60]!r}',
        )

    georgian_letters = len(GEORGIAN.findall(text))
    latin_letters = len(LATIN.findall(text))

    if georgian_letters == 0:
        fail(where, f'{field} contains no Georgian letters: {text[:60]!r}')
    elif latin_letters > georgian_letters and latin_letters > 12:
        fail(
            where,
            f'{field} is more Latin than Georgian ({latin_letters} vs '
            f'{georgian_letters}): {text[:60]!r}',
        )

    if CYRILLIC.search(text):
        # Quoting Russian is normal in this archive; it is only a smell in
        # freshly generated text, so it never blocks a merge.
        rep.warn(where, f'{field} contains Cyrillic: {text[:60]!r}')

    if VISUAL.search(text):
        # Only a hint for review: prose *about* a painting reads the same as an
        # instruction to look at one, and the archive is full of the former.
        rep.warn(where, f'{field} may refer to something to look at: {text[:60]!r}')


def check_clue(rep: Report, where: str, clue: dict, expected_value: object) -> None:
    if not isinstance(clue, dict):
        rep.error(where, 'clue is not an object')
        return

    value = clue.get('value')
    if value != expected_value:
        rep.error(where, f'value is {value!r}, expected {expected_value!r}')

    question = clue.get('question')
    answer = clue.get('answer')
    check_text(rep, where, 'question', question)
    check_text(rep, where, 'answer', answer, prose=False)

    if isinstance(question, str):
        length = len(question.strip())
        if length < 4:
            rep.error(where, f'question is too short to be a clue: {question!r}')
        elif length < 25:
            # Legitimate in a "brand -> city" style round, suspicious otherwise.
            rep.warn(where, f'question is very short: {question!r}')
    if isinstance(answer, str) and len(answer.strip()) > 160:
        rep.error(where, 'answer is a paragraph, not an answer')

    if isinstance(question, str) and isinstance(answer, str):
        a = norm(answer)
        if len(a) >= 5 and a in norm(question):
            rep.error(where, f'the answer is spelled out in the question: {answer!r}')


def check_package(pkg: dict, rep: Report, seen: dict[str, str]) -> None:
    for field in ('number', 'title', 'rounds'):
        if field not in pkg:
            rep.error('package', f'missing {field}')
    if rep.errors:
        return

    if not isinstance(pkg['number'], int):
        rep.error('package', 'number must be an int')
    check_text(rep, 'package', 'title', pkg.get('title'))
    if pkg.get('subtitle') is not None:
        check_text(rep, 'package', 'subtitle', pkg.get('subtitle'))

    rounds = pkg['rounds']
    if not isinstance(rounds, list) or len(rounds) != 4:
        rep.error('package', f'expected 4 rounds (3 boards + final), got {len(rounds)}')
        return

    for i, rnd in enumerate(rounds, start=1):
        where = f'round {i}'
        if rnd.get('index') != i:
            rep.error(where, f'index is {rnd.get("index")!r}, expected {i}')

        is_final = i == 4
        if bool(rnd.get('is_final')) != is_final:
            rep.error(where, f'is_final should be {is_final}')
        if bool(rnd.get('playable')) != (not is_final):
            rep.error(where, f'playable should be {not is_final}')

        topics = rnd.get('topics')
        want_topics = FINAL_TOPICS if is_final else TOPICS_PER_BOARD
        if not isinstance(topics, list) or len(topics) != want_topics:
            rep.error(where, f'expected {want_topics} topics, got {len(topics or [])}')
            continue

        names = set()
        for t_idx, topic in enumerate(topics, start=1):
            t_where = f'{where} topic {t_idx}'
            # Topic names are often a foreign title ("lingua latina", "11").
            check_text(rep, t_where, 'name', topic.get('name'), prose=False)
            name = (topic.get('name') or '').strip()
            if len(name) > 40:
                rep.error(t_where, f'name will not fit a board header: {name!r}')
            if name in names:
                rep.error(t_where, f'duplicate topic name in this round: {name!r}')
            names.add(name)

            clues = topic.get('clues')
            want_clues = 1 if is_final else CLUES_PER_TOPIC
            if not isinstance(clues, list) or len(clues) != want_clues:
                rep.error(t_where, f'expected {want_clues} clues, got {len(clues or [])}')
                continue

            for c_idx, clue in enumerate(clues):
                expected = None if is_final else LADDERS[i][c_idx]
                c_where = f'{t_where} clue {c_idx + 1}'
                check_clue(rep, c_where, clue, expected)

                question = clue.get('question') if isinstance(clue, dict) else None
                if isinstance(question, str):
                    key = norm(question)
                    if key in seen:
                        rep.error(c_where, f'duplicate of {seen[key]}')
                    else:
                        seen[key] = f'{rep.label} {c_where}'


def load_existing(path: str, seen: dict[str, str]) -> int:
    with open(path, encoding='utf-8') as fh:
        data = json.load(fh)
    count = 0
    for pkg in data.get('packages', []):
        for rnd in pkg.get('rounds', []):
            for topic in rnd.get('topics', []):
                for clue in topic.get('clues', []):
                    question = clue.get('question')
                    if isinstance(question, str):
                        seen.setdefault(
                            norm(question),
                            f'{path} package {pkg.get("number")}',
                        )
                        count += 1
    return count


def packages_in(data: object) -> list[dict]:
    """Accept a bare package, a list of them, or a {"packages": [...]} file."""
    if isinstance(data, dict) and 'packages' in data:
        return data['packages']
    if isinstance(data, list):
        return data
    return [data]  # type: ignore[list-item]


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('files', nargs='+', help='packet json files (globs allowed)')
    ap.add_argument(
        '--against',
        default='data/pilot.json',
        help='existing set to check for duplicate questions ("" to skip)',
    )
    args = ap.parse_args(argv)

    paths: list[str] = []
    for pattern in args.files:
        expanded = sorted(glob.glob(pattern))
        paths.extend(expanded or [pattern])

    seen: dict[str, str] = {}
    if args.against:
        try:
            n = load_existing(args.against, seen)
            print(f'compared against {n} existing clues in {args.against}')
        except FileNotFoundError:
            print(f'note: {args.against} not found, skipping duplicate check')

    reports: list[Report] = []
    for path in paths:
        try:
            with open(path, encoding='utf-8') as fh:
                data = json.load(fh)
        except (OSError, json.JSONDecodeError) as exc:
            rep = Report(path)
            rep.error('file', f'{exc}')
            reports.append(rep)
            continue

        for pkg in packages_in(data):
            label = f'{path} #{pkg.get("number") if isinstance(pkg, dict) else "?"}'
            rep = Report(label)
            if isinstance(pkg, dict):
                check_package(pkg, rep, seen)
            else:
                rep.error('package', 'not an object')
            reports.append(rep)

    failed = 0
    for rep in reports:
        clues = 'ok'
        if rep.errors:
            failed += 1
            clues = f'{len(rep.errors)} error(s)'
        print(f'\n{rep.label}: {clues}')
        for message in rep.errors:
            print(f'  ERROR   {message}')
        for message in rep.warnings:
            print(f'  warning {message}')

    print(f'\n{len(reports) - failed}/{len(reports)} package(s) clean')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
