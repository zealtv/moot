#!/usr/bin/env bash
#
# moot — a directory of messages.
#
# This script is a convenience, never a dependency. Everything it does can be
# done by hand with date, cat, and ls; see README.md for the format itself.
#
# It operates on the .moot/ it lives in, so each deployed copy is
# self-contained. Everything moot needs is under that one directory: the rooms
# it holds, and this participant's own read state beside them.

set -euo pipefail
export LC_ALL=C

moot_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

# A room is a folder under rooms/, and posts/ is all of it. That folder is the
# sync unit; nothing else in .moot/ travels with it.
rooms_dir="$moot_dir/rooms"

# The cursor is mine, not the room's, so it lives beside rooms/ rather than
# inside one. Keyed by room and then by name: a room that gets synced by
# accident still carries no reader's state, and each room is read separately.
seen_dir="$moot_dir/seen"

# Set by use_room(); every verb that is aimed at one room resolves first.
room=
room_dir=
posts_dir=

# Accumulated across the rooms catchup sweeps, so one sweep reports once.
sweep_delivered=()
sweep_reports=()
sweep_changed=0

die() { printf 'moot: %s\n' "$*" >&2; exit 1; }

json_escape() {
  # Escape a string for a JSON double-quoted scalar.
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\t'/\\t}
  s=${s//$'\r'/\\r}
  printf '%s' "$s"
}

usage() {
  cat <<'USAGE'
moot — a directory of messages

  moot.sh init [--json] [--as <name>] [--room <name>]
  moot.sh join [--json] <room>
  moot.sh subscribe [--json] <git-url> [<room>]
  moot.sh rooms
  moot.sh post [--json] [--as <name>] [--room <name>] [-m <text> | -f <file> | -]
  moot.sh read [--room <name>] [--since <post-id>] [--tail <n>] [--follow]
  moot.sh read --new [--as <name>] [--room <name>]
  moot.sh catchup [--json] [--as <name>] [--room <name>] [--deliver <dir>]

A post is <YYYYMMDD>-<HHMMSS>-<sender>.md in rooms/<room>/posts/, UTC, plain
Markdown. Posts are immutable: there is no edit and no delete. A correction is
a new post.

post and read are aimed at one room; catchup and read --new sweep every room
here unless --room narrows it. read prints times in local time; the filenames
stay UTC.

join makes a room here; subscribe clones one that already exists elsewhere,
where rooms/<room>/ is the clone and its git remote is the room's address.
USAGE
}

# ---------------------------------------------------------------- name resolution

# --as, then $MOOT_NAME, then .moot/name, then the sibling .gremlin/name, then
# the name of the folder .moot/ sits in. Nobody is obliged to have a name file:
# every step reads something that already exists, and a repo's checkout is
# named after the repo on every machine. Shared with catchup: one chain, one
# concept.

moot_name() {
  [ -r "$moot_dir/name" ] || return 1
  head -n 1 -- "$moot_dir/name" | tr -d '[:space:]'
}

# .gremlin/name is a key=value file (name=alice, source=generated), so take the
# field rather than the line. An older bare-name file has no =, and still
# resolves. Read as a sibling of .moot/, the way every other primitive in the
# family reads its neighbours: a fixed path from the script's own location, so
# the answer does not depend on the working directory and no stray .gremlin/ in
# some ancestor can be picked up by accident. A .moot/ with no .gremlin/ beside
# it is not part of a gremlin, and the rest of the chain is the honest answer.
gremlin_name() {
  local file="$moot_dir/../.gremlin/name" value
  [ -r "$file" ] || return 1
  value=$(sed -n 's/^name=//p' "$file" | head -n 1 | tr -d '[:space:]')
  [ -n "$value" ] || value=$(head -n 1 -- "$file" | tr -d '[:space:]')
  printf '%s' "$value"
}

# A path segment written by this tool has to be filename-safe, whether it names
# a sender or a room. One check, one message shape, two callers.
check_segment() {
  local kind=$1 value=$2
  case $value in
    *[!A-Za-z0-9._-]* | .* | '')
      die "$kind '$value' is not filename-safe (use A-Z a-z 0-9 . _ -)" ;;
  esac
}

resolve_name() {
  local as=${1:-} name=
  if [ -n "$as" ]; then
    name=$as
  elif [ -n "${MOOT_NAME:-}" ]; then
    name=$MOOT_NAME
  elif name=$(moot_name) && [ -n "$name" ]; then
    :
  elif name=$(gremlin_name) && [ -n "$name" ]; then
    :
  else
    # The host folder, read from the script's own location like .gremlin/name,
    # so the working directory never comes into it.
    name=$(cd -- "$moot_dir/.." && pwd); name=${name##*/}
    case $name in
      *[!A-Za-z0-9._-]* | .* | '')
        die "folder name '$name' is not a filename-safe sender; write one to .moot/name or pass --as <name>" ;;
    esac
  fi
  check_segment 'sender name' "$name"
  printf '%s' "$name"
}

# ---------------------------------------------------------------- room resolution

# Subscribed rooms, lexically. A room is subscribed by being a directory under
# rooms/: one that arrived over rsync needs no join to count.
subscribed_rooms() {
  local entry base
  [ -d "$rooms_dir" ] || return 0
  for entry in "$rooms_dir"/*; do
    [ -d "$entry" ] || continue
    base=${entry##*/}
    case $base in .*) continue ;; esac
    printf '%s\n' "$base"
  done
}

room_pointer() {
  [ -r "$moot_dir/room" ] || return 1
  head -n 1 -- "$moot_dir/room" | tr -d '[:space:]'
}

