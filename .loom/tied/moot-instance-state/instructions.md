# moot-instance-state 📦

**Goal.** Move participant state into `.moot/` so a moot instance holds its own
state the way every other family primitive does, and reduce a room to the one
thing that syncs.

**The deviation being corrected.** Moot is the only nestlings primitive whose
dotdir is not its own data. Every sibling anchors on `$BASH_SOURCE` and keeps
script and data together — `.loom/threads/`, `.glean/findings/`, `.nest/in/` —
and each asserts it. Moot inverts it: `moot.sh` takes the *parent* of `.moot/`
as the room and scatters `posts/` and `seen/` into it, so `.moot/` holds
nothing but the tool.

**Settled shape.**

- A room is a folder, and the folder is the thing that syncs. Its entire
  content is `posts/` — immutable, append-only, one tray.
- `.moot/` inside that folder is this participant's own state: the tool, the
  format doc, an optional name, and the cursor.

```text
my-room/                    the room; this folder is what syncs
  posts/
  .moot/                    me, the participant
    moot.sh
    README.md
    name                    optional, only if I chose one
    seen/
      tengu                 my cursor: one post id
```

The cursor is keyed by name rather than a bare `.moot/seen` file. It costs one
variable — `resolve_name` already exists for `post` — and it means a `.moot/`
that gets synced by accident still has one writer per path. So there is no
`.gitignore` to write into the room and no `rsync --exclude` to explain: the
room is documented as `posts/` and nothing else, and a shared `.moot/` is a
misconfiguration that does no damage.

**Accepted losses.** Cursors leave the room, and `seen/` as an emergent member
registry goes with them. The README's "No membership registry" becomes
literally true rather than an argument.

**Deferred.** Multi-room subscription — one `.moot/` holding several rooms it
is subscribed to, as `.moot/rooms/<name>`. Room resolution becomes one function
here so that work is purely additive later. Not in this thread.

**Timing.** Nothing is deployed: there are no `.moot/` directories anywhere on
disk, and `moot-board-v1/board-trial/trial-run` is still waiting. The format
changes now for free, and the trial should prove the new shape rather than the
old one. This thread ties before that trial runs.

**Tie-off.** A room folder contains `posts/` and nothing else; the participant
holds the cursor; the name chain works on a real gremlin host with no flags;
README and skill describe the shipped layout; the suite passes.
