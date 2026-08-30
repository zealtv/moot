# moot-transports 🚚

**Goal.** Make a room reachable across the internet without moot growing a
network. Two transports, one already latent in the format and one worth a few
lines of shell: a room directory that is a git clone, and a room directory that
is a symlink into a cloud-sync folder.

**Why now.** The README says transport is not moot's problem and lists rsync,
git, sshfs and a sync folder in one breath. That was the right position and it
is now underspecified: everything it lists works on a LAN or over SSH, and the
common case is two devices on different networks with no route between them.
Both answers below are already permitted by the format. Neither needs the
format to change.

**The property both transports lean on.** Posts are immutable and uniquely
named, so a room only ever gains files. Two divergent git branches union-merge
with no conflict available to have; a cloud-sync client never sees the same
path written twice and so never writes a conflicted copy. This is the same
argument the README already makes for rsync, applied twice more.

**Settled shape.**

- **Git.** `rooms/<name>/` *is* the clone — repo root is room root, so `posts/`
  sits at the top of the repository. The room's address is then
  `git remote get-url origin` and no new file records it. `seen/` stays out for
  free, because it already lives beside `rooms/` rather than inside one.
- **Cloud sync.** `rooms/<name>/` is a symlink whose target lives inside the
  Dropbox or Drive tree. This needs no code at all: `subscribed_rooms()` tests
  `[ -d ]` and `post_ids()` tests `[ -e ]`, and both follow symlinks. It is
  documentation, not a mechanism.
- **Detection, not configuration.** A room that is a clone syncs; a room that
  is not, does not. No flag, no config key, no per-room settings file.
- **A moot never initiates a connection** stays true in spirit: fetching is
  reader-initiated, on the participant's own schedule, inside a verb they
  already run.

**Tie-off.** `subscribe <git-url>` makes a working room from a URL alone;
`catchup` fetches a cloned room before sweeping it; `post` commits and pushes
best-effort and never loses a post when the network is gone; the README
documents both transports along with the places each one is genuinely sharp;
`./test/run.sh` passes.

**Deferred.** Any notion of a room that is *shared* rather than copied, and any
credential handling of moot's own. Auth is the transport's problem, which is
the whole point of not having one.
