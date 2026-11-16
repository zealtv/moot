# orchestrator-room 🎛️

**Intent.** Give orchestrators running at the same time on one machine (and
one usage account) a shared moot room for load-balancing, so each sees what
the others are spending and running before it dispatches. Bob asked for the
draft on 2026-11-15 and, the same day, for it to sit under board-trial as part
of the trial ("it overlaps with the trial run and should be linked/
integrated"). Not queued.

## Where this came from (as of 2026-11-15)

- Bob had two orchestrators running at once, bopOS and easyhog, on one Claude
  account, relying on a usage buffer. He was trying them out messaging each
  other through their nests to load-balance, told to sign off with an
  identifier.
- The ai-kit orchestrate skill (`skills/orchestrate/SKILL.md`, usage policy)
  sets each run's floors as if it had the account to itself. Usage floors
  only stop new dispatches, so two runs' in-flight work overshoots together.
- Nests carry one-to-one arrivals; shared status ("bopos: 3 workers, Claude
  5-hour 82% at 14:05Z") wants a room every orchestrator reads, with a cursor
  each.

## What moot already gives (README as of `fb8112a`)

- Sender and UTC time in the filename, so sign-off needs no discipline.
- A cursor per participant, so `catchup` shows only what's new.
- `catchup --deliver .nest/in/` turns an `@name` post into a nest item, so
  the "watch your nest" habit keeps working for direct requests.
- Immutable posts: the room doubles as the record of the experiment.

## Usage readings without tripping rate limits

Bob, 2026-11-15: "with multiple agents checking usage they sometimes trip rate
limiting. we might want a more universal system for that. moot might help."
As of then, ai-kit's `claude-usage` and `codex-usage` had no cache or lock, and
every `pane-watch` polled on its own (`claude-usage` every ~4 min); ai-kit's
`harness-lessons.md` records HTTP 429s from `claude-usage` when polled often
(qtable 2026-10-16, glra-midi 2026-11-13).

Two layers to weigh, likely both:

- **Machine-local, in ai-kit's tools:** one shared cache of the last reading
  with its time (e.g. under `~/.cache/ai-kit/`), served to any caller while
  fresh, with a lock so only one caller fetches at a time. That fixes every
  caller at once, orchestrators or not, and needs no moot. It would be an
  ai-kit stitch.
- **In the room:** whoever fetched posts the reading, so other participants,
  including ones on other machines, read it from the
  room instead of fetching. Readings in posts carry their own time, so a
  reader can judge staleness. Weigh whether a usage post every few minutes
  floods the board; a separate `usage` room may fit better than the `runs`
  room.

## To settle

1. **Sharing one room between two repos on one machine.** The README rules
   out a room symlinked into another participant's checkout. A likely answer:
   a local bare repo (e.g. `~/moots/runs.git`) that each repo's `.moot`
   `subscribe`s to, since `post` commits and pushes and `catchup` pulls with
   no network needed. Check that, and say which transport the room uses.
2. **Names.** One per run that stays stable across wakes and resumed
   sessions, e.g. `<repo>-<run>` (`bopos-v3.9`). Check how that fits the
   name chain (`--as`, `$MOOT_NAME`, `.moot/name`, `.gremlin/name`) when the
   orchestrator isn't a gremlin.
3. **A status post format.** Short, plain Markdown, at least: usage readings
   with their times (Claude and Codex, 5-hour and weekly), workers running and
   on which harness, what's about to dispatch, and the run's priority
   (primary or secondary) from its run plan.
4. **Etiquette.** Post state at natural wake points (a `pane-watch` exit,
   before a dispatch, at hand back), not on a timer. No acknowledgements:
   silence means no objection. `@` only for a request. Another orchestrator's
   post is information to weigh, never permission to loosen one's own run
   plan, gates or floors.
5. **Wiring into orchestrate.** Once it works, a short "concurrent runs" note
   in the ai-kit orchestrate skill and a run-plan field (room, name,
   priority). That edit belongs in ai-kit, not here.

## Part of board-trial

`trial-run` has been waiting on "real coordination that was going to happen
anyway" between two fanta gremlins and a human. Two orchestrators sharing a
budget, with Bob, is that kind of coordination, so this stitch runs as part of
the trial: record the setup and what happens in `../trial-kit.tied/
observations.md` alongside (or ahead of) the gremlin trial.

Note: `../trial-kit.tied/setup.md` (as of `16007e6`) starts with every
participant pointing at one shared `~/rooms/hq`, which the README's current
rule against a shared room directory seems to rule out. Settle which holds
before using the kit as written.

## Tie-off

Two orchestrators in different repos have shared one room through at least
one real run, posting status and requests in the agreed format, and the
findings (what helped, what flooded, what got missed) are written down, in a
Lore record and in ai-kit's `harness-lessons.md`.

## Update, 2026-11-16

- Bob wants the room at `~/repos/.moot` (room `runs`), shared with a `dev`
  room. [[shared-rooms]] takes over question 1 and the `setup.md` conflict;
  [[repos-moot]] stands the room up. This stitch now depends on repos-moot.
- The machine-local usage layer exists: ai-kit's `shared-usage-cache` stitch
  records `claude-usage`/`codex-usage` sharing one cached reading per machine
  (built 2026-11-15). So the room layer only needs readings in status posts,
  for whoever wants them, not as a fetch-avoidance mechanism.


## MVP split (2026-11-16)

Bob shaped the MVP so that [[skill-in-moot]] drafts the names (Q2), status post format (Q3) and etiquette (Q4) before the room
opens. This stitch starts once [[repos-moot]] ties, and tests those drafts
in real use; revise the skill from what it finds.
Reshaped later on 2026-11-16: each participating repo gets its own `.moot/`
with `runs` and `dev` symlinked from `~/repos/.moot` ([[shared-rooms]]), and
the skill ships inside `.moot/` rather than globally ([[skill-in-moot]]).
Names come from each repo's folder; a run signs off in the body (Bob chose this over run suffixes, 2026-11-16).

## Scope after the second review (2026-11-16)

"To settle" 1-4 are now answered elsewhere: sharing by [[shared-rooms]],
names by shared-rooms item 5, the status format and etiquette as drafts in
[[skill-in-moot]]. Item 5 (orchestrate wiring) still lands in ai-kit once
it works. What's left here: use `runs` through at least one real run,
observe, revise the skill from what happened, and write the findings.
