#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""CLI tool for reviewing and resolving clue error reports.

Allows developers or AI agents to inspect user reports and patch incorrect
questions or answers in the live database and source pilot.json files.

Usage:
    python src/manage_reports.py list
    python src/manage_reports.py list --status ALL
    python src/manage_reports.py show 1
    python src/manage_reports.py fix 1 --answer "ახალი პასუხი" --note "მომხმარებლის რეპორტის მიხედვით"
    python src/manage_reports.py dismiss 1 --note "კითხვაში შეცდომა არ არის"
"""
import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

DEFAULT_API_URL = os.environ.get("JEOPARD_API_URL", "https://jeopard-kvasho.duckdns.org")
ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PILOT_JSON_PATHS = [
    os.path.join(ROOT_DIR, "data", "pilot.json"),
    os.path.join(ROOT_DIR, "backend", "src", "main", "resources", "pilot.json"),
]


def api_request(url, method="GET", body=None):
    headers = {"Accept": "application/json"}
    data = None
    if body is not None:
        headers["Content-Type"] = "application/json; charset=utf-8"
        data = json.dumps(body).encode("utf-8")

    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req) as resp:
            content = resp.read().decode("utf-8")
            return json.loads(content) if content else {}
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8", errors="replace")
        try:
            parsed = json.loads(err_body)
            msg = parsed.get("detail") or parsed.get("message") or err_body
        except Exception:
            msg = err_body
        print(f"Error {e.code}: {msg}", file=sys.stderr)
        sys.exit(1)
    except urllib.error.URLError as e:
        print(f"Network error connecting to {url}: {e.reason}", file=sys.stderr)
        print("Make sure the backend is reachable or specify --api-url.", file=sys.stderr)
        sys.exit(1)


def update_pilot_json_files(clue_id, new_question, new_answer, note):
    """Updates clue in pilot.json files by positional index cid."""
    updated_files = 0
    for file_path in PILOT_JSON_PATHS:
        if not os.path.exists(file_path):
            continue
        try:
            with open(file_path, "r", encoding="utf-8") as f:
                root = json.load(f)

            cid = 0
            found = False
            for pkg in root.get("packages", []):
                for rnd in pkg.get("rounds", []):
                    for topic in rnd.get("topics", []):
                        for clue in topic.get("clues", []):
                            cid += 1
                            if cid == clue_id:
                                if new_question and new_question != clue.get("question"):
                                    if not clue.get("question_original"):
                                        clue["question_original"] = clue.get("question")
                                    clue["question"] = new_question
                                if new_answer and new_answer != clue.get("answer"):
                                    if not clue.get("answer_original"):
                                        clue["answer_original"] = clue.get("answer")
                                    clue["answer"] = new_answer
                                if note:
                                    existing = clue.get("correction_note")
                                    clue["correction_note"] = (
                                        f"{existing}; {note}" if existing else note
                                    )
                                found = True
                                break
                        if found:
                            break
                    if found:
                        break
                if found:
                    break

            if found:
                with open(file_path, "w", encoding="utf-8") as f:
                    json.dump(root, f, ensure_ascii=False, indent=2)
                updated_files += 1
        except Exception as e:
            print(f"Warning: could not update {file_path}: {e}", file=sys.stderr)

    return updated_files


def cmd_list(args):
    api_url = getattr(args, "api_url", DEFAULT_API_URL).rstrip("/")
    url = f"{api_url}/api/reports"
    if args.status and args.status.upper() != "ALL":
        url += f"?status={urllib.parse.quote(args.status.upper())}"

    reports = api_request(url)
    if not reports:
        print(f"No reports found (filter: {args.status or 'ALL'}).")
        return

    print(f"Found {len(reports)} report(s):")
    print("-" * 80)
    for r in reports:
        rid = r.get("id")
        cid = r.get("clueId")
        status = r.get("status")
        topic = r.get("topicName") or "-"
        val = r.get("value")
        val_str = f"{val} ქ" if val else "ფინალი"
        desc = r.get("description", "").replace("\n", " ")
        if len(desc) > 50:
            desc = desc[:47] + "..."
        date = (r.get("reportedAt") or "")[:19].replace("T", " ")
        print(f"#{rid:<3} [{status:<9}] Clue:{cid:<5} ({topic} {val_str}) | {desc}")
    print("-" * 80)


def cmd_show(args):
    api_url = getattr(args, "api_url", DEFAULT_API_URL).rstrip("/")
    url = f"{api_url}/api/reports/{args.id}"
    r = api_request(url)

    print(f"================ Report #{r.get('id')} [{r.get('status')}] ================")
    print(f"Reported At:  {r.get('reportedAt')}")
    print(f"Reporter IP:  {r.get('reporterIp')}")
    print(f"Package:      {r.get('packageTitle')} (№{r.get('packageNumber')})")
    print(f"Round:        {r.get('roundHeader')}")
    print(f"Topic:        {r.get('topicName')} | Value: {r.get('value')}")
    print(f"Clue ID:      {r.get('clueId')}")
    print("\n--- Question ---")
    print(r.get("question"))
    print("\n--- Answer ---")
    print(r.get("answer"))
    print("\n--- User Problem Description ---")
    print(r.get("description"))

    if r.get("resolutionNote"):
        print(f"\n--- Resolution Note [{r.get('resolvedAt')}] ---")
        print(r.get("resolutionNote"))
    print("=" * 60)


def cmd_fix(args):
    if not args.question and not args.answer and not args.note:
        print("Error: provide at least one of --question, --answer, or --note.", file=sys.stderr)
        sys.exit(1)

    api_url = getattr(args, "api_url", DEFAULT_API_URL).rstrip("/")
    url = f"{api_url}/api/reports/{args.id}/resolve"
    body = {
        "updatedQuestion": args.question,
        "updatedAnswer": args.answer,
        "resolutionNote": args.note or "Fixed via manage_reports CLI",
    }
    res = api_request(url, method="POST", body=body)
    clue_id = res.get("clueId")
    print(f"Report #{args.id} resolved successfully for clue #{clue_id}!")
    print(f"New question: {res.get('question')}")
    print(f"New answer:   {res.get('answer')}")
    print(f"Resolution:   {res.get('resolutionNote')}")

    if args.sync_files and clue_id:
        count = update_pilot_json_files(clue_id, args.question, args.answer, args.note)
        print(f"Updated {count} pilot.json file(s) on disk.")


def cmd_dismiss(args):
    api_url = getattr(args, "api_url", DEFAULT_API_URL).rstrip("/")
    url = f"{api_url}/api/reports/{args.id}/dismiss"
    body = {"note": args.note or "Dismissed via manage_reports CLI"}
    res = api_request(url, method="POST", body=body)
    print(f"Report #{args.id} dismissed.")
    print(f"Note: {res.get('resolutionNote')}")


def main():
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--api-url", default=DEFAULT_API_URL, help=f"Backend API URL (default: {DEFAULT_API_URL})")

    parser = argparse.ArgumentParser(description="Manage Jeopard clue reports", parents=[common])
    sub = parser.add_subparsers(dest="command", required=True)

    # list
    p_list = sub.add_parser("list", help="List reports", parents=[common])
    p_list.add_argument("--status", default="PENDING", help="Filter: PENDING, RESOLVED, DISMISSED, or ALL")
    p_list.set_defaults(func=cmd_list)

    # show
    p_show = sub.add_parser("show", help="Show report details", parents=[common])
    p_show.add_argument("id", type=int, help="Report ID")
    p_show.set_defaults(func=cmd_show)

    # fix
    p_fix = sub.add_parser("fix", help="Resolve a report and update clue", parents=[common])
    p_fix.add_argument("id", type=int, help="Report ID")
    p_fix.add_argument("--question", help="Updated question text")
    p_fix.add_argument("--answer", help="Updated answer text")
    p_fix.add_argument("--note", help="Resolution note")
    p_fix.add_argument("--no-sync-files", dest="sync_files", action="store_false", default=True,
                       help="Do not update pilot.json files on disk")
    p_fix.set_defaults(func=cmd_fix)

    # dismiss
    p_dismiss = sub.add_parser("dismiss", help="Dismiss a report without altering clue", parents=[common])
    p_dismiss.add_argument("id", type=int, help="Report ID")
    p_dismiss.add_argument("--note", help="Dismissal reason / note")
    p_dismiss.set_defaults(func=cmd_dismiss)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
