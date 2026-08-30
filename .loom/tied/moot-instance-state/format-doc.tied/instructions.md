# format-doc 📄

**Intent.** The README is the format spec and it ships into every room, so the
argument has to change, not just the paths. Depends on [[instance-state]] and
[[identity]].

## What actually changed

The README currently makes a virtue of the thing being overturned: *"A
participant holds **no moot state at all** — no dotdir, no cursor file, no
pointer."* That sentence and the reasoning around it are the work.

- **Layout** — the new tree.
- **Read state, and catching up** — currently organised around "state lives in
  the room". Invert it: the room is one immutable tray, the participant holds
  the cursor. The reader-initiated-pull constraint and "delivered is not the
  same as seen" survive untouched — what changed is where the cursor sits, not
  who initiates.
- **One writer per path** — keep the property, restate its basis. It is now the
  trivial consequence of a local cursor rather than a claim needing defence.
  The `cp -r`'d-twin edge stays; the git-conflict-on-`seen/<name>` edge is gone.
- **No membership registry** — currently argues the registry is unnecessary
  *and* that `seen/` supplies one for free. Delete the second half. The
  registry is now genuinely absent, which is simpler to state than to argue.
- **The tool** — install semantics; "it operates on the `.moot/` it lives in"
  becomes true in the family's sense.
- **Deliberately absent** — a row for participant-side room subscriptions,
  naming `.moot/rooms/<name>` as deferred rather than rejected.
- **Gremlins and other agents** — the wiring line is unchanged, but the claim
  around it ("nothing to install into it: the room's path is the pointer") is
  now false in one respect: a participant does install a `.moot/` into their
  copy of the room. Say what is true instead.
- **`skills/moot.md`** — the "no state of your own" framing, and "never write
  anything into a moot except a post and your own `seen/<name>` cursor".

## Tie-off

README and skill describe the shipped layout with no stale `seen/` references —
`grep -rn 'seen/' README.md skills/moot.md` shows only `.moot/seen/`. The copy
deployed into a fresh room matches the repository root.
