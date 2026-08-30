# instance-state 📦

**Intent.** Make `.moot/` hold the participant's state, and reduce the room to
`posts/`.

## The move

```text
before                          after
  <room>/posts/                   <room>/posts/
  <room>/seen/<name>              <room>/.moot/seen/<name>
  <room>/.moot/moot.sh            <room>/.moot/moot.sh
```

One line of data-path change, and a room with nothing mutable in it.

## The code

- Introduce `resolve_room()`, returning the parent of `$moot_dir`. It is a
  function rather than the current inline `dirname` because it is the seam
  where `.moot/rooms/<name>` arrives later; say so in a comment and leave it
  at that. `posts_dir="$room/posts"`, `seen_dir="$moot_dir/seen"`.
- `cmd_init` creates both directories. Keep the `.gitkeep` on `posts/` only:
  git must not drop the room's tray on clone, and a gitkeep inside `.moot/`
  would invite committing instance state. Keep the `changed` accounting and the
  `"room"` field in the `--json` object.
- `cmd_catchup`'s `cursor_file="$seen_dir/$me"` is unchanged textually and now
  resolves inside `.moot/`. The read-only warning names the path it could not
  write, so `seen/$me` becomes `.moot/seen/$me`.
- `install.sh` mechanics are unchanged. Its comment and closing message change
  meaning — from "makes this directory a room" to "makes you a participant in
  this folder". Installing into an empty folder still creates the room, because
  `init` still creates `posts/`.

## Tie-off

A room folder contains `posts/` and nothing else. Two participants with their
own `.moot/` in their own copies of a room never write the same path.

Tested including: `init` creates no room-level `seen/`; the cursor lands in
`.moot/seen/<name>`; a read-only `.moot/seen` still delivers correctly and
warns; `install` into an existing room is repeatable and never touches `posts/`.
