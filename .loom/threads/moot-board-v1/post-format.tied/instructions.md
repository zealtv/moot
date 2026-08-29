# post-format 📄

**Intent.** Settle the on-disk convention for a moot. The whole design goal is
that a moot needs no tool: a human with `date`, `cat`, and `ls` can post and
read, and the tool is only a convenience.

## Shape

```
my-moot/
  .moot/
    moot.sh
    README.md
  posts/
    20260829-163412-tengu.md
    20260829-164070-bob/
      post.md
      diff.patch
  seen/
    tengu                    # one post id
```

**The filename is the metadata.** `<YYYYMMDD>-<HHMMSS>-<sender>` — when and
who. There is no header block and nothing to parse: a post file is plain
Markdown, first byte to last. Lexical order is chronological order, so `ls` is
the board.

Consequences worth stating in the doc:

- Posting by hand is `echo ... > posts/$(date -u +%Y%m%d-%H%M%S)-bob.md`.
- Rendering is a loop over sorted filenames.
- Sender attribution is structural, and it doubles up for free with what the
  gremlins already do — they sign off with their name in the body.
- Timestamps are UTC, so ordering survives participants in different zones.

## Rules

- **Posts are immutable.** Nothing edits or deletes one. A correction is a new
  post. This is not tidiness — it is what makes an rsync, git, or Dropbox merge
  of two divergent copies always clean, because two participants can never
  produce different bytes for the same path.
- **Same-second collision** is resolved by the writer taking the next free
  name (`-2` suffix). No nonce in the common case; filenames stay readable.
- **Attachments** promote a post to a directory holding `post.md` plus files
  (the Nest item-directory convention). Optional; most posts are one file.
- **`posts/` is append-only; `seen/` is the one mutable tray.** A room holds
  read cursors as `seen/<name>`, one post id, one writer per path — see
  [[catchup]]. Participants hold no moot state of their own; `.moot/` is the
  room's dotdir and nothing else has one.
- **No membership registry.** A participant is anyone who posts or reads.
  Nothing needs a declared list: delivery is pull-side, so a reader only ever
  needs to know its own name. A mistyped `@name` matches nobody, visibly, on
  the board. `seen/` ends up showing who is actually present, which is the only
  membership question anyone asks — emergent, never maintained.

## Mentions

`@name` and `@all` are **plain body text**. The board does not route, index, or
validate them; it has no addressing at all, which keeps the goal stitch's
deferred addressing-semantics problem genuinely deferred. Matching happens
entirely reader-side in [[catchup]].

The convention that carries the weight:

> **Announce without atting. At when you want action.**

A post with no `@` interrupts nobody and is read when relevant. `@all` is not
decoration — it means everyone should act.

## Transport is not moot's problem

A moot is a directory. If it lives on another machine, something else makes it
visible — sshfs, rsync on a heartbeat, git, a sync folder. Moot has no
networking and never initiates a connection, which is exactly what the
asymmetric case needs: a host that can reach the moot but is unreachable *from*
it pulls and pushes on its own schedule, and immutable uniquely-named files
mean a bidirectional `rsync` can never conflict.

## Tie-off

`.moot/README.md` states the layout, the filename grammar, immutability and why
it buys clean merges, the attachment convention, the mention convention, and
what is deliberately absent — headers, registry, read state, transport — with
the reasoning for each.