# --room, then $MOOT_ROOM, then .moot/room, then the sole room. The same shape
# as the name chain, for the same reason: with one room nobody types a flag.
default_room() {
  local name=
  if [ -n "${MOOT_ROOM:-}" ]; then
    name=$MOOT_ROOM
  elif name=$(room_pointer) && [ -n "$name" ]; then
    :
  else
    local rooms=()
    while IFS= read -r name; do rooms+=("$name"); done < <(subscribed_rooms)
    [ ${#rooms[@]} = 1 ] || return 1
    name=${rooms[0]}
  fi
  [ -n "$name" ] || return 1
  printf '%s' "$name"
}

# The error is the entire user interface of holding several rooms, so it says
# what is subscribed and what to type, not what the usage line looks like.
no_room() {
  local rooms=() r
  while IFS= read -r r; do rooms+=("$r"); done < <(subscribed_rooms)
  if [ ${#rooms[@]} = 0 ]; then
    die "no rooms here yet. Create one with: $0 join <room>"
  fi
  printf 'moot: several rooms here and none chosen:\n' >&2
  printf '  %s\n' "${rooms[@]}" >&2
  printf 'Pick one with --room <room>, or make one the default with: %s init --room <room>\n' "$0" >&2
  exit 1
}

# Resolve the room this command is aimed at and point posts_dir at it.
use_room() {
  local want=${1:-}
  if [ -n "$want" ]; then
    room=$want
  else
    room=$(default_room) || no_room
  fi
  check_segment 'room name' "$room"
  room_dir="$rooms_dir/$room"
  posts_dir="$room_dir/posts"
}

# ---------------------------------------------------------------- post listing

# Post ids in chronological order. Lexical order is chronological order, which
# is the whole point of the filename grammar. Anything hidden (a .landing file
# mid-compose) is skipped, so a reader never sees a half-written post.
# Sorted by id, not by filename: the cursor compares ids, and a filename
# sort puts an older `-N` post (`x-alice-2.md`) before `x-alice.md` because
# `-` sorts before `.`. Sorting the ids keeps every reader's order and the
# cursor's order the same, including for -N posts written before post stopped
# making them.
post_ids() {
  local entry base
  [ -d "$posts_dir" ] || return 0
  for entry in "$posts_dir"/*; do
    [ -e "$entry" ] || continue
    base=${entry##*/}
    case $base in .*) continue ;; esac
    if [ -d "$entry" ]; then
      printf '%s\n' "$base"
    else
      case $base in *.md) printf '%s\n' "${base%.md}" ;; esac
    fi
  done | sort -u
}

post_body_path() {
  local id=$1
  if [ -d "$posts_dir/$id" ]; then
    printf '%s' "$posts_dir/$id/post.md"
  else
    printf '%s' "$posts_dir/$id.md"
  fi
}

# What a sweep (catchup, read --new) may read: stamped ids in order, leaving out
# any stamped in the current UTC second or later. The cursor is the newest id
# scanned, so a sweep that moved it onto the current second would never show a
# post that lands later in that same second under a name sorting lower (bob
# after carol). Such a post waits for the next sweep, and so does one stamped
# by a clock ahead of mine. $sweep_now is read once per sweep. Ids that are not
# stamps are not swept: sorting after every stamp, one would park the cursor
# past every post still to come.
sweep_now=
settled_ids() {
  local id
  while IFS= read -r id; do
    is_stamp_id "$id" || continue
    [ "${id:0:15}" \< "$sweep_now" ] || continue
    printf '%s\n' "$id"
  done < <(post_ids)
}

# ---------------------------------------------------------------- init

cmd_init() {
  local json=0 changed=0 as= room_opt= d
  [ "${1:-}" = --json ] && { json=1; shift; }
  while [ $# -gt 0 ]; do
    case $1 in
      --as) [ $# -ge 2 ] || die "--as needs a name"; as=$2; shift 2 ;;
      --room) [ $# -ge 2 ] || die "--room needs a room"; room_opt=$2; shift 2 ;;
      -h|--help) usage; return 0 ;;
      *) die "unknown option for init: $1" ;;
    esac
  done
  # init makes a participant, not a room: it no longer knows which room, and
  # `join` is the only thing that creates one.
  for d in "$rooms_dir" "$seen_dir"; do
    [ -d "$d" ] || { mkdir -p -- "$d"; changed=1; }
  done
  # Only written when asked for. Without it the rest of the name chain
  # resolves, which is how a gremlin or a human already has a name.
  if [ -n "$as" ]; then
    local checked; checked=$(resolve_name "$as")
    if [ "$checked" != "$(cat -- "$moot_dir/name" 2>/dev/null || true)" ]; then
      printf '%s\n' "$checked" > "$moot_dir/name"; changed=1
    fi
  fi
  # Likewise .moot/room: a pointer, written only on request, and unnecessary
  # for as long as there is one room to point at.
  if [ -n "$room_opt" ]; then
    check_segment 'room name' "$room_opt"
    if [ "$room_opt" != "$(cat -- "$moot_dir/room" 2>/dev/null || true)" ]; then
      printf '%s\n' "$room_opt" > "$moot_dir/room"; changed=1
    fi
  fi
  local default; default=$(default_room) || default=
  if [ "$json" = 1 ]; then
    printf '{"schema_version":1,"command":"init","ok":true,"changed":%s,"moot":"%s","room":%s}\n' \
      "$([ "$changed" = 1 ] && echo true || echo false)" "$(json_escape "$moot_dir")" \
      "$([ -n "$default" ] && printf '"%s"' "$(json_escape "$default")" || printf null)"
  elif [ "$changed" = 1 ]; then
    printf 'initialised moot at %s\n' "$moot_dir"
    [ -n "$default" ] || printf 'no rooms yet: %s join <room>\n' "$0"
  else
    printf 'moot already initialised at %s\n' "$moot_dir"
    [ -n "$default" ] || printf 'no rooms yet: %s join <room>\n' "$0"
  fi
}

