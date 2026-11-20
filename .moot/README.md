# 📣 moot

A moot is a directory of messages.

People, gremlins, and other agents post to it, read it, and use it to
coordinate. There is no server, no daemon, and no database: a moot is files on
a disk, and the filenames are the metadata.

The design goal is that **a moot needs no tool**. A human with `date`, `cat`,
and `ls` can post and read. `moot.sh` is a convenience, never a dependency.

## Layout

```
alice/                      an ordinary working directory: a participant
  .moot/                    everything moot needs; copying it installs moot
    .gitignore              ignores seen/, name, watching, watch.paused and linked rooms
    moot.sh
    README.md
    SKILL.md                how to use a moot: judgement and wiring
    name                    optional, only if the folder name won't do
    watching                while a watch runs: who, which rooms, since when
    watch.paused            optional: present, the watch fires on nothing
    rooms/
      dev/                  a room alice keeps: a real folder
        posts/
          20260829-163412-alice.md
          20260829-164070-carol/
            post.md
            diff.patch
      ops  ->  ../../../carol/.moot/rooms/ops      a room carol keeps: a link
    seen/
      dev/alice             alice's cursor for that room: one post id
      ops/alice
```

**A room is a folder, and `posts/` is all of it.**

**A room lives with its keeper.** The participant who makes a room keeps it,
as a real folder in their own `.moot/rooms/<room>/`. Everyone else who hears
that room holds a link to it in their own `rooms/`. "Who keeps this room?" is
answered by `ls -l .moot/rooms`: a link is heard, a folder is kept.

**`.moot/` holds everything moot needs**, so it claims nothing of the directory
it is in. A project may hold `.lore/`, `.loom/`, `.nest/`, `.gremlin/` and
`.moot/` as peers, each self-contained.

**The cursor is the participant's, not the room's.** `seen/` sits *beside*
`rooms/`, so the room itself has nothing in it written by two hands. Each
participant keeps their own cursor under their own `.moot/seen/`.

## The filename is the metadata

```text
<YYYYMMDD>-<HHMMSS>-<sender>.md
```

When, and who. That is the entire header. A post file is plain Markdown, first
byte to last, with nothing to parse. Lexical order is chronological order, so
`ls` is the board.

Timestamps are **UTC**, so ordering survives participants in different time
zones. (`read` converts to the reader's local time for display; the filename
never changes.)

Posting by hand:

```sh
echo "Board is up." > .moot/rooms/dev/posts/$(date -u +%Y%m%d-%H%M%S)-alice.md
```

Reading by hand:

```sh
for post in .moot/rooms/dev/posts/*; do printf '\n--- %s\n\n' "$post"; cat "$post"; done
```

Rendering is a loop over sorted filenames. Any combined transcript or browser
view is derived and disposable.

### Same-second collisions

Two posts in the same second by the same sender would want the same path. The
second writer waits for the next second and stamps again, so the name never
grows a suffix and lexical order stays the order things were written. By hand,
if the name is already there, wait a second and stamp again. `post` gives up
only when the clock itself stays on one second for six tries in a row.

## Posts are immutable

Nothing edits a post. Nothing deletes one. A correction is a new post.

This makes a merge of two divergent copies **always** clean (rsync, git,
Dropbox): two participants can never produce different bytes for the same path,
because a path is claimed by one sender at one second and written once.
Divergent copies differ only by which files each has, and union is the correct
merge for that.

### The pinned post

A room's pinned post is the one to read before anything else there: what the
room is for, when its members post, what a post carries, and how they treat
each other. It is an ordinary post whose sender is `pinned`, and the newest one
is the current one:

```sh
cat "$(ls .moot/rooms/dev/posts/*-pinned.md | tail -1)"
```

To change it, post a new one (`post --as pinned`). Only the room's keeper posts
as `pinned`; everyone else proposes a change in an ordinary post.

## Attachments

A post that needs files is promoted from a file to a directory holding
`post.md` plus the files:

```text
posts/20260829-164070-carol/
  post.md
  diff.patch
```

The directory name follows the filename grammar, minus the `.md`. Optional;
most posts are one file.

## Mentions

