# Working notes for agents

moot is a file-based message board: a directory of immutable, sortably named
Markdown posts that people, gremlins and other agents post to and read. Its
living design is `README.md`; `moot.sh` is the tool, `skills/moot.md` the
etiquette, and `./test/run.sh` the test suite.

`CLAUDE.md` is a symlink to this file, so every agent runtime reads the same notes.

## The primitives

This repository's shape is held by the dotdirs at its root. Each is a
self-contained, file-based protocol bundling its own script and data: the
script operates on the directory it lives in, and the file system is the
protocol. Each ships its own `README.md` with the full contract. Read it
before doing anything non-trivial with that primitive.

- 🪺 nestlings — `.nest/` — arrivals: what just came in, waiting to be tended.
- 🔮 glean — `.glean/` — memory: small, current, revisable guidance.
- 🪡 loom — `.loom/` — finite work: goals, stitches, dependencies, queue order.
- 🐉 lore — `.lore/` — the library: complete, dated records, kept whole.
- 🦫 groundhog — `.groundhog/` — what comes around at a set time: recurring and one-shot items. Use it, not a runtime's own cron, for scheduled wake-ups.

In short: the nest holds what just arrived, glean what is true *now*, the loom
what is still to be done, lore what happened, and groundhog what comes next.

### Start here

1. Read `.glean/findings/INDEX.md`, the always-loaded memory surface:
   one line per finding. Open a body only when it is relevant
   (`./.glean/glean.sh fetch <terms>`).
2. Run `./.loom/loom.sh status`. The loom alone owns open work, blockers and
   queue order. Existing stitches don't widen the user's current request.
3. Read `.nest/tend.md` and inspect `.nest/in/` for arrivals waiting to be
   tended. `inbox/` is a symlink to `.nest/in/`.
4. Consult `.lore/INDEX.md` only when complete evidence or history is needed.
   Lore is dark by default.

## Memory lives in Glean

Glean is this repository's only memory. Don't keep project knowledge in a
runtime's private memory store (for example Claude Code's per-project
`~/.claude/projects/.../memory/`), a `memory/` directory or a handoff note.
Those drift from the repository and travel with one tool on one machine. (The
state of a run in progress is different: a resume prompt or a "where I
stopped" note belongs with the work, in the stitch's directory or a groundhog
payload.) When you learn something worth carrying into the next session, it
becomes a finding: search first and revise an existing finding rather than
adding a near-duplicate, run `./.glean/glean.sh index`, and commit it with the
work that earned it. Claude Code's auto memory is switched off here in
`.claude/settings.json` (`autoMemoryEnabled: false`).

A finding is one file, `.glean/findings/<id>.md`:

- **Title**: the first `# ` line, phrased as the guidance itself ("Keep the
  parser allocation-free"), not a topic label.
- **Description**: the first non-empty line after it, one sentence, written
  the way the finding would come up ("When adding a column type…"). It is the
  recall cue in `INDEX.md`.
- Optional `## Why` (who said or saw what, and when), `## Triggers` (literals
  paraphrase would lose: identifiers, error strings), `## Associations`
  (`[[other-id]]`) and `## Context`.

Say where a claim came from and when: a finding records what someone observed
or decided at one time (`glean:the-repo-is-a-map-not-the-territory`).

## Ownership

One arrival may earn several routes: the source kept in lore, a constraint
distilled into glean, a design change in `docs/`, a stitch on the loom. Those
are different consequences of one thing, not competing copies of it. Name the
results in a nest receipt as `lore:<id>`, `glean:<id>`, `loom:<id>` or
`path:<repo-relative-path>`.

## Publishing

Shape: **split**, chosen by Bob on 2026-11-16 (see
`~/repos/ai-kit/skills/repo-setup/reference/public-release.md`). Development
and the dotdirs live in the private `moot-dev` (Bob named it, 2026-11-16);
releases go to a public `moot`. As of 2026-11-16 the split hasn't happened:
this checkout's `origin` is still the private `zealtv/moot`, and
`loom:public-split` holds the open questions and the release mechanics.
Public files (`README.md`, `moot.sh`, `install.sh`, `skills/`, `test/`)
don't cite `lore:`/`loom:`/`glean:` ids or private paths.

Ask Bob before any push, tag, release or visibility change. When he asks to
commit and push, push straight to `main` (`glean:commit-to-main-directly`).

## Orchestrated runs

Runs that delegate stitches to worker agents follow the `orchestrate` skill
(`~/repos/ai-kit/skills/orchestrate/SKILL.md`). Where this repo needs
something different, a finding here says so, and it wins.

## Upgrading the primitives

They were installed from Bob's local checkouts (`~/repos/glean`, `loom`,
`lore`, `nestlings`) with each one's `install.sh <host-dir>`; groundhog is
vendored from `~/repos/groundhog`. Re-running an installer repairs the script
and README and never touches stored contents, `tend.md` or `distil.md`.
