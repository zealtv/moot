# git-sync 🔄

**Intent.** Keep a cloned room current in both directions, inside the verbs
that already exist. Depends on [[git-room]].

## Reading: catchup fetches first

`catchup` is already the reader-initiated pull the README commits to, so the
fetch belongs there and nowhere else. If `rooms/<name>/.git` exists, fetch
before sweeping that room; otherwise sweep exactly as now. That is the whole
detection rule — a room that is a clone syncs, one that is not, does not.

Keep the clone at depth 1 permanently rather than letting history accumulate
forever:

```sh
git fetch --depth 1 origin && git reset --hard FETCH_HEAD
```

**`reset --hard` destroys an unpushed local post.** Only take that path when
the tree is clean; when it is not, rebase instead so a post written offline
survives to be pushed later. Getting this backwards loses a message, which is
the one failure this primitive must not have.

A fetch that fails is not a failed catchup. Warn, sweep what is on disk, and
carry on: the room is a directory, and the directory is still readable.

## Writing: post commits and pushes

Order matters and is the entire correctness argument. Write the post file
first, through the existing `.landing` + `ln` path so the name is claimed
atomically. Then commit, with the post id as the message. Then push,
best-effort.

A push rejected as non-fast-forward means someone else posted. Rebase and
retry. Unlike almost everywhere else in git, this retry loop is honest rather
than hopeful: every post is a new uniquely-named file, so the rebase has no
conflict available to have. Say that in a comment, because the next reader will
assume the loop is a wish.

Offline must not fail a post. The file is written and committed locally; the
push warns and the backlog goes out on the next `post` or `catchup`.

## Tie-off

Two clones of one bare repository exchange posts through `catchup` and `post`
with no manual git. A post written with the remote unreachable succeeds
locally, prints a warning, and reaches the other clone once the remote is back.
A simultaneous post from both clones lands both messages with no manual
intervention. `catchup` on a room that is not a clone is byte-identical to its
behaviour today. All of it in `test/run.sh` against local bare repositories —
the suite stays bash and coreutils, and never touches the network.
