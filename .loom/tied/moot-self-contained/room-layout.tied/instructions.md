# room-layout 🏠

**Intent.** Move the room inside `.moot/` and make room resolution a chain.
This is the structural stitch; the other three depend on it.

## The move

```text
before                              after
  <room>/posts/                       .moot/rooms/<room>/posts/
  <room>/.moot/seen/<name>            .moot/seen/<room>/<name>
  <room>/.moot/moot.sh                .moot/moot.sh
```

`seen/` sits beside `rooms/`, not inside it, because `.moot/rooms/<room>/` is
now the folder that syncs. Putting the cursor under it would hand the room a
second writer and undo [[moot-instance-state]] in one line.

## Room resolution

`resolve_room()` stops being `dirname` and becomes the chain the name chain
already models:

```text
--room   →   $MOOT_ROOM   →   .moot/room   →   the sole room
```

- The sole-room fallback is what keeps the common case flagless: one room, no
  `--room` anywhere, exactly as today.
- `.moot/room` is optional and written only by `init --room <name>`, mirroring
  `.moot/name` precisely — including that nobody is obliged to have one.
- Zero rooms, or several with no pointer and no flag, must die with a message
  that lists what is subscribed and names the fix. That error is the entire UX
  of multi-room, so write it as prose a human can act on, not a usage dump.
- Validate a room name with the filename-safe check `resolve_name` already
  uses. It is a path segment for the same reason a sender is.

`catchup` does not use this chain in the single-room sense — see
[[catchup-sweep]] — but it must use the same validation and the same `--room`
flag spelling.

## The verbs

- **`join <room>`** — create `.moot/rooms/<room>/posts/` with its `.gitkeep`,
  and `.moot/seen/<room>/`. Idempotent, and the only way a room is created. A
  room arriving over rsync into `rooms/` needs no join: it is subscribed by
  being there, and `join` on it is a no-op that creates the missing cursor
  directory.
- **`rooms`** — list subscribed rooms, marking the default. Read-only. Small,
  but without it a `.moot/` holding several rooms has nothing that answers
  "which".
- **`init`** now creates `.moot/rooms/` and `.moot/seen/` only. It no longer
  creates a room, because it no longer knows which one. Keep `--as`, add
  `--room <name>` writing `.moot/room`, keep the `changed` accounting. The
  `"room"` field in `--json` becomes the resolved default or `null`.
- **`install.sh`** copies `moot.sh` and `README.md` into `<dir>/.moot/` and
  runs `init`. Its comment and closing message change meaning: not "makes this
  directory a room" but "makes this directory a moot participant", the same
  sentence that would describe installing `.loom/`. Installing into an empty
  folder no longer produces a usable room — say so, and name `join`.

`post` and `read` gain `--room <name>`. Everything downstream of the resolved
room — `posts_dir`, the `.landing` compose, `link(2)` naming, `post_ids`,
rendering — is unchanged, and that should show in the diff.

## Tie-off

A working directory holds `.moot/` and nothing else of moot's. `join` twice is
a no-op. Two rooms in one `.moot/` each hold their own `posts/` and their own
cursor, and neither is reachable from the other.

Tested including: the sole-room fallback with no flags; two rooms with no
pointer failing usefully; `.moot/room` making it work again; `--room` and
`$MOOT_ROOM` overriding in that order; an unsafe room name dying with the
filename-safe message rather than writing a path; a room dropped into `rooms/`
by copy being usable with no `join`; `install` into a directory that already
has `.loom/` and `.nest/` touching neither.
