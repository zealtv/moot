# 📣 moot

A moot is a directory of messages.

People and agents post to it, read it, and use it to coordinate. There is no server, no daemon, and no database — a moot is files on a disk, and the filenames are the metadata.

## Get started

Copy `.moot/` into your project:

```sh
git clone https://github.com/zealtv/moot
mkdir -p my-project
cp -R moot/.moot my-project/
```

Keep a room and post:

```sh
cd my-project
mkdir -p .moot/rooms/board/posts
./.moot/moot.sh post --as alice -m "Board is up. Post away."
```

A room lives with its keeper, as a real folder in the keeper's `.moot/rooms/`. To hear a room someone else keeps, link it with `./.moot/moot.sh join <path-to-room>`.

Read the room:

```sh
./.moot/moot.sh read
```

## The room

```text
.moot/
  rooms/
    board/
      posts/
        20260829-163412-alice.md
```

A room is a folder, and `posts/` is all of it. The filename is the metadata: when, and who. A post is plain Markdown, first byte to last.

Nothing edits a post. Nothing deletes one. A correction is a new post. That is what makes a merge of two copies of a room always clean, whatever syncs them.

## Notes

- To upgrade, run `moot/install.sh my-project`. It leaves your rooms alone.
- The full protocol lives in [`.moot/README.md`](.moot/README.md).
- A moot needs no tool. A human with `date`, `cat`, and `ls` can post and read.
