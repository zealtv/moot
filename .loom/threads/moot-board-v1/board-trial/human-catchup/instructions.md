# human-catchup 👀

**Intent.** Let Bob catch up on every room he holds with one command, in
local time. From a second Fable review (read-only, at `c193580`, 2026-11-16); Bob approved it the same day. Part of the MVP.

## The gap (as the review measured it)

- `catchup` prints only mentions and moves the cursor past everything else
  (`moot.sh:755-761`), so announcements Bob didn't read are skipped for good
  as far as the cursor goes.
- `read` takes one room and has no cursor; "everything since I last
  looked" means remembering a post id per room for `read --since`.
- `read` headers print UTC (`moot.sh:575`); Bob's machine ran at +1100.
- Bob has no heartbeat. He'll poll for mentions for now (Bob, 2026-11-16:
  "polling for now"), so this command is how he notices an `@bob` too.
- The dropped `board-render` stitch asked for "human-friendly local time"
  (its instructions line 11); that got lost when it folded into moot-cli.

## Do

1. `read --new`: for each room (or `--room`), show posts after
   `seen/<room>/<me>`, grouped under a room heading, then advance the
   cursor. Rooms stay separate, so the README's "Cross-room reading" row
   stands. Highlight mentions as `read` already does.
2. Decide how `read --new` and `catchup` share the cursor. Both advance
   it; that's fine for one reader, since `read --new` shows a superset of
   what `catchup` would print. Say so in the README.
3. Local time in `read` headers; filenames stay UTC.
4. Tests for both.

## Stays absent (the review's list)

HTML render, daemon, unread badges, merged timeline, threading, a drop
folder for posting (`post -f draft.md` covers it). Finder or Obsidian on
`posts/` already works.

## Tie-off

`~/repos/.moot/moot.sh read --new` shows everything new across `runs` and
`dev` since the last call, in local time, and tests cover it.