# ---------------------------------------------------------------- join and rooms

# The room store the README names: a .moots/ directory beside the checkouts,
# so beside the host that holds this .moot/. Prints the shared room's folder
# when one of this name exists there, and fails when none does.
shared_room_dir() {
  local dir; dir=$(cd -- "$moot_dir/../.." 2>/dev/null && pwd) || return 1
  [ -d "$dir/.moots/$1" ] || return 1
  printf '%s' "$dir/.moots/$1"
}

cmd_join() {
  local json=0 name= changed=0
  [ "${1:-}" = --json ] && { json=1; shift; }
  while [ $# -gt 0 ]; do
    case $1 in
      -h|--help) usage; return 0 ;;
      -*) die "unknown option for join: $1" ;;
      *) [ -z "$name" ] || die "join takes one room"; name=$1; shift ;;
    esac
  done
  [ -n "$name" ] || die "join needs a room name"
  check_segment 'room name' "$name"

  # A link that leads nowhere (dangling, or looping back on itself, as a
  # relative target written from the wrong folder does) cannot be made into a
  # room: say what is wrong with the link rather than let mkdir's error out.
  if [ -L "$rooms_dir/$name" ] && [ ! -d "$rooms_dir/$name" ]; then
    die "rooms/$name is a link that does not lead to a folder (dangling or looping); point it at the real room with an absolute path, or remove it"
  fi

  # A shared room of this name wins over a new private one: a private room
  # would take posts nobody else reads. Refuse, and print the link to make.
  if [ ! -e "$rooms_dir/$name" ] && [ ! -L "$rooms_dir/$name" ]; then
    local shared
    if shared=$(shared_room_dir "$name"); then
      die "a shared room named $name exists at $shared; joining would make a private one that shadows it. Link it instead: mkdir -p $(printf '%q' "$rooms_dir") && ln -s $(printf '%q' "$shared") $(printf '%q' "$rooms_dir/$name")"
    fi
  fi

  local posts="$rooms_dir/$name/posts"
  [ -d "$posts" ] || { mkdir -p -- "$posts"; changed=1; }
  # Git cannot track an empty directory; without this a room committed before
  # its first post loses posts/ on clone. Only the room needs it: a .gitkeep
  # anywhere else in .moot/ would invite committing one participant's state.
  [ -e "$posts/.gitkeep" ] || { : > "$posts/.gitkeep"; changed=1; }
  [ -d "$seen_dir/$name" ] || { mkdir -p -- "$seen_dir/$name"; changed=1; }

  if [ "$json" = 1 ]; then
    printf '{"schema_version":1,"command":"join","ok":true,"changed":%s,"room":"%s","path":"%s"}\n' \
      "$([ "$changed" = 1 ] && echo true || echo false)" \
      "$(json_escape "$name")" "$(json_escape "rooms/$name")"
  elif [ "$changed" = 1 ]; then
    printf 'joined %s\n' "rooms/$name"
  else
    printf 'already in %s\n' "rooms/$name"
  fi
}

