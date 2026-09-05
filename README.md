# ჯეოპარდი — Jeopard

A networked buzzer game built on the moazrovne.net **"რა? სად? როდის?"** pilot question set:
a **Flutter** client (Android · iOS · web) against a **Java Spring Boot** backend with
**Postgres in Docker**.

The host reads a clue aloud, teams buzz in from their own phones, the host rules on the spoken
answer — and a wrong answer hands the buzzer to the teams that have not tried yet.

> **შეკითხვები: moazrovne.net (რა? სად? როდის? არქივი). უფლებები ეკუთვნის ავტორებს.**
>
> The questions belong to their authors. This credit is shown in the app on the about dialog and
> the end-of-game screen, and it must stay wherever the questions are used.

---

## What is here

```
jeopard/
├─ backend/            Spring Boot 4.1.1 · Java 21 · Maven wrapper
├─ app/                Flutter client (host + team in one binary)
├─ data/               the pilot question set (unchanged)
├─ src/                the Python pipeline that produced it (unchanged)
└─ docker-compose.yml  Postgres 17
```

### The question set

`data/pilot.json` — built by [`src/build_pilot_db.py`](src/build_pilot_db.py) from the scraped and
corrected moazrovne.net archive:

| | |
|---|---|
| 6 packages | authentic 2008 tournament games, original structure preserved |
| 3 boards each | exactly 6 topics × 5 clues |
| Value ladders | R1 `10·20·30·40·50` · R2 `20·40·60·80·100` · R3 `30·60·90·120·150` |
| 1 final each | 2 topics, 1 clue, no value |
| **552 clues** | 540 board + 12 final; 21 carry a `correction_note` recording a 2008-era fix |

All 552 are pure text — nothing depends on an image, so every clue is playable.

### Twenty-four generated packages

`data/agy_packets/packet_07..30.json` — written by Gemini 3.1 Pro through the `agy` CLI, one call
per package, in the same shape as the originals (three boards, one final, 92 clues each). Each has
a theme of its own, from Georgian history and hagiography through astronomy, Roman law and
mathematical paradoxes to a hardest-of-all mixed package; every prompt carried the topic names
already in use, so no two packages repeat a topic and **no clue repeats a question** — across 2,760
clues the duplicate check finds nothing.

They are not the 2008 material and do not pretend to be. Generated packages say so in their
subtitle, carry `source_url: generated:<model>` on the wire (which is how the picker lists them
separately), and the credit line the app shows names both origins.

Three gates stand between a generated package and the app:

- [`src/validate_packets.py`](src/validate_packets.py) — structure (round flags, 6×5 topics, the
  exact value ladder), and the two failure modes machine-written Georgian actually has: text that
  is not Georgian, and Georgian letters spelling another language (archaic Mkhedruli letters
  `ჱჲჳჴჵ` are the giveaway). It also refuses a clue whose answer is spelled out in its own
  question, and any question duplicating one already in the set. Calibrated so the authentic six
  pass it cleanly.
- **A fact-check pass**, in which the model is pointed back at its own output and asked to attack
  it, then repair what it finds. The first four packages were repaired by hand from its report
  ([`src/apply_factcheck_fixes.py`](src/apply_factcheck_fixes.py) records all 34 edits and the
  finding behind each). For the twenty that followed, the model repaired its own files — which is
  only acceptable because of the third gate.
- **An audit of every edit.** [`src/diff_packets.py`](src/diff_packets.py) prints each changed clue
  before and after against a snapshot taken first. That review found 199 of 1,840 clues touched,
  including 47 where the *answer* itself changed — the dangerous kind. Reading all 47: about a
  dozen were real catches (Albany rather than New York City as the state capital; a pacemaker where
  the answer had said "bacteriophages"; Sanskrit *pañjara* meaning cage, not five; My Lai; Lake
  Albert; Lillehammer), and none was a correction *into* an error. Most of the rest was churn
  caused by feeding the validator's advisory warnings into the repair prompt, which cost some
  answers their Latin-script form; [`src/restore_answer_forms.py`](src/restore_answer_forms.py)
  puts those back.