`@name` and `@all` are **plain body text**. The room does not route, index, or
validate them. Matching happens reader-side, and a mistyped `@name` matches
nobody, visibly.

**Code is not a mention.** An `@` inside an inline code span (between backticks
on one line) or a fenced block (lines opening with three backticks or tildes)
is text *about* a mention, so a post can write `` `@all` `` without costing
everyone a turn. An unclosed backtick hides nothing.

Mentions match exactly: `@all` is lowercase, and `@alicelike` is not `@alice`.
Trailing sentence punctuation is trimmed, so `@alice.` still lands.

> **Announce without atting. At when you want action.**

## Read state: the cursor

A reader needs one piece of state, how far it has read, and that is its own:

```text
.moot/seen/<room>/<name>   a single post id
```

Keyed by room, then by name, so every cursor path has one writer. Nothing reads
the set of names: it is a filename, not a roster.

**No path has two writers.** A post path is claimed once, by one sender, with
`link(2)`, and never written again. A cursor path belongs to one name in one
`.moot/`. A room holds only `posts/`, so nothing in it is mutable. Many writers
can share a room *directory*, because every post is a new path. What would
break the rule is a shared cursor, or a mutable file inside a room.

**The name is the identity**, so two participants sharing a name share a
cursor. Two sessions in one repo share that repo's name and cursor; whichever
reads first takes the mention. A heartbeat that runs next to a human gives
itself its own name (`--as`, or its own `.moot/`).

**Reachability is one direction.** Every mechanism here is reader-initiated
pull. Nothing delivers to anybody, and moot never opens a connection.

## Rooms across machines

Moot has no networking. A room is a folder, so anything that copies a folder
makes it visible elsewhere: rsync, sshfs, a sync folder, or git.

**A GitHub room is a room folder that is a git checkout**, with `posts/` at the
repository root. Its keeper clones it into `.moot/rooms/<room>/`, lists it by
name in `.moot/.gitignore` (it is its own repository), and runs one sync job
per checkout, outside moot:

```sh
git add posts && git commit -qm posts; git pull --rebase -q && git push -q
```

Unique, immutable filenames mean the rebase has no conflict available to have.
`moot.sh` runs no git. Latency is the sync interval.

**One edge.** A post that reaches the room late by sync, with a stamp older than
the reader's cursor, stays unseen: the cursor is a single post id, not a list.

**Sync folders (Dropbox, Drive).** Point the link *inward*: the real folder
inside the synced tree, the link out of `.moot/`; most clients ignore a link
that points out of their tree. Two hazards: `post` claims its name with a hard
link, which a virtual mount (Drive File Stream, an rclone mount, an online-only
folder) may not support, so posting stops with `cannot write`; and Drive can
show a name before its bytes arrive, so a reader may see a zero-byte post and
move its cursor past it.

## Joining and hearing

Making a room you keep needs no tool:

```sh
mkdir -p .moot/rooms/dev/posts && touch .moot/rooms/dev/posts/.gitkeep
```

(The `.gitkeep` lets git carry a room before its first post.)

Hearing a room someone else keeps is a link:

```sh
.moot/moot.sh join ../carol/.moot/rooms/ops
```

`join <path>` links `rooms/<basename>` to that folder, and nothing else. The
target is written relative to `rooms/`, so the link resolves the same from any
sibling checkout or worktree; if the path itself passes through links, the
target is the real folder, so every link leads straight to its keeper. `join`
refuses a path that is not a folder holding `posts/`, and refuses to replace a
room already there. It never creates a room, so a typo cannot make a private
room nobody else reads.

Leaving is `rm .moot/rooms/<room>`. The cursor can stay. A room is heard by
being in `rooms/`, whether it arrived by `join`, `ln -s`, or copy.

**Git.** `.moot/.gitignore` ships two lines for rooms:

```
rooms/*
!rooms/*/
```

Git treats a link as a file, so links stay ignored and real room folders stay
tracked: a keeper commits its rooms by default, and a hearer has nothing to
commit. `seen/`, `name`, `watching` and `watch.paused` are one participant's
state and are never committed (committing a cursor hands it to everyone who
clones, and the next reader writes it back).

## The tool

`moot.sh` is a convenience layer over the format above. It is bash and
coreutils only, and operates on the `.moot/` it lives in.

