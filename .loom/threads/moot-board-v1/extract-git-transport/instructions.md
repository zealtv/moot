# extract-git-transport 🚚

**Intent.** Weigh moving the git transport (`subscribe`, and the commit,
push, rebase and fetch inside `post` and `catchup`) out of `moot.sh` into
a consumer, so moot keeps "no networking". From a review: Fable, read-only, 2026-11-16, at moot `e02923a`
(finding 5); Bob asked for this stitch the same day. Not queued.

## The case (as the review put it)

- README (as of `e02923a`) says "Moot has no networking and never
  initiates a connection" (~line 335), yet `post` pushes and `subscribe`
  clones; the "Deliberately absent" row calls it "the exception that proves
  it".
- About 180 of 888 lines (`moot.sh:315-469`, hooks near `:527-533` and
  `:829-840`) and about a fifth of the tests.
- It puts a mutable `.git/` inside a room whose bytes are meant to be
  immutable, and a hand-written post in a clone room stayed uncommitted
  after `catchup`, so there the format does need the tool.
- `nestlings/README.md:260`: "Network transport and synchronization are
  outside the local protocol."
- Concurrency: six simultaneous posts into one clone room kept all six files,
  but five warned "could not commit".

## To settle

1. Who uses clone rooms today. Check before removing: `moot-transports` was
   tied for a reason (see its tied record and any lore), and gremlin hosts may
   depend on it.
2. Shape of the replacement: a separate `moot-git` script, or two heartbeat
   lines (`git pull --rebase`, `git add posts && git commit && git push`)
   documented beside `catchup`.
3. Migration for existing clone rooms.

Best opened after board-trial supplies evidence on whether rooms cross
machines at all.

## Tie-off

Either `moot.sh` no longer touches git and the README documents the
replacement, or the reasons to keep it are written here and the README's
contract says so without contradiction.