- **An independent audit**, because the fact-check above was the authoring model reviewing its own
  work. Two models that did not write the content were pointed at the same files, read-only, and
  [`src/audit_findings.py`](src/audit_findings.py) collects and cross-references what they reported
  -- including a check that each finding's (round, value) pair exists at all, which turns out to be
  the cheapest way to tell whether a model is reading the file or confabulating.

  The two auditors were worth wildly different amounts. **Claude Opus 4.6** raised 14 findings over
  packages 07-10 and **11 held up**, all of them errors the self-review had missed: van Gogh's left
  ear called the right one, Tariel's killing of the Khwarezmian suitor attributed to Nestan, the
  Bauhaus dated to the 1920s rather than 1919, an emperor penguin laying its egg "directly on the
  ice" in a clue that then has the male hold it on his feet, Sigismund of Luxembourg numbered
  "Sigismund I". **GPT-OSS 120B** raised 33 findings over packages 07-12 and **none** survived: it
  reported that წყალბადი is not hydrogen, that Pharasmanes I and II never existed, and read
  ბოტსვანა as "Bhutan" -- acting on it would have broken correct clues.
  [`src/apply_audit_fixes.py`](src/apply_audit_fixes.py) records the 11 applied edits and the three
  findings rejected, with reasons.

  The audit is **incomplete**: the agy quota ran out after 40 calls, so packages 11-30 have not yet
  been independently audited. At the rate Opus found real errors, expect a few per package still
  waiting.

Merging is a separate step, so `data/pilot.json` stays exactly what the pipeline produced:

```bash
python src/validate_packets.py --against data/pilot.json data/agy_packets/*.json
python src/merge_packets.py          # -> data/packets_all.json + the backend's seed resource
```

That yields **30 packages, 2,760 clues** — 552 from the archive, 2,208 generated. The seeder only
runs on an empty content table, so an already-seeded database ignores the new file until you clear
it:

```powershell
.ackend
eseed.ps1
```

---

## Running it

### 1. Postgres

```bash
docker compose up -d
```

Published on **5433**, not 5432 — this machine already runs a native PostgreSQL 18 service that
owns 5432. (Docker Desktop binds the port anyway without complaining, so the symptom is a
confusing `password authentication failed`.)

### 2. Backend

```powershell
.\backend\run.ps1
```

The script sets `JAVA_HOME` (no JDK is on `PATH` here — they live under `~/.jdks`), frees port 8080
if a previous forked JVM is still holding it, starts Postgres if needed, then runs the app on
<http://localhost:8080>. On first start Flyway creates the schema and the seeder loads all 2,760
clues; it is idempotent, so later starts skip it — which is also why replacing the question set
needs [`.\backend\reseed.ps1`](backend/reseed.ps1) first.

Plain Maven works too:

```bash
cd backend && JAVA_HOME=$HOME/.jdks/ms-21.0.11 ./mvnw spring-boot:run
```

### 3. Client

```bash
cd app && flutter run -d chrome
```

```bash
cd app && flutter run -d emulator-5554 --dart-define=API_BASE=http://10.0.2.2:8080
```

The API base URL is resolved per platform — `localhost` on web, `10.0.2.2` on the Android
emulator. For a physical phone, pass your machine's LAN address:

```bash
flutter run --dart-define=API_BASE=http://192.168.1.42:8080
```

**iOS**: the `ios/` folder is scaffolded and no Dart code is platform-specific, but iOS cannot be
compiled on Windows — it needs macOS with Xcode. It should build as-is on a Mac.

---

## Deploying it

One hostname serves everything: the Flutter build, the REST API and the WebSocket.

```
                    ┌──────────── Caddy (TLS) ─────────────┐
https://<host>      │  /            → the Flutter build    │
                    │  /api/*, /ws  → Spring Boot :8080    │
                    └──────────────────┬───────────────────┘
                                       └── Postgres (same host, not published)
```

That is not tidiness, it is the one arrangement that cannot break the buzzer. **A page served
over https may not open a plain `ws://` socket**, and the client derives the socket URL from the
origin it was served from — so a split deployment loses the buzzer while REST keeps working, which
is the worst way for this app to fail. Same origin also removes CORS from the game entirely, and
puts Postgres a loopback away from the row lock that decides who buzzed first.

