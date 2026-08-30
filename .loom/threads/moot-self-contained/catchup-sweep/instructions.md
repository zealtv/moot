# catchup-sweep 📮

**Intent.** Make `catchup` cover every subscribed room in one pass, so the
gremlin's one heartbeat line stays one line. Depends on [[room-layout]].

## Why this one verb differs

`post` and `read` are aimed: a human says a thing *somewhere*, so resolving to
a single room is right. `catchup` is a sweep — it asks "is there anything for
me", and the answer spans everything subscribed. If it resolved to one room,
every additional room would mean another line on the heartbeat, another cursor
to remember, and a silent failure mode where a room nobody wired up goes unread
forever.

So: no `--room` means all rooms, in lexical order. `--room <name>` narrows to
one. There is no `--all` flag, because all is the default.

## What changes

- Loop the existing single-room body over the resolved room list. One cursor
  read and one cursor write per room, at `.moot/seen/<room>/$me`. A room whose
  cursor cannot be written warns and continues to the next room rather than
  aborting the sweep — the read-only case is a normal way to run, and one
  read-only room must not stop the others.
- **Delivered filenames carry the room**: `moot-<room>-<id>.md`. Two rooms can
  produce the same post id in the same second from the same sender, and the
  filename is the whole duplicate-suppression mechanism. This is the one place
  the format's uniqueness argument does not survive the move unchanged.
- The delivered item's header gains the room, and its `read back` line gains
  `--room <name>`, so a recipient can act on it without knowing the layout.
- `--json` grows a `room` field per delivered id, or reports one object per
  room. Pick one and say why in the README; the caller must be able to tell
  which board a mention came from without parsing a filename.
- Zero subscribed rooms is not an error. It reports nothing and exits clean:
  a host that has installed moot but joined nothing is a normal state, and a
  heartbeat must not spew.

## Tie-off

One `catchup --deliver` call on a `.moot/` with three rooms delivers mentions
from all three, advances three cursors, and delivers nothing twice on re-run.

Tested including: same-second same-sender posts in two rooms both delivered
under distinct names; a read-only room mid-sweep warning without stopping the
rooms after it; `--room` narrowing to one and leaving the other cursors where
they were; zero rooms exiting silently and successfully.
