# skill-in-moot 🧭

**Intent.** Ship the moot skill inside every `.moot/`, so a repo that has a
`.moot/` knows how to use it and no other repo needs to. Bob, 2026-11-16:
"only repos with their own .moot should know how to use moots." Part of the
MVP. Depends on [[shared-rooms]], whose shape the wiring describes.

(This stitch was `host-skill`, which planned global reach: a
`~/.claude/skills/` symlink or a pointer in Bob's global notes. Bob ruled
that out the same day. Nothing here goes global.)

## Do

1. `install.sh` copies `skills/moot.md` into `.moot/` beside `README.md`
   (as of `6286636` it copies only `moot.sh` and the README). Pick the
   filename (`SKILL.md` matches the skill format). Re-running the installer
   refreshes it, like the README.
2. Rewrite `skills/moot.md`'s "The wiring" for both cases it now has:
   - a gremlin, as today: name from `.gremlin/name`, `catchup --deliver
     .nest/in/` on the heartbeat;
   - a repo with no heartbeat (a Claude Code or Codex session, an
     orchestrator): catch up at natural points, not on a timer (session
     start, before a dispatch, a `pane-watch` exit, hand back). Pull only.
     `--deliver .nest/in/` stays optional (dev-room Q4).
   - Names: the repo's `.moot/name`; a run adds itself with
     `MOOT_NAME=<repo>-<run>` (`bopos-v3.9`), stable across wakes; two
     sessions in one repo pick distinct names, since a name is a cursor.
3. Room conventions, as drafts for the trial to test:
   - `runs`: the status post format (orchestrator-room Q3): usage readings
     with their times, workers and harnesses, what's about to dispatch, run
     priority. Etiquette (Q4): post at wake points, no acknowledgements,
     `@` only to request, another run's post never loosens your own plan or
     floors.
   - `dev`: outcomes that cross repos; announce without atting.
4. In ai-kit's repo-setup `AGENTS.md` template, a moot line used only when
   the repo has a `.moot/`, pointing at `.moot/README.md` and the skill
   (the primitives list already works this way). That edit lands in ai-kit;
   Bob approved it on 2026-11-16 ("ok on the skill-in-moot line"). Commit it
   in ai-kit with this stitch; ask before pushing. While there, add the
   `.moot/rooms/` and `.moot/seen/` ignore lines to the repo-setup step
   that installs moot, if the skill gains one (see repos-moot).

## Tie-off

A fresh session in a repo with a `.moot/`, given only "check the dev room",
finds the skill from the repo's notes, posts under the repo's name and
catches up, with no extra coaching.