```bash
cd deploy
cp .env.example .env          # set JEOPARD_HOST and POSTGRES_PASSWORD
./deploy.sh user@your-server  # builds the client, ships it, starts the stack
```

**With no domain**, set `JEOPARD_HOST` to an [sslip.io](https://sslip.io) name that resolves to the
box's own address — `203-0-113-45.sslip.io` for `203.0.113.45`. Let's Encrypt issues certificates
for those, so HTTPS (and therefore `wss://`) is real without registering anything, and moving to a
domain later is that one line. Setting it to `:80` serves plain HTTP, which is the right answer on a
LAN where there is no public name to certify.

The client build takes no `--dart-define`: on the web it defaults to **the origin it was served
from**, so one bundle runs on localhost, on a LAN address and on the deployed host. Only native
builds need `--dart-define=API_BASE=https://your-host`.

### Testing the deployment shape locally

The client deriving its own base means a static file server on one port with the backend on another
is a shape that no longer exists in production. So mirror production instead:

```bash
cd deploy && docker compose -f local.docker-compose.yml up -d   # http://localhost:5050
```

That fronts the backend you are already running (`.ackendun.ps1`) with the same proxy layout,
one origin, sockets included.

### What exposing it changes

The notes below still hold — there is no auth and the tokens are the only thing protecting a game.
Deploying adds two things that were not needed on a LAN:

- **TLS**, handled by Caddy, and required for `wss://` rather than for privacy alone.
- **A ceiling on game creation.** `POST /api/games` needs no credentials by design (a host just
  opens the app), and each game seeds a whole board, so a public URL is otherwise a way to fill the
  database. [`GameCreationLimitFilter`](backend/src/main/java/ge/jeopard/backend/config/GameCreationLimitFilter.java)
  caps it per client address — `JEOPARD_GAMES_PER_HOUR`, default 30, `0` to disable. Every other
  write already needs a token from a game that had to exist first.

It is still a pilot: anyone with a join code can join a game, and anyone with the host token can run
it. That is fine for a quiz night among people you invited, and not fine as a public service.

---

## How a game runs

One device hosts; everyone else joins with a six-character code (no `I`, `O`, `0` or `1`, so it
survives being read out loud).

### Players and teams are separate

A **team** is the scoring unit. A **player** is one person on one device. Several players can sit on
the same team, each holding their own buzzer — which is the normal case when three friends play as
one team but nobody wants to pass a phone around.

Joining is therefore two steps:

1. enter the game code and **your own name**
2. **join an existing team** (the screen lists each team with its current members) **or start a new
   one**

Consequences land on the team, not the individual: the score, the final-round wager, and the
per-clue lockout are all the team's. So if one member answers wrong, their teammates are locked out
of that clue too — otherwise a four-person team would simply get four guesses. The snapshot still
carries `buzzedPlayerId` alongside `buzzedTeamId`, so the host sees *"გიორგი (მთიები) დააჭირა"* and
knows who to listen to.

```
LOBBY ──> BOARD ──> CLUE_READING ──> BUZZ_OPEN ──> BUZZED ──> RESOLVED ──> BOARD ...
                          ^                            |
                          |         judge(wrong)        |
                          +─────────────────────────────+
                            deduct, lock that team out,
                            reopen for whoever is left
```

- **The buzzer opens on a separate step.** The clue appears with the buzzer still shut while the
  host reads it aloud, so the fastest connection cannot win before anyone has heard the question.
- **Players can see the board.** While the host is choosing, every player device shows the same
  board read-only, so the category and value in play are never a mystery. Once a clue is chosen its
  category and points are shown large on every screen.
- **First buzz wins, decided by the database.** A buzz is one conditional `UPDATE` — it claims the
  game row only while the buzzer is open, nobody holds it, and this team is not locked out — so of
  any number of simultaneous buzzes exactly one updates a row and the rest update none. Nothing
  queues and nothing depends on JVM-local locking, so it survives more than one instance.
  Every other write to a game takes `SELECT … FOR UPDATE` on that row first, including joining:
  a room's teams are numbered by reading the room and then writing to it, and a roomful of people
  scanning the host's code do that within the same second. The lock is per game row, so a busy
  lobby never touches the room next door.
- **A wrong answer is not the end of the clue.** The team loses the value and is locked out of that
  clue; the buzzer reopens for the rest — including any team that has not tried yet. When no one is
  left, the answer is revealed.
- **Answers are not on the wire.** Nothing broadcast to players contains the answer until it is
  revealed. The host fetches it separately with the host token.

### Whole package or single round

Playing a **whole package** runs boards 1→2→3 and then the final, carrying scores across. This
matters: a wager has to be funded by points already won, so a final played in isolation would have
every team staking zero. A **single round** is also selectable for a quick one-board game.

Setup is two steps, because thirty packages are longer than any screen and the options used to sit
under the end of that scroll. Picking a package is now all the first screen does; the options that
follow it — whole package or one round, whether the host plays — open as **their own page** on a
phone, and as a **panel beside the list** on anything wider than 880px, where there is room to show
both at once and picking never scrolls anything.

### Three ways the buzzer opens

Chosen when the game is created, enforced on the server — a buzz is only ever accepted in
`BUZZ_OPEN`, so no client decides for itself that its countdown has finished.

| Mode | What happens |
|---|---|
| `HOST` | the host presses *"ღილაკის გახსნა"* when they have finished reading. The default, and what every game did before |
| `INSTANT` | the clue and the buzzer arrive together — `select-clue` goes straight to `BUZZ_OPEN` |
| `TIMER` | the buzzer opens itself after 5, 10, 15 or a typed number of seconds (1–120) |

The timer is one-shot work booked on a scheduler thread when the clue goes up, and it checks
before it fires: if the host opened the buzzer early, passed, or moved on, it does nothing rather
than opening a buzzer on the wrong clue. The booking lives in the JVM, so a restart mid-clue loses
it — the host's button is still there, which is why it stays on screen in every mode (labelled
*"ახლავე გახსნა"* while a timer runs).