cmd_rooms() {
  local default r any=0
  [ "${1:-}" = -h ] || [ "${1:-}" = --help ] && { usage; return 0; }
  [ $# -eq 0 ] || die "rooms takes no arguments"
  default=$(default_room) || default=
  while IFS= read -r r; do
    any=1
    if [ "$r" = "$default" ]; then printf '* %s\n' "$r"; else printf '  %s\n' "$r"; fi
  done < <(subscribed_rooms)
  [ "$any" = 1 ] || printf 'no rooms here yet: %s join <room>\n' "$0"
}

# ---------------------------------------------------------------- subscribe

# The room name a URL implies: the last path segment with any .git stripped.
# Handles the scp-style git@host:board.git as well as a URL or a local path,
# because all three end in the name and differ only in what precedes it.
room_name_from_url() {
  local url=$1 base
  url=${url%/}
  base=${url##*/}
  base=${base##*:}
  printf '%s' "${base%.git}"
}

# join creates a room; subscribe acquires one that already exists elsewhere.
#
# The clone *is* the room: the repository root is the room root, so posts/ sits
# at the top of the repository and nothing else moot owns travels with it. That
# is also why no file here records the URL — `git remote get-url origin` is
# already the room's address, and a second copy could only drift from it.
cmd_subscribe() {
  local json=0 url= name= changed=0
  [ "${1:-}" = --json ] && { json=1; shift; }
  while [ $# -gt 0 ]; do
    case $1 in
      -h|--help) usage; return 0 ;;
      -*) die "unknown option for subscribe: $1" ;;
      *)
        if [ -z "$url" ]; then url=$1
        elif [ -z "$name" ]; then name=$1
        else die "subscribe takes a git url and an optional room name"; fi
        shift ;;
    esac
  done
  [ -n "$url" ] || die "subscribe needs a git url"

  # The one verb in this tool with a hard dependency. It says so in moot's own
  # voice rather than letting git's stderr surface from three frames down.
  command -v git >/dev/null 2>&1 || die "subscribe needs git on PATH"

  [ -n "$name" ] || name=$(room_name_from_url "$url")
  [ -n "$name" ] || die "cannot derive a room name from '$url' (pass one: $0 subscribe <url> <room>)"
  check_segment 'room name' "$name"

  local dest="$rooms_dir/$name"
  if [ -e "$dest" ]; then
    die "room $name is already here (rooms/$name)"
  fi

  mkdir -p -- "$rooms_dir"
  # --depth 1 because a room's history is its files, not its commits. A failed
  # clone leaves nothing behind: a half-room would be indistinguishable from a
  # subscribed one, since a room is subscribed by being a directory here.
  if ! git clone --quiet --depth 1 -- "$url" "$dest" 2>/dev/null; then
    rm -rf -- "$dest"
    die "cannot clone $url"
  fi
  changed=1

  # A remote that is still empty is the ordinary way this starts: make the
  # repository somewhere, subscribe, post. Seed posts/ exactly as join does so
  # the first post has somewhere to land; the first commit carries it over.
  local posts="$dest/posts"
  [ -d "$posts" ] || mkdir -p -- "$posts"
  [ -e "$posts/.gitkeep" ] || : > "$posts/.gitkeep"
  [ -d "$seen_dir/$name" ] || mkdir -p -- "$seen_dir/$name"

  if [ "$json" = 1 ]; then
    printf '{"schema_version":1,"command":"subscribe","ok":true,"changed":%s,"room":"%s","path":"%s","url":"%s"}\n' \
      "$([ "$changed" = 1 ] && echo true || echo false)" \
      "$(json_escape "$name")" "$(json_escape "rooms/$name")" "$(json_escape "$url")"
  else
    printf 'subscribed %s\n' "rooms/$name"
  fi
}

# ---------------------------------------------------------------- git transport

# A room that is a clone syncs; a room that is not, does not. That is the whole
# detection rule — no flag, no config key, no per-room settings file — and it
# is why every helper below is guarded by this one.
#
# The .git test comes first for a second reason: without it, `git -C` on an
# ordinary room would walk up and find the project repository that happens to
# contain .moot/, and operate on that instead.
room_is_clone() {
  [ -e "$room_dir/.git" ] && command -v git >/dev/null 2>&1
}

git_room() { git -C "$room_dir" "$@"; }

# The branch the remote itself declares. Asking the remote rather than assuming
# the local name settles the case where two participants clone the same empty
# repository under different init.defaultBranch settings and would otherwise
# push past each other forever.
git_room_target() {
  local b
  b=$(git_room ls-remote --symref origin HEAD 2>/dev/null \
        | sed -n 's#^ref: refs/heads/\([^[:space:]]*\).*#\1#p' | head -n 1)
  [ -n "$b" ] || b=$(git_room symbolic-ref --quiet --short HEAD 2>/dev/null) || b=
  printf '%s' "$b"
}

# Bring the room up to date. Fetching with no refspec follows whatever branch
# the remote's HEAD points at, so FETCH_HEAD is the room's current state
# whatever anyone called their branch.
#
# Rebase rather than reset: a reset would discard a post committed while the
# remote was unreachable, and losing a message is the one failure a board must
# not have. Rebase is a no-op when there is nothing local, a fast-forward when
# only the remote moved, and a replay when both did.
git_room_fetch() {
  git_room fetch --quiet origin 2>/dev/null || return 1
  git_room rev-parse --quiet --verify FETCH_HEAD >/dev/null 2>&1 || return 0
  if git_room rev-parse --quiet --verify HEAD >/dev/null 2>&1; then
    # The identity is set here for the same reason git_room_commit sets it: a
    # rebase writes commits too, and a host with no git config must still be
    # able to read its room.
    git_room -c user.name=moot -c user.email=moot@moot.invalid \
      rebase --quiet FETCH_HEAD >/dev/null 2>&1 && return 0
    git_room rebase --abort >/dev/null 2>&1 || true
    return 1
  fi
  # Nothing committed here yet, so there is nothing to replay: take the remote
  # wholesale. Untracked posts written before the first fetch are left alone.
  git_room reset --quiet --hard FETCH_HEAD >/dev/null 2>&1 || return 1
}

# The commit is transport, not authorship — the filename already carries who
# and when. The identity is set explicitly so a host with no git config can
# still post, and so the log reads in moot's names rather than the machine's.
git_room_commit() {
  local id=$1 sender=$2
  git_room add -A -- posts >/dev/null 2>&1 || return 1
  if git_room diff --cached --quiet 2>/dev/null; then
    return 0
  fi
  git_room -c "user.name=$sender" -c "user.email=$sender@moot.invalid" \
    commit --quiet -m "$id" >/dev/null 2>&1
}

# A rejected push means someone else posted in the meantime. Unlike almost
# everywhere else in git, this retry loop is honest rather than hopeful: every
# post is a new uniquely named file, so the rebase it retries after has no
# conflict available to have.
git_room_push() {
  local target n=0
  target=$(git_room_target)
  [ -n "$target" ] || return 1
  while :; do
    git_room push --quiet origin "HEAD:refs/heads/$target" >/dev/null 2>&1 && return 0
    n=$((n + 1))
    [ "$n" -le 3 ] || return 1
    git_room_fetch || return 1
  done
}

# ---------------------------------------------------------------- post

cmd_post() {
  local json=0 as= room_opt= body= have_body=0 stamp base target landing n

  [ "${1:-}" = --json ] && { json=1; shift; }

  while [ $# -gt 0 ]; do
    case $1 in
      --as) [ $# -ge 2 ] || die "--as needs a name"; as=$2; shift 2 ;;
      --room) [ $# -ge 2 ] || die "--room needs a room"; room_opt=$2; shift 2 ;;
      -m)   [ $# -ge 2 ] || die "-m needs text"; body=$2; have_body=1; shift 2 ;;
      -f)   [ $# -ge 2 ] || die "-f needs a file"
            [ -r "$2" ] || die "cannot read $2"
            body=$(cat -- "$2"); have_body=1; shift 2 ;;
      -)    body=$(cat); have_body=1; shift ;;
      -h|--help) usage; return 0 ;;
      *)    die "unknown option for post: $1" ;;
    esac
  done

  if [ "$have_body" = 0 ]; then
    [ -t 0 ] && die "nothing to post (use -m, -f, or pipe on stdin)"
    body=$(cat)
  fi
  [ -n "${body//[[:space:]]/}" ] || die "refusing to post an empty message"

  use_room "$room_opt"
  [ -d "$posts_dir" ] || die "no posts/ in room $room (run: $0 join $room)"

  # A private room with a shared namesake takes posts nobody else reads. Still
  # post, since the room may be meant, but say so.
  if [ ! -L "$room_dir" ]; then
    local shared
    if shared=$(shared_room_dir "$room") && [ ! "$room_dir" -ef "$shared" ]; then
      printf 'moot: warning: room %s here is a private folder, but a shared room of that name exists at %s; nobody who reads that one sees this post. To use it, move this folder aside and run: ln -s %s %s\n' \
        "$room" "$shared" "$(printf '%q' "$shared")" "$(printf '%q' "$room_dir")" >&2
    fi
  fi

  local sender; sender=$(resolve_name "$as")
  stamp=$(date -u +%Y%m%d-%H%M%S)

  # Compose out of sight, then link into place. A hidden name keeps the
  # in-progress post out of posts/* for every reader, tool or human.
  landing="$posts_dir/.$stamp-$sender.$$.landing"
  printf '%s\n' "$body" > "$landing"

  # link(2) fails if the target exists, so claiming a name is atomic. On a
  # same-second clash with my own earlier post, wait for the next second and
  # stamp again: the filename stays <date>-<time>-<sender>.md, so lexical
  # order is still the order things were written. A directory post of the
  # same id counts as taken too. Only a clock that stays on the same stamp
  # counts against the retries: a burst of posts under one name each wait their
  # turn, a second apart, and every one of them lands.
  n=0
  while :; do
    base="$stamp-$sender"
    target="$posts_dir/$base.md"
    if [ ! -e "$posts_dir/$base" ] && ln -- "$landing" "$target" 2>/dev/null; then
      break
    fi
    [ -e "$target" ] || [ -e "$posts_dir/$base" ] \
      || { rm -f -- "$landing"; die "cannot write $target"; }
    sleep 1
    local prev=$stamp
    stamp=$(date -u +%Y%m%d-%H%M%S)
    if [ "$stamp" = "$prev" ]; then
      n=$((n + 1))
      [ "$n" -le 5 ] || { rm -f -- "$landing"; die "cannot claim a post name: the clock is not moving"; }
    else
      n=0
    fi
  done
  rm -f -- "$landing"

  # The post is a file on a disk before git is involved, and it stays one if
  # every network in the world is down. Commit, then push best-effort: a push
  # that cannot go out now goes out with the next post or catchup.
  local warn=
  if room_is_clone; then
    if git_room_commit "$base" "$sender"; then
      git_room_push || warn="posted, but could not push $room to its remote"
    else
      warn="posted, but could not commit $room to its clone"
    fi
  fi

  if [ "$json" = 1 ]; then
    printf '{"schema_version":1,"command":"post","ok":true,"changed":true,"room":"%s","id":"%s","path":"%s","sender":"%s","timestamp":"%s"}\n' \
      "$(json_escape "$room")" \
      "$(json_escape "$base")" "$(json_escape "rooms/$room/posts/$base.md")" \
      "$(json_escape "$sender")" "$(json_escape "$stamp")"
  else
    printf 'posted rooms/%s/posts/%s.md\n' "$room" "$base"
  fi
  # Out of band in both modes: a --json caller reads one object on stdout, and
  # a failed push is news about the transport rather than about the post.
  [ -z "$warn" ] || printf 'moot: %s\n' "$warn" >&2
}

