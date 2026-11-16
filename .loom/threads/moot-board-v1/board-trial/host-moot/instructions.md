# host-moot 🏠

**Intent.** Settle, document and test one `.moot/` that many named
participants on one machine share, so `~/repos/.moot` can serve every repo
under `~/repos` as one orchestrator room and development chat. Bob asked on
2026-11-16 for "a moot in my repos directory - ie a ~/repos/.moot to use as an
orchestrator room and development chat". Settles orchestrator-room's question 1
and the `trial-kit.tied/setup.md` conflict it flagged.

## The tension (README as of `3fc09a9`)

- "Deliberately absent" rules out a shared room directory ("two writers on one
  directory is exactly what immutability and the outside cursor exist to
  avoid") and per-room identity ("one name per `.moot/`").
- `trial-kit.tied/setup.md` starts with every participant pointing at one
  shared `~/rooms/hq`.
- Mechanically, moot.sh looks like it already supports a shared host moot:
  `post` claims a name with `link(2)`, so two writers in one `posts/` can't
  clobber each other, and cursors live at `seen/<room>/<name>`, so each name
  keeps one writer per path. Callers pick a name with `--as` or `$MOOT_NAME`.
  Verify this rather than trust the reading.

## Proposed answer (Claude, 2026-11-16; for Bob to confirm)

A **host moot**: one `.moot/` in a directory that is no participant's
checkout (here `~/repos`), on one filesystem, holding plain-directory rooms,
written by many names. The README rule stays for what it was protecting
against, a room symlinked into *another participant's* `.moot/`. The local
bare repo + per-repo `subscribe` alternative from orchestrator-room still
works, but adds a clone, a commit and a push per post for no gain on one
machine.

## To do

1. Tests: two names posting in one `.moot/` in the same second get distinct
   ids; their cursors advance independently; `catchup --as a` never moves
   `b`'s cursor.
2. **Name guard.** From `~/repos/.moot` the name chain falls through
   `../.gremlin/name` (absent) to `$USER`, so an agent that forgets
   `$MOOT_NAME` posts as `bob` and reads with Bob's cursor. Decide a guard,
   e.g. a `.moot/shared` marker (written by `init --shared`) under which
   `post` and `catchup` refuse without `--as`/`$MOOT_NAME`, or warn. Keep it
   one file and one check.
3. Clone rooms in a host moot: many names committing in one working tree can
   race on `index.lock`. Check what `post` does then (it should warn and keep
   the post), and say in the README that host-moot rooms start as plain
   directories; cross-machine comes later via a clone or sync-folder symlink.
4. README: a short "A host moot" section, and amend the two "Deliberately
   absent" rows so they no longer read as forbidding it. Fix `setup.md` to
   match (its path and the `seen/` rsync advice, which predates
   `seen/` living beside `rooms/`).

## Tie-off

Tests pass, the README and setup.md agree on one rule, and the name guard
behaves as decided.
