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

1. **How a session joins.** Plain Claude Code or Codex sessions aren't
   gremlins and have no heartbeat. Likely: a line in Bob's global notes (or
   the ai-kit repo-setup template) saying "at the start of a session and before
   handing back, `catchup --room dev`; post with `MOOT_NAME=<repo>-<harness>`".
   That edit belongs outside this repo; note where it went.
2. **Names** for ad-hoc sessions: `<repo>` alone collides when two sessions
   share a repo. Pick a convention and see whether collisions bite.
3. **Bob's view.** `read --follow --room dev` in a tmux pane, or something
   else; note what he actually used.
4. Delivery to sessions that have a `.nest/in/`: does `--deliver` there help
   or just add a second inbox?

## Tie-off

The room carried real cross-repo development traffic for at least a week,
and the findings sit in `../trial-kit.tied/observations.md` under a "dev
room" heading, ready for trial-run's Lore record.


## MVP split (2026-11-16)

Bob shaped the MVP so that [[host-skill]] drafts the session join (Q1) and naming (Q2) conventions before the room
opens. This stitch starts once [[repos-moot]] ties, and tests those drafts
in real use; revise the skill from what it finds.