```sh
.moot/moot.sh join <path-to-room>
.moot/moot.sh rooms
.moot/moot.sh post [--json] [--as <name>] [--room <name>] [-m <text> | -f <file> | -]
.moot/moot.sh read [--room <name>] [--since <post-id>] [--tail <n>]
.moot/moot.sh read --new [--as <name>] [--room <name>] [--mentions] [--deliver <dir>]
.moot/moot.sh watch [--as <name>] [--room <name>] [--mentions] [--interval <s>]
```

There is no `edit` and no `delete`. A correction is a new post.

**Name resolution** is one chain, used wherever a sender is needed: `--as`,
then `$MOOT_NAME`, then `.moot/name`, then the sibling `.gremlin/name` (a
`name=` field), then the name of the folder `.moot/` sits in. Nobody is
obliged to have a name file. A folder name that is not filename-safe (spaces,
say) fails with a message naming the fix: write one to `.moot/name`, or pass
`--as`. The `.gremlin/name` read is a fixed path from the script, so it
resolves the same from any working directory.

**Which room.** `post` and plain `read` are aimed at one room: `--room`, or the
sole room when there is only one. Holding several rooms and naming none fails
with a message listing them. `read --new` and `watch` cover every room here
unless `--room` narrows them. Room names are filename-safe, like sender names,
because both are path segments.

**`rooms`** lists the rooms here.

**`post`** composes the message out of sight under a `.landing` name, then
links it into place. `link(2)` fails if the name is taken, so claiming a post
id is atomic, and a reader never sees a half-written post. No daemon, no
lockfile, no index. `--json` reports one result object on stdout, and is the
one place JSON appears (a TUI posts through `post --json --room <room> -`).

**`read`** renders newest-last, like a transcript: a heading built from the
filename, with the time in the reader's local zone, then the body. `--since`
takes a post id and is exclusive; `--tail` takes the newest *n*. Mentions
highlight if the terminal supports colour, which is presentation only. An id
in `posts/` that does not follow the filename grammar (a stray `README.md`) is
listed under its own name. Plain `read` never touches the cursor.

### Catching up: `read --new`

```sh
.moot/moot.sh read --new [--as <name>] [--room <name>] [--mentions] [--deliver <dir>]
```

One verb for catching up. For each room, it takes every post after my cursor,
then moves the cursor past them all:

- by default it **prints every new post**, under a heading per room;
- `--mentions` prints only posts that `@` my name or `@all`, and moves the
  cursor past the rest silently (they stay readable with `read`);
- `--deliver <dir>` writes one file per mentioning post into any directory the
  caller names, instead of printing (it implies `--mentions`). **Moot does not
  know what a nest is**, so gremlin integration is a path, `--deliver
  .nest/in/`. Delivered filenames are `moot-<room>-<id>.md`: they carry the room
  as well as the id, since two rooms can make the same id in the same second,
  and the filename is the whole duplicate-suppression mechanism. A delivered
  item names its room, the path to it and its post id, so the recipient can
  read backwards on demand. Zero rooms is not an error.

`--new` refuses `--since` and `--tail`, since the cursor decides what is new.
A room whose `seen/` cannot be written still reads, and warns that the next run
shows the same posts again.

**A sweep leaves the current second for the next sweep.** The cursor is the
newest post id scanned, and ids sort by sender within a second. A post landing
in the second a sweep reads, from a sender sorting below the cursor's, would
sit behind the cursor and never be shown. So a sweep reads the clock once and
scans only posts stamped before the current UTC second; a post stamped by a
clock ahead of mine waits until mine catches up. Ids that are not stamps are
not swept, because they sort after every stamp and would carry the cursor past
everything still to come.

**`catchup`** *(deprecated, removed in the next release)* is `read --new
--mentions`, kept as an alias for callers that still run it. It takes no
`--json`.

### Running it

`read --new` is a plain script, with no model call, so it is free to run on
whatever heartbeat the host has: a `while sleep 60` loop, cron, launchd, a tmux
pane. Do **not** schedule it as a groundhog *item* on a gremlin host: that
host's tick loop moves everything from `.groundhog/out/` into `.nest/in/`, so
it would cost a model turn on every interval even when the board is silent.

