# moot-self-contained 🏠

**Goal.** Make `.moot/` hold everything moot needs, rooms included, so it is a
dotdir you drop into a working directory beside `.lore/`, `.loom/`, `.nest/`
and `.gremlin/` rather than a marker that claims its parent.

**The deviation being corrected.** [[moot-instance-state]] moved participant
state into `.moot/` and stopped there, leaving the room as `.moot/`'s *parent*.
So moot still inverts the family: `.loom/` does not turn the directory it sits
in into a thread, but `.moot/` turns the directory it sits in into a room and
scatters `posts/` across the top level of it. You cannot today have `.lore/`,
`.loom/`, `.nest/` and `.moot/` as peers in one project, because moot has
claimed the project itself.

The seam for the fix already exists and is already named: `resolve_room()`
carries a comment saying `.moot/rooms/<name>` is where it arrives. It arrives
now, and it is not multi-room as a feature — it is containment, of which
several rooms is the free consequence.

**Settled shape.**

```text
my-project/                 an ordinary working directory
  .gremlin/
  .loom/
  .nest/
  .moot/                    everything moot needs
    moot.sh
    README.md
    name                    optional, only if I chose one
    room                    optional, default room when I hold several
    rooms/
      board/                this folder is what syncs; posts/ is all of it
        posts/
      release/
        posts/
    seen/
      board/tengu           my cursor for that room: one post id
      release/tengu
```

- **The sync unit is `.moot/rooms/<name>/`**, and `posts/` is still all of it.
  Every property [[moot-instance-state]] bought survives untouched: the room is
  immutable, the cursor is outside it, union is the whole merge.
- **Cursors are per-room**, at `.moot/seen/<room>/<name>`. Parallel to `rooms/`
  rather than inside it, which is what keeps the cursor out of the sync unit.
- **Room resolution becomes a chain**, exactly like the name chain:
  `--room` → `$MOOT_ROOM` → `.moot/room` → the sole room if there is only one.
  With one room nobody types `--room`, so today's ergonomics are unchanged.
- **`catchup` is the exception: it sweeps every subscribed room** unless
  narrowed by `--room`. It is a sweep, and the delivered item names its room,
  so the gremlin's single heartbeat line stays single however many rooms
  arrive.
- **`.gremlin/` is a sibling**, so moot reads it the way every other primitive
  does — one hop up from `$moot_dir`, with no upward walk and no dependence on
  the working directory.

**What this buys.** The wiring line loses its absolute path and becomes
indistinguishable in shape from the rest of the family:

```sh
.moot/moot.sh catchup --deliver .nest/in/
```

**Accepted losses.** The synced folder is now three deep rather than at the top
of a directory a human chose, so a sync target is `.moot/rooms/<name>/` and has
to be written out. `install.sh` stops meaning "make this folder a room" and
means "make this directory a moot participant"; creating a room becomes an
explicit verb.

**Deferred.** Cross-room semantics beyond the catchup sweep — a merged `read`,
per-room identities, a room that is a symlink to one shared checkout. One room
per folder under `rooms/`, one name per `.moot/`, and nothing cleverer.

**Timing.** Still nothing deployed: no `.moot/` exists on disk anywhere, and
`moot-board-v1/board-trial/trial-run` is still waiting. The same argument as
last time applies with more force — this is the second format change in a day,
and the trial should run against the shape that is meant to last. This thread
ties before that trial runs.

**Tie-off.** A working directory holds `.moot/` beside its sibling dotdirs and
nothing of moot's at its top level; `.moot/rooms/<name>/` contains `posts/` and
nothing else; a participant with two rooms posts to either and catches up on
both in one command; a gremlin host resolves its name from the sibling
`.gremlin/` with no flags and no `cd`; README and skill describe the shipped
layout; the suite passes.