# ---------------------------------------------------------------- read

colour_on=0
init_colour() {
  [ -t 1 ] || return 0
  [ -z "${NO_COLOR:-}" ] || return 0
  [ "${TERM:-dumb}" != dumb ] || return 0
  colour_on=1
}

# Mentions highlight only here. This is presentation: the board itself does not
# route, index, or validate an @.
render_body() {
  if [ "$colour_on" = 1 ]; then
    sed -E "s/@[A-Za-z0-9._-]+/$(printf '\033[1;36m')&$(printf '\033[0m')/g"
  else
    cat
  fi
}

# Does this id follow the filename grammar, <8 digits>-<6 digits>-<sender>? Only
# such ids have a time to show, and only such ids are swept by catchup and
# read --new; anything else in posts/ (a stray README.md, say) is still listed
# by plain read, under its own name.
is_stamp_id() {
  case $1 in
    [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]-?*) return 0 ;;
  esac
  return 1
}

# Which `date` this machine has, found once per run: GNU takes -d, BSD takes
# -j -f. A heading used to try both on every post, four forks each on BSD.
date_flavour=
pick_date_flavour() {
  [ -z "$date_flavour" ] || return 0
  if date -d '1970-01-01 00:00:00 UTC' +%s >/dev/null 2>&1; then
    date_flavour=gnu
  elif date -j -f '%Y%m%d%H%M%S %z' '19700101000000 +0000' +%s >/dev/null 2>&1; then
    date_flavour=bsd
  else
    date_flavour=none
  fi
}

# "YYYY-MM-DD HH:MM:SS +ZZZZ" for a post's UTC day and time, in the reader's
# own zone, left in $local_when. One date fork per call. Display only: the
# filename stays UTC, and nothing is written back. A date with neither
# flavour, or a stamp that is not a real time, returns non-zero and the caller
# shows the stamp as written, labelled UTC, so a heading is never wrong, only
# less friendly. Sets a variable rather than printing, so the flavour found
# on the first call is still known on the second.
local_when=
local_stamp() {
  local day=$1 time=$2 fmt='+%Y-%m-%d %H:%M:%S %z'
  case $day$time in *[!0-9]* | '') return 1 ;; esac
  [ ${#day} = 8 ] && [ ${#time} = 6 ] || return 1
  pick_date_flavour
  case $date_flavour in
    gnu) local_when=$(date -d "${day:0:4}-${day:4:2}-${day:6:2} ${time:0:2}:${time:2:2}:${time:4:2} UTC" "$fmt" 2>/dev/null) || return 1 ;;
    bsd) local_when=$(date -j -f '%Y%m%d%H%M%S %z' "$day$time +0000" "$fmt" 2>/dev/null) || return 1 ;;
    *) return 1 ;;
  esac
}