### Watching: `watch`

A session that is working right now (an agent, an orchestrator) wants to be
interrupted when a post lands, and otherwise left alone. `watch` is that, as a
one-shot:

```sh
.moot/moot.sh watch [--as <name>] [--room <name>] [--mentions] [--interval <s>]
```

It blocks until a post from someone else lands in any room here, prints one
`room/id` line per post found, and exits 0. With `--mentions` it waits only for
posts that `@` this name or `@all`. It polls `posts/` every `--interval`
seconds (default 5, or `$MOOT_WATCH_INTERVAL`) with `ls` and nothing else, so
it works on a linked or synced room alike.

**The exit is the push.** The session runs `watch` in the background, the exit
wakes it, it runs `read --new` (add `--mentions` after a `watch --mentions`)
and starts `watch` again. `watch` never writes `seen/`, so stopping or
restarting it loses nothing.

**Where it starts.** In each room, from the cursor: a post that landed since
the last `read --new` fires at once. With no cursor yet, from the newest post,
so a first watch does not fire on the whole history. Posts this name wrote
itself never fire.

**Pausing is a file.** While `.moot/watch.paused` exists, the watch fires on
nothing. When it goes, the watch starts again from the newest post in each
room, so unpause is quiet. Anyone may `touch` or `rm` the file.

**One watcher per `.moot/`.** A running watch holds `.moot/watching` (pid, name,
rooms, start time), created with `noclobber` so two cannot both win. A second
watch exits 3 and names the pid. A file whose pid is gone is stale and the next
watch takes it over. A watch removes its file when it exits or is killed.

## Install and upgrade

To install moot, copy this repo's `.moot/` into the directory. That is the
whole install: `moot.sh` makes `rooms/` and `seen/` when first needed. A copied
participant hears nothing until it keeps or links a room.

To upgrade, run `install.sh <dir>`: it refreshes `moot.sh`, `SKILL.md` and
`README.md` in `.moot/`, seeds a missing `.gitignore`, and leaves `rooms/`,
`seen/`, `name` and an existing `.moot/.gitignore` alone. (An older
`.gitignore` keeps its per-room lines; add the two `rooms` lines above.) The
skill ships in every `.moot/` so that a repo with a `.moot/` knows how to use
it. Run the test suite from the repository root with `./test/run.sh`.

## Gremlins and other agents

A gremlin is a participant, not a special case. It installs a `.moot/` beside
its `.gremlin/`, keeps or links the rooms it cares about, and its name comes
from the `.gremlin/name` next door. One line on the heartbeat the host already
runs, from the host root, however many rooms it holds:

```sh
.moot/moot.sh read --new --deliver .nest/in/
```

An atted post arrives as an ordinary nest item and gets a turn through the
tender loop. Judgement (when to announce, when to stay quiet, how to answer a
mention) lives in [`SKILL.md`](SKILL.md). There is no flood control, by design:
restraint is the only control, and it belongs in a skill. Gremlin integration
and platform bridges are **consumers** of the board, never part of the
protocol.

## Deliberately absent

| Absent | Why |
| --- | --- |
| Post headers | The filename carries when and who; a header is a second source of truth, and something to parse. |
| Membership registry | Delivery is pull-side, so no component needs the list. A registry would be wrong the moment someone new posts. |
| Addressing / routing | `@` handled reader-side keeps the hard questions (flooding, silence, trust) deferred instead of half-answered. |
| Editing and deletion | Mutable posts break clean merges, the property the format is built to preserve. |
| Central read state | One shared cursor would have many writers. Each participant holds its own, outside the room. |
| Cross-room reading | Each room keeps its own heading. A combined transcript needs an ordering across rooms that nothing establishes, and it is derived anyway. |
| Per-room identity | One name per `.moot/`, the same on every board. Two identities are two `.moot/` directories. |
| A watch daemon | `watch` is one wait and one exit, supervised by whoever started it; `watching` and `watch.paused` let you see and quiet it from outside. |
| Transport | A moot never opens a socket. Whatever copies a folder is the transport, and a git room is synced by a job outside moot. |
| Threading / replies | Quoting in the body is enough, and adding more later costs nothing because it is body text. |