Clients get the remaining milliseconds (`buzzOpensInMs`), not the deadline, so a device with a
wrong clock still counts the same seconds as everyone else. Both consoles show that countdown: the
host reads against it, the players watch the button wake up.

### Two host modes

- **Dedicated host screen** — the host has no score and never buzzes. Fairest.
- **Host plays too** — the host device gets its own team and buzzer. The answer stays hidden on the
  host screen until the clue resolves; tapping *"პასუხის ნახვა"* reveals it but disables the host's
  own buzzer for that clue, which the server enforces.

### The final round

No buzzer, as in the real format: teams stake part of their score (clamped to what they hold), the
host reveals the clue, then rules on each team in turn.

---

## Layout

**Backend** — `ge.jeopard.backend`

| | |
|---|---|
| `content` | packages, rounds, topics, clues; seeded once from `pilot.json` |
| `game` | the state machine, buzz resolution, scoring, snapshots |
| `config` | STOMP broker (`/ws`), CORS for the Flutter web dev server |

Clients get the whole `Snapshot` on every change rather than deltas, so a reconnecting client is
correct as soon as its first frame lands. A monotonic `seq` lets clients drop stale frames.

**Client** — `app/lib`

| | |
|---|---|
| `core/` | API config, REST client, STOMP socket, models, theme, Georgian strings (`L`), the live feed, the resume-after-reload session |
| `host/` | setup, board, clue, judging |
| `team/` | two-step join (name, then team), board watching, the buzz button |
| `widgets/` | board grid, scoreboard, clue panel, shared game chrome |

Noto Sans Georgian is **bundled** (`app/assets/fonts/`, OFL-1.1) rather than fetched at runtime, so
Android, iOS and web render identically and the first launch needs no network.

### A reload does not end the game

The server holds every bit of game state, so a client only has to remember *who it is*: the game id
and the bearer token that says what it may do. That record ([`core/session.dart`](app/lib/core/session.dart))
is written to `localStorage` the moment a game is created or joined, and read back synchronously
before the first frame — so pressing F5 mid-game, or a phone browser discarding the tab, returns to
the same board with the same rights rather than to the role picker.

- The host keeps the host token, which is the whole point: without it a reloaded host could watch
  the game but not run it.
- A player keeps their *player* token, so they rejoin their existing team instead of joining twice
  under the same name.
