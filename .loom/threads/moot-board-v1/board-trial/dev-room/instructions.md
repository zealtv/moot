# dev-room 💬

**Intent.** Use the `dev` room in `~/repos/.moot` as a development chat:
Bob and agent sessions working in different repos announce and ask across
them (a loom release that moot should pick up, a breaking change in a shared
tool, "who is touching ai-kit right now?"). Bob asked for it on 2026-11-16
alongside the orchestrator room. Depends on [[repos-moot]].

This stays inside board-trial on purpose. The goal stitch defers group chat
(flooding, silence, addressing, turn-taking) until a trial supplies
evidence; this room supplies some, so it records findings rather than
building chat features.

## To settle

1. **How a session joins.** Only through a repo's own `.moot/` and the
   skill inside it ([[skill-in-moot]]); Bob ruled out global notes on
   2026-11-16. Observe whether sessions actually check the room at the
   points the skill names.
2. **Names** for ad-hoc sessions: the folder name, per shared-rooms item 5.
   Watch whether two readers in one repo ever collide.
3. **Bob's view.** `read --new` ([[human-catchup]]) plus `read --follow`
   panes; note what he actually used.
4. Delivery to sessions that have a `.nest/in/`: does `--deliver` there help
   or just add a second inbox?

## Tie-off

The room carried real cross-repo development traffic for at least a week,
and the findings sit in `../trial-kit.tied/observations.md` under a "dev
room" heading, ready for trial-run's Lore record.


## MVP split (2026-11-16)

Bob shaped the MVP so that [[skill-in-moot]] drafts the session join (Q1) and naming (Q2) conventions before the room
opens. This stitch starts once [[repos-moot]] ties, and tests those drafts
in real use; revise the skill from what it finds.
Reshaped later on 2026-11-16: each participating repo gets its own `.moot/`
with `runs` and `dev` symlinked from `~/repos/.moot` ([[shared-rooms]]), and
the skill ships inside `.moot/` rather than globally ([[skill-in-moot]]).
Names come from each repo's folder; a run adds `MOOT_NAME=<folder>-<run>`.
