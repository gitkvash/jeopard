# Task: sharpen the clues of one existing package of "ჯეოპარდი"

Working directory: C:/Users/giorg/Desktop/jeopard -- every path is relative to it.

You are given ONE existing AI-written package, `data/agy_packets/packet_NN.json`
(NN is given in the request). Its structure is fixed: 3 boards of 6 topics x 5
clues, plus a final of 2 single-clue topics (92 clues). Your job is to find the
clues that read like generic AI filler and replace them with real, specific
trivia. **Do not modify the original file.** Write your result to
`data/agy_rewrite/packet_NN.json` (same schema, all 92 clues present, the
untouched ones copied verbatim) and a change log to
`data/agy_rewrite/packet_NN_changes.json`.

## What the owner wants

"Very trivia questions, or very specific ones that are hard to change."
In practice: a clue whose answer is ONE unambiguous, verifiable fact that will
still be true in twenty years and that two encyclopedias would agree on.

### A clue is WEAK (rewrite it) when any of these holds

1. **Definition clue.** "This term is used for a X that does Y" -- the player
   is guessing a dictionary word from a description (ნახევარკუნძული, ოაზისი,
   სრუტე). Nothing specific is being asked.
2. **Answerable from the topic name alone**, or several answers fit equally
   well.
3. **Time-sensitive.** Records, rankings, "largest/tallest/fastest/most",
   "current", "the latest", population or price figures, anything that a new
   record, election or census can overturn. (Tallest buildings, biggest
   airports, best-selling models, world records, richest people.)
4. **Vague or hedged wording** -- "often", "usually", "one of the", "famous",
   "important", an answer with "(or ...)" alternatives, an answer that is a
   common noun rather than a name/date/number/title.
5. **Difficulty does not match the value.** A 100-150 point clue that any
   schoolchild answers, or a 10-20 point clue nobody could.
6. **American-civics / US-domestic content** (state capitals, NFL, etc.) --
   this game is general/international knowledge.

### A clue is STRONG (keep it byte-for-byte) when

It pins a single answer with at least one concrete anchor -- a year, a full
name, a number, a place, a first/only/last event -- and the fact is stable.

### What a good replacement looks like

Prefer the shape "concrete anchor + one missing specific":

- Who/what/where/when with a year or named event in the clue:
  "In 1889 this engineer's tower opened for the World's Fair in Paris" style,
  but in Georgian and on a less obvious fact.
- A date, count or name that is fixed by history: treaty years, discoveries
  and discoverers, first ascents, first flights, awards and their years,
  atomic numbers, chemical symbols, Latin names, authors of specific titled
  works, original titles, composers of specific pieces, founding dates,
  where a named battle or treaty took place.
- Specific and surprising beats famous and vague. A 30-point clue may be
  "well-read adult", a 150-point clue should be something only a real trivia
  player would know -- but always a fact, never an opinion.
- Answers should be short and canonical (a name, a number, a title, a place).
  One accepted form; no "(or ...)" alternatives. Numbers may be written in
  words where the original file does that for spoken reading.

## Hard rules (a violation makes the clue unusable)

- **Truth first.** Every fact you write must be one you are certain of.
  If you are not sure, pick another fact. Do not guess dates or numbers.
  For each rewritten clue record the fact in English in `fact_basis` so a
  second model can check it atomically.
- Fluent modern Georgian (Mkhedruli). Never use the archaic letters
  ჱ ჲ ჳ ჴ ჵ ჸ ჶ. Question is Georgian prose; the answer may be a Latin-script
  title/species where natural.
- Read aloud, played by ear: no reference to a picture, map or video.
- Never spell the answer, or an obvious stem of it, inside the question.
- Do not change `value`, the order of clues, or the number of clues/topics.
- A topic name may only change when its clues are being rewritten away from
  US-domestic content; then the new name must not appear in
  `data/used_topics.txt`, must be <= 40 characters and must not repeat within
  its round. Otherwise keep every topic name exactly.
- Within the packet: no answer may appear twice, no clue may give away or
  duplicate another clue.
- Stay on the topic each clue sits in.
- Keep Georgian-culture clues to facts you are sure of (authors, years,
  regions, documented dishes); do not invent folklore.
- Rewrite only what is weak. It is expected that a fair share of the 92 clues
  is already fine and stays untouched -- do not rewrite for the sake of it.
  "Nothing to change" for a clue is a perfectly good outcome. A first pilot
  rewrote 51% of a packet and that was too aggressive: it turned fair 10-point
  clues into hard ones and padded several with trivia that is cute but not the
  point. Aim for roughly 25-40% of the clues; below 20% you are being lazy,
  above 50% you are rewriting strong clues.
- **The difficulty ladder survives the rewrite.** A 10/20-point replacement must
  still be answerable by a well-read adult; do not make it harder than the
  clue it replaces unless the original was wrong for its value.
- Do not claim "first European to...", "the only...", "the oldest..." unless that
  is firmly documented; superlatives are exactly the facts that turn out to be
  contested. Prefer a dated event, a named treaty/battle/expedition, an exact
  count or a named author/title.
- Add `"confidence": "certain"` to every change-log entry. If you cannot honestly
  write "certain" for a fact, do not use it.

## Change log schema

`data/agy_rewrite/packet_NN_changes.json` is a JSON list, one object per
rewritten clue, with machine-checkable coordinates (1-based `round`, 0-based
`topic` and `clue` indexes into the packet's arrays):

```json
{"round": 2, "topic": 3, "clue": 4, "value": 100,
 "weakness": "time-sensitive | definition | vague | too-easy | too-hard | us-centric | multiple-answers",
 "old_question": "...", "old_answer": "...",
 "new_question": "...", "new_answer": "...",
 "fact_basis": "the fact in English, with the year/number/name it depends on"}
```

The `old_*` fields must be copied exactly from the original file and the `new_*`
fields must be exactly what you wrote into the rewritten packet.

## Output discipline

Do not edit anything except the two files under `data/agy_rewrite/`. Do not
write a plan artifact and do not ask for approval -- just write the two files
and finish with a one-line reply saying how many clues you changed.