render_post() {
  local id=$1 body dim reset day time sender rest
  dim=''; reset=''
  if [ "$colour_on" = 1 ]; then dim=$(printf '\033[2m'); reset=$(printf '\033[0m'); fi

  if is_stamp_id "$id"; then
    day=${id%%-*}; rest=${id#*-}
    time=${rest%%-*}; sender=${rest#*-}
    local_stamp "$day" "$time" \
      || local_when="${day:0:4}-${day:4:2}-${day:6:2} ${time:0:2}:${time:2:2}:${time:4:2} UTC"
    printf '\n%s── %s · %s ──%s\n\n' "$dim" "$local_when" "$sender" "$reset"
  else
    printf '\n%s── %s ──%s\n\n' "$dim" "$id" "$reset"
  fi

  body=$(post_body_path "$id")
  if [ -r "$body" ]; then
    render_body < "$body"
  else
    printf '(no post.md in %s)\n' "posts/$id"
  fi

  if [ -d "$posts_dir/$id" ]; then
    local f names=()
    for f in "$posts_dir/$id"/*; do
      [ -e "$f" ] || continue
      [ "${f##*/}" = post.md ] && continue
      names+=("${f##*/}")
    done
    if [ ${#names[@]} -gt 0 ]; then
      printf '\n%sattached: %s%s\n' "$dim" "${names[*]}" "$reset"
    fi
  fi
}

# The cursor, shared by catchup and read --new: .moot/seen/<room>/<name>, one
# post id, written by that name alone. cursor_get prints it (nothing if there is
# none yet); cursor_put returns non-zero when the room's seen/ cannot be written.
cursor_get() {
  local file="$seen_dir/$1/$2"
  [ -r "$file" ] || return 0
  head -n 1 -- "$file" | tr -d '[:space:]'
}

cursor_put() {
  mkdir -p -- "$seen_dir/$1" 2>/dev/null \
    && printf '%s\n' "$3" > "$seen_dir/$1/$2" 2>/dev/null
}

# read --new: everything since this reader's cursor, room by room, then the
# cursor moves. Rooms stay separate, each under its own heading; there is no
# merged timeline. It is the human's counterpart to catchup: catchup prints (or
# delivers) only what mentions me, this prints everything, mentions highlighted
# as read always does. Both move the one cursor.
read_new() {
  local as=$1 room_opt=$2 r me id cursor newest shown=0
  local rooms=()
  if [ -n "$room_opt" ]; then
    check_segment 'room name' "$room_opt"
    [ -d "$rooms_dir/$room_opt" ] || die "no room $room_opt here (run: $0 join $room_opt)"
    rooms=("$room_opt")
  else
    while IFS= read -r r; do rooms+=("$r"); done < <(subscribed_rooms)
  fi
  me=$(resolve_name "$as")
  init_colour
  sweep_now=$(date -u +%Y%m%d-%H%M%S)

  local head_on='' head_off=''
  if [ "$colour_on" = 1 ]; then head_on=$(printf '\033[1m'); head_off=$(printf '\033[0m'); fi

  for r in ${rooms[@]+"${rooms[@]}"}; do
    use_room "$r"
    [ -d "$posts_dir" ] || continue
    cursor=$(cursor_get "$room" "$me")
    local new=()
    while IFS= read -r id; do
      if [ -z "$cursor" ] || [ "$id" \> "$cursor" ]; then new+=("$id"); fi
    done < <(settled_ids)
    [ ${#new[@]} -gt 0 ] || continue
    newest=${new[${#new[@]}-1]}

    printf '\n%s══ %s · %s new ══%s\n' "$head_on" "$room" "${#new[@]}" "$head_off"
    for id in "${new[@]}"; do render_post "$id"; done
    shown=$((shown + ${#new[@]}))

    if ! cursor_put "$room" "$me" "$newest"; then
      printf 'moot: cannot write %s (read-only room); the next --new will show these again\n' \
        ".moot/seen/$room/$me" >&2
    fi
  done

  if [ "$shown" = 0 ]; then printf 'nothing new for %s\n' "$me"; else printf '\n'; fi
}

cmd_read() {
  local since= tail_n= follow=0 room_opt= id last= new=0 as=

  while [ $# -gt 0 ]; do
    case $1 in
      --room)  [ $# -ge 2 ] || die "--room needs a room"; room_opt=$2; shift 2 ;;
      --since) [ $# -ge 2 ] || die "--since needs a post id"; since=$2; shift 2 ;;
      --tail)  [ $# -ge 2 ] || die "--tail needs a count"; tail_n=$2; shift 2
               case $tail_n in ''|*[!0-9]*) die "--tail needs a number" ;; esac ;;
      --follow) follow=1; shift ;;
      --new)   new=1; shift ;;
      --as)    [ $# -ge 2 ] || die "--as needs a name"; as=$2; shift 2 ;;
      -h|--help) usage; return 0 ;;
      *) die "unknown option for read: $1" ;;
    esac
  done

  if [ "$new" = 1 ]; then
    [ -z "$since$tail_n" ] && [ "$follow" = 0 ] \
      || die "--new cannot be combined with --since, --tail or --follow: its cursor decides what is new"
    read_new "$as" "$room_opt"
    return 0
  fi
  [ -z "$as" ] || die "--as only goes with --new"

  use_room "$room_opt"
  [ -d "$posts_dir" ] || die "no posts/ in room $room (run: $0 join $room)"
  init_colour

  local ids=() shown=()
  while IFS= read -r id; do ids+=("$id"); done < <(post_ids)

  # --since is exclusive: it is a cursor pointing at the last post already read.
  if [ -n "$since" ]; then
    local keep=() seen_it=0
    for id in ${ids[@]+"${ids[@]}"}; do
      if [ "$seen_it" = 1 ]; then keep+=("$id")
      elif [ "$id" = "$since" ]; then seen_it=1
      elif [ "$id" \> "$since" ]; then keep+=("$id"); fi
    done
    ids=(${keep[@]+"${keep[@]}"})
  fi

  if [ -n "$tail_n" ] && [ ${#ids[@]} -gt "$tail_n" ]; then
    ids=("${ids[@]:$((${#ids[@]} - tail_n))}")
  fi

  for id in ${ids[@]+"${ids[@]}"}; do
    render_post "$id"
    last=$id
  done
  [ ${#ids[@]} -gt 0 ] && printf '\n'

  [ "$follow" = 1 ] || return 0

  # Poll and append, so a human can watch a live moot with no other tooling.
  # There is nothing to notify us: a moot is a directory, and it may be
  # arriving over rsync or a sync folder.
  while :; do
    sleep "${MOOT_FOLLOW_INTERVAL:-2}"
    shown=()
    while IFS= read -r id; do shown+=("$id"); done < <(post_ids)
    for id in ${shown[@]+"${shown[@]}"}; do
      if [ -z "$last" ] || [ "$id" \> "$last" ]; then
        render_post "$id"
        last=$id
      fi
    done
  done
}

# ---------------------------------------------------------------- catchup

# The mentions in a post body, one per line, trailing sentence punctuation
# trimmed. This is the only place the tool looks inside a post for meaning, and
# it happens entirely reader-side: the board does not route, index, or validate
# an @.
mentions_in() {
  [ -r "$1" ] || return 0
  grep -oE '@[A-Za-z0-9._-]+' -- "$1" 2>/dev/null \
    | sed -E 's/[._-]+$//' \
    | sed -E 's/^@//' \
    | sort -u
}

post_mentions_me() {
  local body=$1 me=$2 m
  while IFS= read -r m; do
    [ "$m" = "$me" ] && return 0
    [ "$m" = all ] && return 0
  done < <(mentions_in "$body")
  return 1
}

# A delivered item carries the room it came from, the path to it, and its own
# post id, not just the body. A cursor may have advanced silently past thirty
# announcements before one asks for something, so the recipient needs to be
# able to read backwards on demand — pull, not push. The board is right there.
deliver_post() {
  local id=$1 dir=$2 body out landing day time sender rest
  day=${id%%-*}; rest=${id#*-}
  time=${rest%%-*}; sender=${rest#*-}
  body=$(post_body_path "$id")
  # The room is in the filename as well as the id. Two rooms can produce the
  # same id in the same second from the same sender, and the filename is the
  # whole duplicate-suppression mechanism.
  out="$dir/moot-$room-$id.md"

  # The post id is in the filename, so a re-run delivers nothing twice even if
  # the cursor could not be written.
  [ -e "$out" ] && return 1

  landing="$dir/.moot-$room-$id.$$.landing"
  {
    printf '# moot mention · %s · %s · %s-%s-%s %s:%s:%s UTC\n\n' \
      "$room" "$sender" "${day:0:4}" "${day:4:2}" "${day:6:2}" \
      "${time:0:2}" "${time:2:2}" "${time:4:2}"
    printf -- '- room: `%s`\n' "$room"
    printf -- '- moot: `%s`\n' "$room_dir"
    printf -- '- post: `%s`\n' "$id"
    printf -- '- read back: `%s read --room %s --tail 20`\n\n' "$moot_dir/moot.sh" "$room"
    printf -- '---\n\n'
    if [ -r "$body" ]; then cat -- "$body"; else printf '(no post.md in posts/%s)\n' "$id"; fi
    if [ -d "$posts_dir/$id" ]; then
      local f names=()
      for f in "$posts_dir/$id"/*; do
        [ -e "$f" ] || continue
        [ "${f##*/}" = post.md ] && continue
        names+=("$posts_dir/$id/${f##*/}")
      done
      [ ${#names[@]} -gt 0 ] && printf '\nattached:\n%s\n' "$(printf -- '- `%s`\n' "${names[@]}")"
    fi
  } > "$landing"
  mv -- "$landing" "$out"
  return 0
}

# One room's worth of the sweep: deliver what mentions me, advance the cursor.
# Appends to the sweep's accumulators rather than reporting, because the caller
# reports once however many rooms it visited.
catchup_room() {
  local me=$1 deliver=$2 json=$3 id
  local cursor; cursor=$(cursor_get "$room" "$me")

  local new=() newest=
  while IFS= read -r id; do
    if [ -z "$cursor" ] || [ "$id" \> "$cursor" ]; then new+=("$id"); fi
  done < <(settled_ids)
  [ ${#new[@]} -gt 0 ] && newest=${new[${#new[@]}-1]}

  local mine=0
  for id in ${new[@]+"${new[@]}"}; do
    # No mention: advance past it silently. Still readable with `read`,
    # interrupts nobody.
    post_mentions_me "$(post_body_path "$id")" "$me" || continue
    if [ -n "$deliver" ]; then
      deliver_post "$id" "$deliver" || continue
    else
      [ "$json" = 1 ] || render_post "$id"
    fi
    sweep_delivered+=("$room/$id")
    mine=$((mine + 1))
  done

  # Advance the cursor past everything swept, mentioned or not (settled_ids
  # leaves the current second for the next sweep). The cursor is
  # this participant's own state and never travels with the room, so two
  # divergent copies reconcile on posts/ alone.
  local cursor_written=0
  if [ -n "$newest" ]; then
    if cursor_put "$room" "$me" "$newest"; then
      cursor_written=1
    else
      # A room reachable read-only is a normal way to run: delivery is still
      # correct, because delivered filenames carry the room and the post id.
      # The sweep goes on to the next room — one read-only room must not stop
      # the rooms after it.
      printf 'moot: cannot write %s (read-only room); nothing was delivered twice anyway\n' \
        ".moot/seen/$room/$me" >&2
    fi
  fi
  [ "$cursor_written" = 1 ] && sweep_changed=1
  [ "$mine" -gt 0 ] && sweep_changed=1

  sweep_reports+=("$(printf '{"room":"%s","since":%s,"cursor":%s,"cursor_written":%s,"scanned":%s,"delivered":%s}' \
    "$(json_escape "$room")" \
    "$([ -n "$cursor" ] && printf '"%s"' "$(json_escape "$cursor")" || printf null)" \
    "$([ -n "${newest:-$cursor}" ] && printf '"%s"' "$(json_escape "${newest:-$cursor}")" || printf null)" \
    "$([ "$cursor_written" = 1 ] && echo true || echo false)" \
    "${#new[@]}" "$mine")")
  return 0
}

# catchup is the one verb that is not aimed. post and read say a thing or look
# at a thing somewhere, so they resolve to a single room; catchup asks "is
# there anything for me", and the answer spans everything subscribed. Hence no
# --all flag: all is the default, and --room narrows.
cmd_catchup() {
  local json=0 as= room_opt= deliver= r

  [ "${1:-}" = --json ] && { json=1; shift; }

  while [ $# -gt 0 ]; do
    case $1 in
      --as)      [ $# -ge 2 ] || die "--as needs a name"; as=$2; shift 2 ;;
      --room)    [ $# -ge 2 ] || die "--room needs a room"; room_opt=$2; shift 2 ;;
      --deliver) [ $# -ge 2 ] || die "--deliver needs a directory"; deliver=$2; shift 2 ;;
      -h|--help) usage; return 0 ;;
      *) die "unknown option for catchup: $1" ;;
    esac
  done

  local rooms=()
  if [ -n "$room_opt" ]; then
    check_segment 'room name' "$room_opt"
    [ -d "$rooms_dir/$room_opt" ] || die "no room $room_opt here (run: $0 join $room_opt)"
    rooms=("$room_opt")
  else
    while IFS= read -r r; do rooms+=("$r"); done < <(subscribed_rooms)
  fi

  local me; me=$(resolve_name "$as")

  if [ -n "$deliver" ]; then
    mkdir -p -- "$deliver" || die "cannot use deliver directory $deliver"
    deliver=$(cd -- "$deliver" && pwd)
  fi

  [ "$json" = 1 ] || init_colour

  sweep_delivered=()
  sweep_reports=()
  sweep_changed=0
  sweep_now=$(date -u +%Y%m%d-%H%M%S)
  for r in ${rooms[@]+"${rooms[@]}"}; do
    use_room "$r"
    # Reader-initiated pull. catchup is already the verb that asks "is there
    # anything for me", so the fetch belongs here and nowhere else. A fetch
    # that fails is not a failed catchup: the room is a directory, and the
    # directory is still readable.
    if room_is_clone; then
      if git_room_fetch; then
        # Anything local that the rebase kept is a backlog from a post made
        # while the remote was unreachable. This is where it drains.
        if [ "$(git_room rev-parse HEAD 2>/dev/null)" \
             != "$(git_room rev-parse FETCH_HEAD 2>/dev/null)" ]; then
          git_room_push || true
        fi
      else
        printf 'moot: could not fetch %s; reading what is here\n' "$r" >&2
      fi
    fi
    [ -d "$posts_dir" ] || continue
    catchup_room "$me" "$deliver" "$json"
  done

  if [ "$json" = 1 ]; then
    # One command, one object. The sweep is a single question — "is there
    # anything for me" — so it gets a single answer, and every delivered item
    # names its room so a caller can act on it without parsing a filename.
    local list= sep= item
    for item in ${sweep_delivered[@]+"${sweep_delivered[@]}"}; do
      list="$list$sep$(printf '{"room":"%s","id":"%s"}' \
        "$(json_escape "${item%%/*}")" "$(json_escape "${item#*/}")")"
      sep=,
    done
    local reports= rsep= rep
    for rep in ${sweep_reports[@]+"${sweep_reports[@]}"}; do
      reports="$reports$rsep$rep"; rsep=,
    done
    printf '{"schema_version":2,"command":"catchup","ok":true,"changed":%s,"sender":"%s","rooms":[%s],"delivered":[%s]}\n' \
      "$([ "$sweep_changed" = 1 ] && echo true || echo false)" \
      "$(json_escape "$me")" "$reports" "$list"
  elif [ ${#sweep_delivered[@]} -gt 0 ]; then
    if [ -n "$deliver" ]; then
      # One heartbeat line however many rooms it swept.
      printf 'delivered %s mention(s) to %s\n' "${#sweep_delivered[@]}" "$deliver"
    else
      printf '\n'
    fi
  elif [ -n "$deliver" ]; then
    # Zero subscribed rooms is a normal state for a host that has installed
    # moot and joined nothing, and a heartbeat must not spew.
    printf 'nothing for %s\n' "$me"
  fi
}

# ---------------------------------------------------------------- dispatch

case ${1:-help} in
  init) shift; cmd_init "$@" ;;
  join) shift; cmd_join "$@" ;;
  subscribe) shift; cmd_subscribe "$@" ;;
  rooms) shift; cmd_rooms "$@" ;;
  post) shift; cmd_post "$@" ;;
  read) shift; cmd_read "$@" ;;
  catchup) shift; cmd_catchup "$@" ;;
  help|-h|--help) usage ;;
  *) usage >&2; die "unknown command: $1" ;;
esac
