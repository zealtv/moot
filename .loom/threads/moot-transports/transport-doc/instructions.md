# transport-doc 📄

**Intent.** The README is the format spec and ships into every `.moot/`, so a
transport that is real but undocumented does not exist. Depends on
[[git-sync]].

## Transport is not moot's problem — expanded, not retracted

The section keeps its title and its position. What it gains is the case it
currently waves at: two devices on different networks with no route between
them. Everything the section lists today — sshfs, rsync on a heartbeat, a sync
folder — assumes a LAN or an SSH route. Name the two answers that do not.

**Cloud sync by symlink.** `rooms/<name>/` is a symlink whose target lives
inside the Dropbox or Drive tree. Show the direction explicitly, because the
opposite one is the common mistake and silently does nothing:

```
project/.moot/rooms/board  ->  ~/Dropbox/moot/board
```

The real folder is inside the synced tree; the link points inward from
`.moot/`. Most clients do not follow a link pointing out of their own tree.
This needs no code and no verb — say so, and say why: `subscribed_rooms()`
tests `[ -d ]`, `post_ids()` tests `[ -e ]`, and symlinks follow. `seen/` stays
local automatically because the link is per-room.

**Git by clone**, cross-referenced to the tool section for `subscribe`.

## Where each one is sharp

A transport section that lists only the happy path is worse than none. Both of
these are real and both were found by testing rather than by reasoning:

- **Hard links.** `post` composes to a hidden `.landing` file and `ln`s it into
  place to claim the name atomically. A filesystem without hard-link support —
  Google Drive File Stream, rclone mounts, Dropbox online-only directories —
  fails that `ln`, and posting dies with `cannot write`. A real local folder on
  a real filesystem is fine; a virtual mount is the hazard, and it is worth one
  command to test before trusting one.
- **Names arriving before bytes.** rsync and git reveal a file only once it is
  complete. Drive can materialise a filename before its contents are local, so
  a reader can see a post as zero bytes — and advance its cursor past it.
  Dropbox's download-then-rename is generally safe. This is the one place cloud
  sync is genuinely weaker than the alternatives, and a reader choosing a
  transport deserves to know before choosing.

## Rooms and git

The existing section argued that committing `rooms/` is *permitted*. It now has
to describe a room that *is* a repository. Keep the `seen/`-is-not-safe half
intact — it is unchanged and still the thing people get wrong — and add the
clone-as-room shape, the address living in `git remote`, and the one wart: an
`rsync` of a room that is a clone carries `.git/` and therefore the remote URL
with it. Surprising rather than dangerous, but better written down than
discovered.

## Also

`skills/moot.md` gains `subscribe`, since a gremlin told to join a room will be
handed a URL. The deliberately-absent table loses nothing and gains nothing:
cross-room reading and per-room identity are still absent, and neither
transport changes that.

## Tie-off

Both transports are documented with their hazards; every command example in
`README.md` and `skills/moot.md` runs as written; no stale claim that moot has
only local transports survives; and the copy deployed into a fresh `.moot/`
matches the repository root.
