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
3. **Joining a shared room: a plain `ln -s <room-path> .moot/rooms/<name>`.**
   Settled 2026-11-16: the second review's trial showed `rooms` lists a
   linked room and `catchup` creates `seen/<room>/` itself (`moot.sh:760`),
   so no `join --at` is needed. Document the link.
4. **Rooms that are clones stay out** of a shared room: many repos
   committing in one working tree race on `index.lock` (the review measured
   five "could not commit" warnings from six concurrent posts). Say so; the
   real rooms in `~/repos/.moot` start as plain directories.
5. **Names: a `.moot/` is named after the folder it sits in.** Bob chose
   this on 2026-11-16 ("simple is good - let's go with that"). Replace the
   chain's last step, `$USER`, with the basename of `.moot/..`, read from the
   script's own location like `gremlin_name()` (`moot.sh:92`). The chain
   becomes `--as`, `$MOOT_NAME`, `.moot/name`, `.gremlin/name`, folder name.
   - No name file in repos: a fresh clone anywhere resolves to `bopOS`.
     `.moot/name` stays an uncommitted, machine-local override (Bob's
     `~/repos/.moot/name` holds `bob`, since the folder is `repos`).
   - Names keep the folder's case, and mentions match exactly: `@bopOS`.
   - A folder name that fails `check_segment` (spaces, e.g. `Pedal Board
     Utilities`) dies with the existing message; the fix is `.moot/name`.
   - A human's `~/.moot` falls back to the home folder name, usually
     `$USER`, so little changes for them. Check the tests that rely on
     `$USER` and update the README's name-resolution paragraph.
   - **Open, for Bob: run names.** The plan said a run sets
     `MOOT_NAME=<folder>-<run>` (`bopOS-v3.9`) so two readers in one repo
     don't share a cursor. The second review measured the cost: `@bopOS`
     reached a reader named `bopOS-v3.9` as `delivered:0`, and each new run
     name starts with an empty cursor, replaying old `@all`s. Options:
     (a) `@<folder>` also matches `<folder>-*`, with a test; (b) runs keep
     the plain folder name, so a new run inherits the repo's cursor, and
     sign the run in the body ("— bopOS v3.9"). Bob leaned to (a) on
     2026-11-16, then asked why run names are needed at all. Claude
     recommended (b) the same day: as far as the loom shows, only one agent
     per repo reads the moot at a time, and two concurrent readers in one
     repo would be trial evidence to act on later.
     **Decided: (b).** Bob, 2026-11-16: "option b for now. sub agents can
     add a sign off. gremlins already use sign off conventions and that's
     been working well." No `MOOT_NAME` run suffixes and no prefix
     matching; a run or sub-agent posts as the folder name and signs off in
     the body. Revisit only if the trial shows two readers in one repo
     colliding on the cursor.
   - Hostnames (`bopOS.spectre`; `@` isn't filename-safe) matter only when
     a room crosses machines and two clones of one repo could write the same
     path. Then each machine sets its own uncommitted `.moot/name`. Out of
     the MVP; belongs with [[extract-git-transport]] or whatever carries
     rooms between machines.
6. **Fix `trial-kit.tied/setup.md`** to match: per-gremlin `.moot/`, rooms
   shared by symlink (or rsync/git across machines). Its claim that a
   gremlin's name "comes from the `.gremlin/name` it already has" (lines
   56-58) holds only when `.moot/` sits beside `.gremlin/` (`moot.sh:92`),
   which this shape makes true. Lines 15 and 32-33 predate the current
   layout.

7. **More README text the plan contradicts** (second review): "synced by
   accident" (~line 171), the containment passage (~249-261) and the
   "Deliberately absent" shared-room row (~535). Rewrite them with item 1.

## Tie-off

Tests pass, the README states the one-writer-per-path rule and the
shared-by-symlink shape without contradiction, and setup.md agrees.
