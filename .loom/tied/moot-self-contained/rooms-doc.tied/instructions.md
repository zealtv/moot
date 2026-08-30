# rooms-doc 📄

**Intent.** The README is the format spec and ships into every `.moot/`, so the
argument changes, not just the paths. Depends on [[room-layout]],
[[catchup-sweep]] and [[gremlin-sibling]].

## What actually changed

The README currently opens by making the room the folder you chose. It is one
day old and it argues the position this thread overturns, so the prose is the
work.

- **Layout** — the new tree, and the sentence that now carries the family
  argument: a directory may hold `.lore/`, `.loom/`, `.nest/`, `.moot/` as
  peers, and each is self-contained. The existing line about siblings bundling
  script and data stops being an aspiration and becomes the shape of the thing.
- **A room is a folder** — still true, but the folder is now
  `.moot/rooms/<name>/` rather than the participant's project. Restate what
  syncs, and give the concrete `rsync`/`git` target, since it is three deep and
  no longer obvious by looking.
- **Read state** — `.moot/seen/<room>/<name>`. The reasoning is unchanged; the
  path gains a segment.
- **Nothing in the room has two writers** — the property and its argument
  survive intact. Say explicitly that containment did not cost it, because a
  reader who watched the room move will want to know.
- **The tool** — `join` and `rooms` are new verbs; `--room` on `post`, `read`
  and `catchup`; the room resolution chain, written beside the name chain
  because they are the same idea twice.
- **Catchup** — the sweep, and why this verb alone defaults to every room.
- **Gremlins and other agents** — the wiring line is now relative and the
  `~/rooms/<room>/` paths are gone. The claim to make is the one the thread
  exists for: a gremlin interacts with moot exactly as it interacts with its
  other primitives.
- **Deliberately absent** — the `Room subscriptions` row shipped, so it leaves
  the table. Replace it with what is now genuinely absent: cross-room reading,
  per-room identity, and any notion of a room directory that is shared rather
  than copied.
- **`skills/moot.md`** — the wiring, all three `~/rooms/<room>/...` command
  examples, and "the `.moot/` inside your copy is yours", which describes the
  old nesting.

## The git question, settled here

`.moot/` now sits inside directories that are often themselves git repos, which
sharpens a question the old layout let us dodge. State the position rather than
engineering around it: `rooms/` holds immutable posts and is safe to commit —
committing it is a legitimate transport — while `seen/` and `name` are one
participant's state and are not. Say what a host that commits `.moot/` should
expect. No `.gitignore` is written by the tool; this is documentation, and the
`.gitkeep` stays on `posts/` only.

## Tie-off

README and skill describe the shipped layout with no stale paths —
`grep -rn 'rooms/<room>\|~/rooms' README.md skills/moot.md` is empty, and every
command example in both files runs as written. The copy deployed into a fresh
`.moot/` matches the repository root.
