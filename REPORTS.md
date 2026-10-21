# Clue Reporting & Error Resolution Guide

This document describes how player error reporting works in **Jeopard**, and provides clear instructions for AI coding assistants (such as Antigravity, Claude, ChatGPT, etc.) on how to review reports and fix clues.

---

## 1. Overview

Players in any game mode (Practice, Host, or Team Buzzer) can report errors in clues using the **„შეცდომაა?“** button displayed in the clue panel header.

Common report reasons include:
- Typographical or grammatical errors in Georgian text.
- Outdated or incorrect trivia answers (e.g. historical dates, geographical facts).
- Ambiguous clue phrasing where multiple answers could be valid.

Reports are saved to the PostgreSQL database in the `clue_report` table and are protected against spamming and denial-of-service abuse.

---

## 2. Architecture & Components

```
Flutter Client (Web/Mobile)
  └─ CluePanel (header button „შეცდომაა?“)
       └─ ClueReportDialog (dialog with description input & validation)
            └─ POST /api/clues/{clueId}/report
                 │
                 ▼
Spring Boot Backend (Port 8080)
  ├─ ClueReportService (Abuse limits + Duplicate check + Validation)
  ├─ ReportController (/api/clues/{clueId}/report, /api/reports)
  └─ Flyway Migration V13__clue_reports.sql
       │
       ▼
PostgreSQL Database
  └─ Table: clue_report
```

### Anti-Spam Protection Rules
1. **IP Rate Limit:** Maximum 10 reports per hour per IP (configurable via `JEOPARD_REPORTS_PER_HOUR`). Exceeding this returns HTTP 429.
2. **Cooldown Period:** Minimum 10 seconds between reports from the same IP (configurable via `JEOPARD_REPORT_COOLDOWN_SECONDS`). Rapid bot requests return HTTP 429.
3. **Duplicate Report Suppression:** If an IP submits a report for a clue that already has a `PENDING` report from that same IP, the server returns a friendly notice without creating duplicate database rows.
4. **Description Validation:** Minimum 5 characters, maximum 1000 characters. Rejects single-character or blank spam with HTTP 400.

---

## 3. Instructions for AI Assistants (How to Review & Fix)

When the user asks you to check or fix reports (e.g., *"ნახე რა რეპორტებია"*, *"შეამოწმე რეპორტები და გაასწორე"*):

### Step 1: List Pending Reports
Run the CLI tool from the workspace root:
```bash
python src/manage_reports.py list
```
*(By default, this targets the production server `https://jeopard-kvasho.duckdns.org`. To target local backend, pass `--api-url http://localhost:8080`)*

To view all reports including resolved and dismissed ones:
```bash
python src/manage_reports.py list --status ALL
```

### Step 2: Inspect Report Details
Run:
```bash
python src/manage_reports.py show <REPORT_ID>
```
This prints:
- Clue ID, Topic, Value, Round, and Package Title.
- Current question text and answer.
- User's problem description.
- Reporter IP and submission timestamp.

### Step 3: Fact-Check & Research
- Verify whether the user's claim is accurate by checking reputable sources or knowledge bases.
- Ensure correct Georgian orthography and spelling.

### Step 4: Resolve & Apply Fix
If the clue or answer needs updating:
```bash
python src/manage_reports.py fix <REPORT_ID> --question "განახლებული შეკითხვა" --answer "განახლებული პასუხი" --note "შესწორდა მომხმარებლის რეპორტის მიხედვით"
```
**What this does automatically:**
1. Updates the `clue` row in PostgreSQL (keeps original in `question_original` / `answer_original` for auditability).
2. Updates `clue_report` status to `RESOLVED` with the note and timestamp.
3. Invalidates the in-memory board cache for that round.
4. Updates `data/pilot.json` and `backend/src/main/resources/pilot.json` on disk by positional index (`cid == clue_id`), so the fix is permanently preserved even after re-seeding!

### Step 5: Dismiss False Reports
If the clue is already correct and the report is invalid:
```bash
python src/manage_reports.py dismiss <REPORT_ID> --note "შემოწმდა: არსებული პასუხი სწორია"
```

---

## 4. Deploying Updates to Production

If you made code changes or updated `pilot.json` assets and want to redeploy to the live Oracle VM:
```bash
& "C:\Program Files\Git\bin\bash.exe" deploy/oracle/deploy.sh
```
*(or `./deploy/oracle/deploy.sh` in Git Bash / Linux)*

The script builds the Flutter release bundle, copies the backend and web files to `/opt/jeopard` on the server, builds the Docker container, reloads Caddy, and prints the live URL:
**https://jeopard-kvasho.duckdns.org**

---

## 5. Database Schema Reference

Table: `clue_report`
```sql
CREATE TABLE clue_report (
    id              BIGSERIAL PRIMARY KEY,
    clue_id         BIGINT NOT NULL REFERENCES clue (id) ON DELETE CASCADE,
    description     TEXT NOT NULL,
    status          VARCHAR(32) NOT NULL DEFAULT 'PENDING',  -- PENDING | RESOLVED | DISMISSED
    reporter_ip     VARCHAR(64) NOT NULL,
    reported_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    resolution_note TEXT,
    resolved_at     TIMESTAMPTZ
);
```