- The record expires after 12 hours, is dropped when the game finishes, and can be dropped by hand
  from the game screen (`თამაშიდან გასვლა`).
- Off the web, `SessionStore` is a deliberate no-op ([`session_store_stub.dart`](app/lib/core/session_store_stub.dart)):
  a native app is not reloaded out from under itself, and a key-value plugin would drag native code
  into a project that has none — which is what keeps `flutter test` working here.

### Startup and frame cost

Four things were on the critical path and are not any more:

- **The font had no digits.** The bundled Georgian subset covers no digits, Latin letters or even a
  comma — and this app is scores, values and join codes. Missing glyphs make the web engine fetch a
  fallback font from `fonts.gstatic.com` mid-frame, which is a network round trip in the middle of
  first paint and a row of boxes when offline. A Latin/Cyrillic/Greek subset of Roboto
  (Apache-2.0) now ships alongside and is wired up as `fontFamilyFallback`. Every character in all
  920 clues is covered locally; a check for that lives in the history of this change.
- **The white page.** `web/index.html` paints a styled splash immediately and swaps it out on the
  engine's `flutter-first-frame` event, and preloads the asset manifest, font manifest and both
  fonts so those requests are in flight before `main.dart.js` has finished parsing.
- **Whole-screen rebuilds.** A snapshot arrives on every host action and used to `setState` a tree
  holding the board, the scoreboard and the clue panel. [`core/game_feed.dart`](app/lib/core/game_feed.dart)
  turns the feed into a `ChangeNotifier` and `SnapshotBuilder` rebuilds only the subtree whose
  selected value changed — a score change no longer touches the 30-tile grid.
- **A layout pass per tile.** The board sized each value with `FittedBox`; the grid now measures one
  font size for all 30 tiles, which is also why they no longer differ slightly in size.

---

## Tests

```bash
cd backend && JAVA_HOME=$HOME/.jdks/ms-21.0.11 ./mvnw test
```

Fourteen tests over a live HTTP server and the real database, including:

- every wrong-then-next-team transition, scoring and lockout
- **8+ genuinely simultaneous buzzes resolving to exactly one winner**
- board payloads containing no clue text, and answers staying hidden until revealed
- host-token enforcement, and the peek penalty in host-plays mode
- a whole package played through: three boards, carried scores, funded and clamped wagers
- two players sharing a team: either may buzz, and one member's wrong answer locks out the other
- every seeded package having three boards and a final -- which is how two malformed packages from an
  earlier generation attempt were caught

```bash
cd app && flutter test
```

Thirty-nine tests over snapshot parsing, the session record, the resume path and the widgets —
including that a spent tile is not tappable, team devices cannot drive the board, the clue panel
never paints an answer it was told not to show, a shared team reports its member count, a stored
session with no usable token is refused rather than half-restored, and a stored host session reopens
the host console while a finished game does not.

`test/session_store_web_test.dart` covers the real `localStorage` path and is tagged
`@TestOn('browser')`, so it only runs where a browser can be driven:

```bash
cd app && flutter test --platform chrome test/session_store_web_test.dart
```

---

## Notes and limits

- No auth and no TLS: host and team actions are gated by opaque bearer tokens over plain HTTP. Fine
  for a pilot on a trusted network; **not** something to expose to the internet.
- Android debug builds allow cleartext HTTP (for the local backend); release builds do not. iOS
  permits cleartext to local addresses only, via `NSAllowsLocalNetworking`.
- Changing the question set means running `python src/merge_packets.py` (which writes the backend's
  seed resource) and then the reseed script, because the seeder skips a database that already has
  content. Reseeding deletes games as well as content -- a game row points at a round and a clue, so
  content cannot be swapped underneath one.
- The generated packages are AI-written and fact-checked, not archive material. They are labelled as
  such in the picker and in the credit line; a disputed answer there is the generator's fault, not
  the 2008 authors'.
- `flutter test` needs a working MSVC toolchain only if a dependency has native code. Nothing here
  has any -- which is why the resume-after-reload session reaches `localStorage` through
  `package:web` instead of a key-value plugin.
- Docker Desktop must be running before the backend starts.
