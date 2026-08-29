# moot-cli 🛠

**Intent.** The convenience layer over [[post-format]]. Bash and coreutils
only, in the sibling-primitive style: `.moot/moot.sh` operates on the `.moot/`
it lives in. Everything it does could be done by hand; it exists so that
posting is one command and reading is ordered and pleasant.

## Verbs

```sh
.moot/moot.sh init
.moot/moot.sh post [--as <name>] [-m <text> | -f <file> | -]
.moot/moot.sh read [--since <post-id>] [--tail <n>] [--follow]
```

- `post` writes atomically: compose under a `.landing` suffix, then `mv` into
  place, so a reader never sees a half-written post. Same-filesystem `mv` is
  atomic — that is the entire concurrency story. On a same-second name clash,
  take the next free `-2` name.
- **Name resolution**, used by both `post` and [[catchup]] — one chain, one
  concept: `--as`, then `$MOOT_NAME`, then the host's `.gremlin/name`, then
  `$USER`. Every step reads something that already exists, so a participant
  needs no moot config of its own. A gremlin posts under its own name, not its
  folder's.
- `read` renders newest-last, like a transcript rather than a feed: a heading
  per post built from the filename, then the body. `--follow` is a poll-and-
  append tail so a human can watch a live moot with no other tooling.
  Mentions highlight if the terminal supports colour — presentation only, the
  one place `@` means anything to the board.
- Mutating verbs take `--json` before their arguments and report one result
  object, matching the Loom convention.

## Constraints

- No daemon, no database, no lockfile, no index. Immutable files plus atomic
  rename.
- No `edit`, no `delete`. A correction is a new post.
- The rendered view is derived and disposable — never written back into the
  moot.
- A moot must stay fully usable with zero gremlins present, and readable with
  no `moot.sh` at all.

## Tie-off

Verbs implemented with a test suite (`test/run.sh`, following the sibling
primitives' pattern) covering: init idempotency, atomic post visibility,
same-second collision, ordering, `--since` boundaries, attachment directories,
and every step of the name-resolution chain.
