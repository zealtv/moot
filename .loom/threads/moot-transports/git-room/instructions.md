# git-room 🔗

**Intent.** Turn a git URL into a room. Subscribing to a room across the
internet should need nothing but the URL.

## The shape

`rooms/<name>/` is the clone itself. The repository root is the room root, so
the repository contains `posts/` and nothing else moot cares about. This is
what makes the address free: `git remote get-url origin` already answers "where
does this room live", so no `remotes/` file, no address in `.moot/room`, and no
second source of truth to drift.

`join` is unchanged and still makes a local-only room. `subscribe` is its
sibling for a room that already exists somewhere else.

```sh
.moot/moot.sh subscribe [--json] <git-url> [<room>]
```

- Room name defaults to the repository basename with any `.git` suffix removed,
  and goes through `check_segment` like every other path segment this tool
  writes. An explicit second argument overrides it, because a URL is not
  obliged to be named the way the reader wants to type it.
- Clone into `rooms/<name>/`, then `mkdir -p seen/<name>` exactly as `join`
  does. A room is subscribed by being a directory under `rooms/`, so nothing
  else is needed to make it count.
- Refuse a name that already exists rather than cloning over it.
- `--depth 1` by default. A room's history is its files, not its commits.
- Fail with moot's own message shape if `git` is absent — this verb is the one
  place the tool has a hard dependency, and it should say so plainly rather
  than leaking git's stderr.

## Not this

Do not teach `join` a URL argument. `join` creates; `subscribe` acquires. The
error messages stay legible precisely because the two are separate verbs.

Do not write a `.gitignore`. The README's position is that this is
documentation rather than a mechanism, and `seen/` is already outside the sync
unit, so there is nothing to ignore.

## Tie-off

`subscribe <url>` against a local bare repository produces a room that `rooms`
lists, `read` renders, and `catchup` sweeps, with the cursor under
`seen/<room>/` and `.git/` invisible to every reader. Name derivation, the
explicit-name override, the already-exists refusal and the missing-git message
are covered in `test/run.sh`.
