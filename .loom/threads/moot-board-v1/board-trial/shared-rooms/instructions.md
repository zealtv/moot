# shared-rooms 🔗

**Intent.** Let several participants' `.moot/` directories on one machine
share a room by symlink, so repos under `~/repos` that each have their own
`.moot/` can meet in rooms held in `~/repos/.moot`. Bob, 2026-11-16: "only
repos with their own .moot should know how to use moots", then, choosing
this shape over one shared `.moot/`: "this is more in the nestlings spirit."

(This stitch was `host-moot`, which planned one `.moot/` written by many
names. Bob reshaped it the same day. The earlier plan needed a name guard,
because a shared `.moot/` with no `.gremlin/` beside it falls through to
`$USER`; with a `.moot/` per repo, each repo's own `.moot/name` names it, so
no guard is planned.)

## Shape

```
~/repos/.moot/                    Bob's own participant; holds the real rooms
  name                            bob
  rooms/runs/posts/
  rooms/dev/posts/
~/repos/bopOS/.moot/
  name                            bopos
  rooms/runs -> ~/repos/.moot/rooms/runs
  rooms/dev  -> ~/repos/.moot/rooms/dev
  seen/runs/bopos                 bopOS's cursor, in bopOS
```

Each `posts/` file is claimed atomically by `link(2)` (`moot.sh:514` as of
`e02923a`), and each cursor lives in its own repo's `seen/`, so no path has
two writers. A symlinked room already counts as a room: `subscribed_rooms()`
and `post_ids()` follow links (README, "A room that is a symlink").

## To do

1. **Restate the invariant** in the README as the code enforces it: no
   *path* has two writers. Then amend the "A shared room directory" row in
   "Deliberately absent", which today forbids exactly this shape ("never a
   symlink into someone else's checkout"). A symlink across `.moot/`s on
   one filesystem is fine; two writers on one *cursor* or a mutable room
   file is what stays ruled out. (Review finding 1, Fable, 2026-11-16.)
2. **Tests**: two `.moot/`s sharing a room by symlink; same-second posts from
   both get distinct ids; each cursor advances independently; `catchup`
   in one never touches the other's `seen/`.
3. **Joining a shared room.** Decide between documenting the plain
   `ln -s <room-path> .moot/rooms/<name>` and a `join <room> --at <path>`
   that makes the link and the cursor directory. Lean to the plain link
   (zero code) unless the test shows `join` is needed for the cursor dir.
4. **Rooms that are clones stay out** of a shared room: many repos
   committing in one working tree race on `index.lock` (the review measured
   five "could not commit" warnings from six concurrent posts). Say so; the
   real rooms in `~/repos/.moot` start as plain directories.
5. **Names.** `install.sh --as <name>` writes `.moot/name` at install, so
   a repo's name never falls through to `$USER`. Two sessions in one repo
   would share a name and a cursor; a run sets `MOOT_NAME=<repo>-<run>`
   (`bopos-v3.9`). Convention only, carried by [[skill-in-moot]].
6. **Fix `trial-kit.tied/setup.md`** to match: per-gremlin `.moot/`, rooms
   shared by symlink (or rsync/git across machines). Its claim that a
   gremlin's name "comes from the `.gremlin/name` it already has" (lines
   56-58) holds only when `.moot/` sits beside `.gremlin/` (`moot.sh:92`),
   which this shape makes true. Lines 15 and 32-33 predate the current
   layout.

## Tie-off

Tests pass, the README states the one-writer-per-path rule and the
shared-by-symlink shape without contradiction, and setup.md agrees.
