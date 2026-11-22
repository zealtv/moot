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

# A room is a folder under rooms/, and posts/ is all of it. A room lives with its
# keeper as a real folder; everyone else holds a link there.
rooms_dir="$moot_dir/rooms"

# The cursor is mine, not the room's, so it lives beside rooms/ rather than
# inside one. Keyed by room and then by name, so each cursor has one writer.
seen_dir="$moot_dir/seen"

# Set by use_room(); every verb that is aimed at one room resolves first.
room=
room_dir=
posts_dir=

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

  moot.sh create <room>
  moot.sh join <path-to-room>
  moot.sh leave <room>
  moot.sh archive <room>
  moot.sh dm <dir-or-name>
  moot.sh status [-m <text>]
  moot.sh rooms
  moot.sh post [--json] [--as <name>] [--room <name>] [-m <text> | -f <file> | -]
  moot.sh read [--room <name>] [--since <post-id>] [--tail <n>]
  moot.sh read --new [--as <name>] [--room <name>] [--mentions] [--deliver <dir>]
  moot.sh watch [--as <name>] [--room <name>]... [--mentions] [--interval <s>]

A post is <YYYYMMDD>-<HHMMSS>-<sender>.md in rooms/<room>/posts/, UTC, plain
Markdown. Posts are immutable: there is no edit and no delete. A correction is
a new post.

A room lives with its keeper, as a real folder in the keeper's .moot/rooms/.
create makes one here (or: mkdir -p .moot/rooms/<room>/posts); join links to
one someone else keeps, and never makes one; leave removes a link. archive
closes a room you keep as rooms/<room>.archived: it still reads, and posting is
closed. dm finds or starts the one room, dm-<a>-<b>, for you and another.

post and read are aimed at one room; read --new and watch cover every live room
here unless --room narrows them. read --new prints every post since my cursor (only
the ones that mention me with --mentions, or written to <dir> with --deliver)
and moves the cursor. watch waits for a new post from someone else, prints
room/id, and exits; it never moves the cursor. watch --room (repeatable) hears
those rooms fully; with --mentions it also hears mentions in the others. read prints times in local time;
the filenames stay UTC.
USAGE
}

# ---------------------------------------------------------------- name resolution

# --as, then $MOOT_NAME, then .moot/name, then the sibling .gremlin/name, then
# the name of the folder .moot/ sits in. Nobody is obliged to have a name file:
# every step reads something that already exists, and a repo's checkout is
# named after the repo on every machine.

moot_name() {
  local file="${1:-$moot_dir}/name"
  [ -r "$file" ] || return 1
  head -n 1 -- "$file" | tr -d '[:space:]'
}

# .gremlin/name is a key=value file (name=alice, source=generated), so take the
# field rather than the line. An older bare-name file has no =, and still
# resolves. Read as a sibling of .moot/, the way every other primitive in the
# family reads its neighbours: a fixed path from the script's own location, so
# the answer does not depend on the working directory and no stray .gremlin/ in
# some ancestor can be picked up by accident. A .moot/ with no .gremlin/ beside
# it is not part of a gremlin, and the rest of the chain is the honest answer.
gremlin_name() {
  local file="${1:-$moot_dir}/../.gremlin/name" value
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

# The name a .moot/ gives itself from its own files, with no --as or
# $MOOT_NAME: .moot/name, the sibling .gremlin/name, then its folder. Both sides
# of a DM are named this way, so both compute the same room.
own_name() {
  local dir=${1:-$moot_dir} name=
  if name=$(moot_name "$dir") && [ -n "$name" ]; then
    :
  elif name=$(gremlin_name "$dir") && [ -n "$name" ]; then
    :
  else
    # The host folder, read from the script's own location like .gremlin/name,
    # so the working directory never comes into it.
    name=$(cd -- "$dir/.." && pwd); name=${name##*/}
    case $name in
      *[!A-Za-z0-9._-]* | .* | '')
        die "folder name '$name' is not a filename-safe sender; write one to .moot/name or pass --as <name>" ;;
    esac
  fi
  check_segment 'sender name' "$name"
  printf '%s' "$name"
}

resolve_name() {
  local as=${1:-} name=
  if [ -n "$as" ]; then
    name=$as
  elif [ -n "${MOOT_NAME:-}" ]; then
    name=$MOOT_NAME
  else
    name=$(own_name) || exit 1
  fi
  check_segment 'sender name' "$name"
  printf '%s' "$name"
}

# ---------------------------------------------------------------- room resolution

# Rooms here: whatever is a folder under rooms/, real or linked (one that arrived
# by copy is heard by being there). Live rooms in name order, then archived ones,
# which `subscribed_rooms live` leaves out.
subscribed_rooms() {
  local want=${1:-all} entry base pass
  [ -d "$rooms_dir" ] || return 0
  for pass in live archived; do
    [ "$pass" = live ] || [ "$want" = all ] || return 0
    for entry in "$rooms_dir"/*; do
      [ -d "$entry" ] || continue
      base=${entry##*/}
      case $base in
        .*) continue ;;
        *.archived) [ "$pass" = archived ] || continue ;;
        *) [ "$pass" = live ] || continue ;;
      esac
      printf '%s\n' "$base"
    done
  done
}

is_archived() { case $1 in *.archived) return 0 ;; esac; return 1; }

room_hint() { printf 'keep one with: mkdir -p .moot/rooms/<room>/posts; hear one with: %s join <path-to-room>' "$0"; }

# The room a name means, left in $room: itself, or once its keeper has closed it
# its archived form, so --room ops still finds ops.archived.
named_room() {
  room=$1
  check_segment 'room name' "$room"
  if [ ! -e "$rooms_dir/$room" ] && [ ! -L "$rooms_dir/$room" ] && [ -d "$rooms_dir/$room.archived" ]; then
    room=$room.archived
  fi
}

# Resolve the room a post or plain read is aimed at, and point posts_dir at it:
# --room, or the sole live room here. Several and none chosen is an error that
# lists them.
use_room() {
  local want=${1:-} rooms=() r
  if [ -n "$want" ]; then
    named_room "$want"
  else
    while IFS= read -r r; do rooms+=("$r"); done < <(subscribed_rooms live)
    case ${#rooms[@]} in
      0) die "no rooms here yet; $(room_hint)" ;;
      1) room=${rooms[0]} ;;
      *)
        printf 'moot: several rooms here and none chosen:\n' >&2
        printf '  %s\n' "${rooms[@]}" >&2
        printf 'Pick one with --room <room>\n' >&2
        exit 1 ;;
    esac
  fi
  room_dir="$rooms_dir/$room"
  posts_dir="$room_dir/posts"
}

# The rooms a pass covers: --room's one, or every live room here. Called in the
# main shell first, so that a bad --room stops the command (a die inside a
# process substitution would not); it leaves the room found in $room.
check_room_opt() {
  named_room "$1"
  [ -d "$rooms_dir/$room" ] || die "no room $1 here; $(room_hint)"
}
pass_rooms() {
  if [ -n "$1" ]; then printf '%s\n' "$1"; else subscribed_rooms live; fi
}

# ---------------------------------------------------------------- link repair

# Every command but help starts here (README, "Link repair"): for each link in
# rooms/ that leads nowhere, follow the one rename with its cursor folder, or
# drop a link to an archived room that has gone, or leave it for rooms to report.
# Built-in tests, and readlink only for a link that dangles, so it is cheap.
repair_links() {
  local entry name target new to there
  [ -d "$rooms_dir" ] || return 0
  for entry in "$rooms_dir"/*; do
    [ -L "$entry" ] && [ ! -e "$entry" ] || continue
    name=${entry##*/}
    target=$(readlink -- "$entry") || continue
    target=${target%/}
    if is_archived "$name"; then new=${name%.archived}; else new=$name.archived; fi
    if is_archived "$target"; then to=${target%.archived}; else to=$target.archived; fi
    case $to in /*) there=$to ;; *) there=$rooms_dir/$to ;; esac
    if [ -d "$there/posts" ]; then
      [ ! -e "$rooms_dir/$new" ] && [ ! -L "$rooms_dir/$new" ] || continue
      ln -s -- "$to" "$rooms_dir/$new" 2>/dev/null || [ -L "$rooms_dir/$new" ] || continue
      rm -f -- "$entry"
      if [ -d "$seen_dir/$name" ] && [ ! -e "$seen_dir/$new" ]; then
        mv -- "$seen_dir/$name" "$seen_dir/$new" 2>/dev/null || true
      fi
      if is_archived "$new"; then
        printf 'moot: rooms/%s is archived, now rooms/%s (read --new --room %s shows the rest)\n' "$name" "$new" "$new" >&2
      else
        printf 'moot: rooms/%s is open again, now rooms/%s\n' "$name" "$new" >&2
      fi
    elif is_archived "$name"; then
      case $target in /*) there=$target ;; *) there=$rooms_dir/$target ;; esac
      [ -d "${there%/*}" ] || continue
      rm -f -- "$entry"
      rm -rf -- "${seen_dir:?}/$name"
      printf 'moot: rooms/%s has gone from its keeper; removed the link and its cursor\n' "$name" >&2
    fi
  done
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

# What a pass (read --new) may read: stamped ids in order, leaving out
# any stamped in the current UTC second or later. The cursor is the newest id
# scanned, so a pass that moved it onto the current second would never show a
# post that lands later in that same second under a name sorting lower (ben
# after carol). Such a post waits for the next pass, and so does one stamped
# by a clock ahead of mine. $pass_now is read once per pass. Ids that are not
# stamps are left out: sorting after every stamp, one would park the cursor
# past every post still to come.
pass_now=
settled_ids() {
  local id
  while IFS= read -r id; do
    is_stamp_id "$id" || continue
    [ "${id:0:15}" \< "$pass_now" ] || continue
    printf '%s\n' "$id"
  done < <(post_ids)
}

# ---------------------------------------------------------------- join and rooms

# relative_path <from-dir> <to-path>: the path that leads from one to the other,
# both absolute and physical. A link written this way resolves the same from any
# sibling checkout or worktree.
relative_path() {
  local from=${1%/} to=${2%/} up=
  while [ "${to#"$from"/}" = "$to" ]; do
    from=${from%/*}; up="../$up"
  done
  printf '%s%s' "$up" "${to#"$from"/}"
}

# join only ever makes a link. A room lives with its keeper, as a real folder in
# the keeper's .moot/rooms/; everyone else holds a link to it. join never makes
# a room, so a typo cannot make a private one that nobody else reads.
cmd_join() {
  local target= name= real rooms_real rel link me
  while [ $# -gt 0 ]; do
    case $1 in
      -h|--help) usage; return 0 ;;
      -*) die "unknown option for join: $1" ;;
      *) [ -z "$target" ] || die "join takes one path"; target=$1; shift ;;
    esac
  done
  [ -n "$target" ] || die "join needs the path to a room"
  [ -d "$target/posts" ] \
    || die "'$target' is not a room (no posts/ folder in it). join links to a room someone keeps; to keep one yourself: mkdir -p .moot/rooms/<room>/posts"

  real=$(cd -P -- "$target" && pwd -P)
  name=${target%/}; name=${name##*/}
  case $name in .|..|'') name=${real##*/} ;; esac
  check_segment 'room name' "$name"

  mkdir -p -- "$rooms_dir"
  rooms_real=$(cd -P -- "$rooms_dir" && pwd -P)
  link="$rooms_dir/$name"
  if [ "$link" -ef "$real" ]; then
    printf 'already in rooms/%s\n' "$name"; return 0
  fi
  if [ -L "$link" ]; then
    die "rooms/$name is already a link to $(readlink -- "$link"); remove it first (rm .moot/rooms/$name) to point it elsewhere"
  elif [ -e "$link" ]; then
    die "rooms/$name is a room kept here (a real folder); join links to rooms others keep"
  fi
  name_free "$name"
  # A DM is for its pair: the joiner must be one of its two names.
  case ${name%.archived} in
    dm-*)
      me=$(own_name) || exit 1
      case ${name%.archived} in
        "dm-$me-"?* | "dm-"?*"-$me") ;;
        *) die "rooms/$name is a direct message for two others; only its pair joins it" ;;
      esac ;;
  esac

  rel=$(relative_path "$rooms_real" "$real")
  ln -s -- "$rel" "$link"
  printf 'joined rooms/%s -> %s\n' "$name" "$rel"
}

# ops and ops.archived are one name: refuse either while the other is here.
name_free() {
  local n other
  if is_archived "$1"; then other=${1%.archived}; else other=$1.archived; fi
  for n in "$1" "$other"; do
    if [ -e "$rooms_dir/$n" ] || [ -L "$rooms_dir/$n" ]; then die "rooms/$n is already here"; fi
  done
}

# The one argument a room verb takes.
one_room() {
  local verb=$1; shift
  case ${1:-} in
    -h|--help) usage; exit 0 ;;
    -*) die "unknown option for $verb: $1" ;;
    '') die "$verb needs a room" ;;
  esac
  [ $# -eq 1 ] || die "$verb takes one room"
  arg=$1
}

cmd_create() {
  local arg; one_room create "$@"
  check_segment 'room name' "$arg"
  case $arg in
    dm-*) die "dm- names are kept for direct messages; start one with: $0 dm <who>" ;;
    *.archived) die "names ending .archived are kept for archived rooms" ;;
  esac
  name_free "$arg"
  mkdir -p -- "$rooms_dir/$arg/posts"
  : > "$rooms_dir/$arg/posts/.gitkeep"
  printf 'created rooms/%s\n' "$arg"
}

# leave removes a link and its cursor, and never a real folder.
cmd_leave() {
  local arg; one_room leave "$@"
  named_room "$arg"
  if [ -L "$rooms_dir/$room" ]; then
    rm -f -- "$rooms_dir/$room"
    rm -rf -- "${seen_dir:?}/$room"
    printf 'left rooms/%s\n' "$room"
  elif [ -e "$rooms_dir/$room" ]; then
    die "rooms/$room is kept here (a real folder); leave removes only a link"
  else
    die "no room $room here"
  fi
}

# archive renames a room kept here, and its own cursor folder with it. Hearers'
# links follow at their next command, by link repair.
cmd_archive() {
  local arg dir; one_room archive "$@"
  named_room "$arg"
  dir="$rooms_dir/$room"
  case ${room%.archived} in dm-*) die "rooms/$room is a direct message, and a DM is never archived; its hearer can leave it" ;; esac
  if [ -L "$dir" ] && [ ! -e "$dir" ]; then
    die "rooms/$room leads nowhere; leave it with: $0 leave $room"
  elif [ ! -d "$dir" ]; then
    die "no room $room here"
  elif is_archived "$room"; then
    printf 'already archived rooms/%s\n' "$room"; return 0
  elif [ -L "$dir" ]; then
    die "rooms/$room is heard here, not kept; only its keeper archives it, at $(cd -P -- "$dir" && pwd -P)"
  fi
  [ ! -e "$dir.archived" ] && [ ! -L "$dir.archived" ] || die "rooms/$room.archived is already here"
  mv -- "$dir" "$dir.archived"
  if [ -d "$seen_dir/$room" ] && [ ! -e "$seen_dir/$room.archived" ]; then
    mv -- "$seen_dir/$room" "$seen_dir/$room.archived"
  fi
  printf 'archived rooms/%s.archived\n' "$room"
}

cmd_rooms() {
  local r any=0 entry
  [ "${1:-}" = -h ] || [ "${1:-}" = --help ] && { usage; return 0; }
  [ $# -eq 0 ] || die "rooms takes no arguments"
  while IFS= read -r r; do
    any=1
    printf '%s\n' "$r"
  done < <(subscribed_rooms)
  # What link repair left alone: where each leads, and how to let it go.
  for entry in "$rooms_dir"/*; do
    [ -L "$entry" ] && [ ! -e "$entry" ] || continue
    printf 'moot: rooms/%s leads nowhere (%s); leave it with: %s leave %s\n' \
      "${entry##*/}" "$(readlink -- "$entry")" "$0" "${entry##*/}" >&2
  done
  [ "$any" = 1 ] || printf 'no rooms here yet: keep one with mkdir -p .moot/rooms/<room>/posts, or hear one with %s join <path-to-room>\n' "$0"
}

# ---------------------------------------------------------------- post

cmd_post() {
  local json=0 as= room_opt= body= have_body=0 stamp base target landing n

  while [ $# -gt 0 ]; do
    case $1 in
      --json) json=1; shift ;;
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
  [ -d "$posts_dir" ] || die "no room $room here; $(room_hint)"
  ! is_archived "$room" || die "${room%.archived} is archived; posting is closed"

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

  if [ "$json" = 1 ]; then
    printf '{"schema_version":1,"command":"post","ok":true,"changed":true,"room":"%s","id":"%s","path":"%s","sender":"%s","timestamp":"%s"}\n' \
      "$(json_escape "$room")" \
      "$(json_escape "$base")" "$(json_escape "rooms/$room/posts/$base.md")" \
      "$(json_escape "$sender")" "$(json_escape "$stamp")"
  else
    printf 'posted rooms/%s/posts/%s.md\n' "$room" "$base"
  fi
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
# such ids have a time to show, and only such ids are read by a pass of read
# --new; anything else in posts/ (a stray README.md, say) is still listed by
# plain read, under its own name.
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

# The cursor, written by read --new: .moot/seen/<room>/<name>, one
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

# read --new, the one catch-up verb: everything since this reader's cursor, room
# by room, then the cursor moves. Rooms stay separate, each under its own
# heading; there is no merged timeline. By default every new post prints,
# mentions highlighted as read always does. --mentions keeps only the posts that
# mention me (the cursor still moves past the rest). --deliver <dir> writes
# those posts as files instead of printing, and implies --mentions.
read_new() {
  local as=$1 room_opt=$2 mentions=$3 deliver=$4 r me id cursor newest
  local shown=0 rooms=()
  if [ -n "$room_opt" ]; then check_room_opt "$room_opt"; room_opt=$room; fi
  while IFS= read -r r; do rooms+=("$r"); done < <(pass_rooms "$room_opt")
  me=$(resolve_name "$as")

  if [ -n "$deliver" ]; then
    mentions=1
    mkdir -p -- "$deliver" || die "cannot use deliver directory $deliver"
    deliver=$(cd -- "$deliver" && pwd)
  else
    init_colour
  fi
  pass_now=$(date -u +%Y%m%d-%H%M%S)

  local head_on='' head_off=''
  if [ "$colour_on" = 1 ]; then head_on=$(printf '\033[1m'); head_off=$(printf '\033[0m'); fi

  for r in ${rooms[@]+"${rooms[@]}"}; do
    use_room "$r"
    [ -d "$posts_dir" ] || continue
    cursor=$(cursor_get "$room" "$me")
    local new=() picked=()
    while IFS= read -r id; do
      if [ -z "$cursor" ] || [ "$id" \> "$cursor" ]; then new+=("$id"); fi
    done < <(settled_ids)
    [ ${#new[@]} -gt 0 ] || continue
    newest=${new[${#new[@]}-1]}

    for id in "${new[@]}"; do
      if [ "$mentions" = 0 ] || counts_for_me "$id" "$me"; then picked+=("$id"); fi
    done

    if [ -n "$deliver" ]; then
      for id in ${picked[@]+"${picked[@]}"}; do
        deliver_post "$id" "$deliver" && shown=$((shown + 1))
      done
    elif [ ${#picked[@]} -gt 0 ]; then
      printf '\n%s══ %s · %s %s ══%s\n' "$head_on" "$room" "${#picked[@]}" \
        "$([ "$mentions" = 1 ] && echo "for $me" || echo new)" "$head_off"
      for id in "${picked[@]}"; do render_post "$id"; done
      shown=$((shown + ${#picked[@]}))
    fi

    # A room reachable read-only is a normal way to run. It still reads, the
    # pass goes on to the next room, and delivered filenames carry the room and
    # post id, so a repeat delivers nothing twice.
    if ! cursor_put "$room" "$me" "$newest"; then
      printf 'moot: cannot write %s (read-only room); the next --new will repeat these\n' \
        ".moot/seen/$room/$me" >&2
    fi
  done

  if [ "$shown" = 0 ]; then
    printf 'nothing new for %s\n' "$me"
  elif [ -n "$deliver" ]; then
    printf 'delivered %s mention(s) to %s\n' "$shown" "$deliver"   # one heartbeat line
  else
    printf '\n'
  fi
}


cmd_read() {
  local since= tail_n= room_opt= id new=0 as= mentions=0 deliver=

  while [ $# -gt 0 ]; do
    case $1 in
      --room)  [ $# -ge 2 ] || die "--room needs a room"; room_opt=$2; shift 2 ;;
      --since) [ $# -ge 2 ] || die "--since needs a post id"; since=$2; shift 2 ;;
      --tail)  [ $# -ge 2 ] || die "--tail needs a count"; tail_n=$2; shift 2
               case $tail_n in ''|*[!0-9]*) die "--tail needs a number" ;; esac ;;
      --new)   new=1; shift ;;
      --as)    [ $# -ge 2 ] || die "--as needs a name"; as=$2; shift 2 ;;
      --mentions) mentions=1; shift ;;
      --deliver)  [ $# -ge 2 ] || die "--deliver needs a directory"; deliver=$2; shift 2 ;;
      -h|--help) usage; return 0 ;;
      *) die "unknown option for read: $1" ;;
    esac
  done

  if [ "$new" = 1 ]; then
    [ -z "$since$tail_n" ] \
      || die "--new cannot be combined with --since or --tail: its cursor decides what is new"
    read_new "$as" "$room_opt" "$mentions" "$deliver"
    return 0
  fi
  [ -z "$as$deliver" ] && [ "$mentions" = 0 ] || die "--as, --mentions and --deliver only go with --new"

  use_room "$room_opt"
  [ -d "$posts_dir" ] || die "no room $room here; $(room_hint)"
  init_colour

  local ids=()
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

  for id in ${ids[@]+"${ids[@]}"}; do render_post "$id"; done
  if [ ${#ids[@]} -gt 0 ]; then printf '\n'; fi
}

# ---------------------------------------------------------------- mentions and delivery

# The mentions in a post body, one per line, trailing sentence punctuation
# trimmed. This is the only place the tool looks inside a post for meaning, and
# it happens entirely reader-side: the board does not route, index, or validate
# an @.
#
# Code is not a mention: an @ inside a fenced block (``` or ~~~) or an inline
# code span is text about a mention, so a post can say `@all` without costing
# everyone a turn. The awk drops fenced lines and backtick spans before the
# match; an unclosed backtick leaves the rest of its line as it was.
mentions_in() {
  [ -r "$1" ] || return 0
  awk '/^[ \t]*(```|~~~)/ { fence = !fence; next }
       !fence { gsub(/`[^`]*`/, ""); print }' "$1" 2>/dev/null \
    | grep -oE '@[A-Za-z0-9._-]+' 2>/dev/null \
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

# Does post <id> in $room count as a mention of me? In a dm- room every post from
# the other side does, so a DM always reaches its reader; elsewhere, an @ of me
# or @all.
counts_for_me() {
  case ${room%.archived} in dm-*) id_is_from "$1" "$2" || return 0 ;; esac
  post_mentions_me "$(post_body_path "$1")" "$2"
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

# ---------------------------------------------------------------- watch

# watch is a one-shot wait for a session that has no heartbeat: it blocks until
# a post lands that the session would want to see, prints one line per post,
# and exits. The exit is the push. The session catches up, then starts the
# watch again. It never touches seen/: read --new stays the cursor's
# only writer, so pausing, stopping or restarting a watch loses nothing.
#
# Two plain files beside rooms/, both this machine's and never committed:
#   watching       held while a watch runs (pid, name, rooms, start time), so
#                  there is one watcher per .moot/; a stale one is taken over.
#   watch.paused   present: the watch fires on nothing. Removed: it carries on
#                  from the newest post, so whatever landed while paused waits
#                  for the next read --new instead of firing (a quiet unpause).

watch_file="$moot_dir/watching"
pause_file="$moot_dir/watch.paused"

# The pid of a process's parent, or nothing if it is gone or ps cannot say.
ppid_of() {
  local p
  p=$(ps -o ppid= -p "$1" 2>/dev/null) || return 0
  printf '%s' "${p//[[:space:]]/}"
}

# Is this pid a moot watch for this .moot/? A pid in watching may have been
# recycled by an unrelated process, which must never be waited on or signalled.
# Its command line has to name a moot.sh (this one's path, in either its
# logical or physical form, or a relative one) and the word watch. Without ps
# there is no way to tell, so the holder is taken at its word.
is_this_watch() {
  local cmd w this=0 watch=0 physical
  command -v ps >/dev/null 2>&1 || return 0
  # kill -0 has shown the pid is alive: if ps cannot say more, take it as live.
  cmd=$(ps -o command= -p "$1" 2>/dev/null) || return 0
  [ -n "$cmd" ] || return 0
  physical=$(cd -P -- "$moot_dir" && pwd)
  local words
  read -r -a words <<< "$cmd"
  for w in ${words[@]+"${words[@]}"}; do
    case $w in
      "$moot_dir/moot.sh" | "$physical/moot.sh") this=1 ;;
      /*) ;;
      moot.sh | */moot.sh) this=1 ;;
      watch) watch=1 ;;
    esac
  done
  [ "$this" = 1 ] && [ "$watch" = 1 ]
}

# Take watching atomically. noclobber makes the create fail if the file is
# there, so two watches starting at once cannot both win. A file whose pid is
# gone, or no longer a moot watch for this .moot/ (the pid was recycled), is
# stale (a session that died without its trap), and is taken over, unsignalled. A
# holder that is alive gets up to about 2 s to finish exiting before this watch
# gives up with exit 3, so a watch just killed does not block its restart. A
# holder whose parent is pid 1, or has changed since it started, is an orphan:
# it would exit at its next poll anyway, so it is asked to now.
watch_lock() {
  local me=$1 rooms=$2 mentions=$3 pid parent now tries=0 waited=0
  while :; do
    if ( set -o noclobber
         printf 'pid=%s\nparent=%s\nname=%s\nrooms=%s\nmentions=%s\nstarted=%s\n' \
           "$$" "$PPID" "$me" "$rooms" "$mentions" "$(date -u +%Y%m%d-%H%M%S)" > "$watch_file" ) 2>/dev/null; then
      return 0
    fi
    pid=$(sed -n 's/^pid=//p' "$watch_file" 2>/dev/null | head -n 1)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && is_this_watch "$pid"; then
      if [ "$waited" -eq 0 ]; then
        parent=$(sed -n 's/^parent=//p' "$watch_file" 2>/dev/null | head -n 1)
        now=$(ppid_of "$pid")
        if [ -n "$now" ] && { [ "$now" = 1 ] || { [ -n "$parent" ] && [ "$now" != "$parent" ]; }; }; then
          kill "$pid" 2>/dev/null || true
        fi
      fi
      if [ "$waited" -ge 10 ]; then
        printf 'moot: another watch holds .moot/watching (pid %s); one watcher per .moot/. Stop it with: kill %s\n' \
          "$pid" "$pid" >&2
        exit 3
      fi
      waited=$((waited + 1))
      sleep 0.2
      continue
    fi
    tries=$((tries + 1))
    [ "$tries" -le 3 ] || die "cannot take .moot/watching"
    rm -f -- "$watch_file"
  done
}

# The sender is everything after the stamp.
id_is_from() { [ "${1:16}" = "$2" ]; }

newest_id() {
  local id last=
  while IFS= read -r id; do is_stamp_id "$id" && last=$id; done < <(post_ids)
  printf '%s' "$last"
}

cmd_watch() {
  local as= mentions=0 interval=${MOOT_WATCH_INTERVAL:-5} r i id item
  local full=()

  while [ $# -gt 0 ]; do
    case $1 in
      --as)       [ $# -ge 2 ] || die "--as needs a name"; as=$2; shift 2 ;;
      --room)     [ $# -ge 2 ] || die "--room needs a room"; full+=("$2"); shift 2 ;;
      --mentions) mentions=1; shift ;;
      --interval) [ $# -ge 2 ] || die "--interval needs seconds"; interval=$2; shift 2 ;;
      -h|--help)  usage; return 0 ;;
      *) die "unknown option for watch: $1" ;;
    esac
  done
  case $interval in ''|*[!0-9.]*) die "--interval needs a number of seconds" ;; esac

  # Which rooms are heard how. With no --room, every room, and --mentions
  # narrows all of them to mentions. With --room, those rooms fully, and
  # --mentions adds mentions from every other room; without it the others are
  # not heard. Archived rooms are heard only when --room names them. The room
  # list is read again on every poll, so a room joined while the watch runs is
  # heard from its next poll.
  local seen_opt=
  for r in ${full[@]+"${full[@]}"}; do
    check_room_opt "$r"; r=$room
    case " $seen_opt " in *" $r "*) ;; *) seen_opt="$seen_opt $r" ;; esac
  done
  [ -n "$(subscribed_rooms live)$seen_opt" ] || die "no rooms here to watch"

  local me; me=$(resolve_name "$as")

  local watch_parent=$PPID
  seen_opt=${seen_opt# }
  watch_lock "$me" "${seen_opt:-all}" "$mentions"
  sleep_pid=
  trap '[ -z "$sleep_pid" ] || kill "$sleep_pid" 2>/dev/null || true; rm -f -- "$watch_file"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  # Where each room starts: the cursor, so a post that landed after the last
  # read --new still fires; with no cursor yet, a room here at start begins at
  # its newest post, so a first watch doesn't fire on the whole history. A room
  # that appears later, with no cursor, starts from nothing, so the first post
  # of a new DM fires. Starting paused is an unpause later.
  # Parallel arrays, not an associative one: bash 3 has none.
  local known=() base=() k idx only paused=0 now first=1
  [ -e "$pause_file" ] && paused=1

  local hits=()
  while :; do
    # An orphan (its parent gone or now pid 1, so it can never wake a session)
    # exits and lets go of watching.
    now=$(ppid_of "$$")
    if [ -n "$now" ] && { [ "$now" = 1 ] || [ "$now" != "$watch_parent" ]; }; then
      printf 'moot: watch exiting: its parent (pid %s) is gone, so nothing would hear it\n' "$watch_parent" >&2
      exit 4
    fi
    # List the rooms afresh and start any new one.
    while IFS= read -r r; do
      if is_archived "$r"; then case " $seen_opt " in *" $r "*) ;; *) continue ;; esac; fi
      idx=
      for k in "${!known[@]}"; do [ "${known[$k]}" = "$r" ] && idx=$k; done
      [ -z "$idx" ] || continue
      use_room "$r"
      idx=${#known[@]}
      known[$idx]=$r
      base[$idx]=$(cursor_get "$room" "$me")
      [ -n "${base[$idx]}" ] || [ "$first" = 0 ] || base[$idx]=$(newest_id)
    done < <(subscribed_rooms)
    first=0
    if [ -e "$pause_file" ]; then
      paused=1
    else
      if [ "$paused" = 1 ]; then
        for i in "${!known[@]}"; do use_room "${known[$i]}"; base[$i]=$(newest_id); done
        paused=0
      fi
      for i in "${!known[@]}"; do
        r=${known[$i]}
        # Heard fully, heard on mentions only, or not heard.
        only=
        if [ -n "$seen_opt" ]; then
          case " $seen_opt " in *" $r "*) ;; *) [ "$mentions" = 1 ] || continue; only=1 ;; esac
        elif [ "$mentions" = 1 ]; then
          only=1
        fi
        use_room "$r"
        [ -d "$posts_dir" ] || continue
        while IFS= read -r id; do
          is_stamp_id "$id" || continue
          [ -z "${base[$i]}" ] || [ "$id" \> "${base[$i]}" ] || continue
          id_is_from "$id" "$me" && continue
          if [ -n "$only" ]; then
            counts_for_me "$id" "$me" || continue
          fi
          hits+=("$room/$id")
        done < <(post_ids)
      done
      [ ${#hits[@]} -gt 0 ] && break
    fi
    # Sleep in the background and wait on it, so a TERM or INT runs its trap at
    # once instead of when a foreground sleep ends.
    sleep "$interval" & sleep_pid=$!
    wait "$sleep_pid" || true
  done

  for item in "${hits[@]}"; do printf '%s\n' "$item"; done
}

# ---------------------------------------------------------------- direct messages

# A DM is the one room for a pair, dm-<a>-<b>, the two names in byte order, each
# from that side's own files. The starter keeps it; the other's own script links
# it there, so each script still writes only its own .moot/.

dm_room() { if [ "$1" \< "$2" ]; then printf 'dm-%s-%s' "$1" "$2"; else printf 'dm-%s-%s' "$2" "$1"; fi; }

# Refuse a DM closed by hand in <rooms dir>, naming the mv that reopens it.
dm_closed() {
  local keeper
  [ -d "$1/$2.archived" ] || return 0
  keeper=$(cd -P -- "$1/$2.archived/.." && pwd -P)
  die "$2 is archived; its keeper reopens it with: mv $keeper/$2.archived $keeper/$2"
}

dm_has_posts() { local e; for e in "$1"/posts/*; do [ -e "$e" ] && return 0; done; return 1; }

# The other side's own join of my room, its stderr on stdout for the caller.
dm_link_there() { MOOT_NAME= "$their/moot.sh" join "$rooms_dir/$room" 2>&1 >/dev/null; }

cmd_dm() {
  local who= me them room their mine theirs out
  case ${1:-} in -h|--help) usage; return 0 ;; -*) die "unknown option for dm: $1" ;; esac
  [ $# -eq 1 ] || die "dm takes one participant: its directory, or a sibling folder's name"
  who=$1
  me=$(own_name) || exit 1

  # A name: a DM already here, or else the sibling folder of that name.
  case $who in
    */* | . | ..) their=$who ;;
    *)
      check_segment 'participant name' "$who"
      their=$(cd -- "$moot_dir/../.." && pwd)/$who
      if [ ! -d "$their/.moot" ]; then
        room=$(dm_room "$me" "$who")
        [ ! -d "$rooms_dir/$room" ] || { printf 'have rooms/%s\n' "$room"; return 0; }
        dm_closed "$rooms_dir" "$room"
        die "no participant $who beside this one; pass its directory: $0 dm <dir>"
      fi ;;
  esac
  [ -d "$their/.moot" ] || die "no participant at $who (no .moot/ there)"
  their=$(cd -- "$their/.moot" && pwd)
  [ -x "$their/moot.sh" ] || die "no moot.sh in $their; install moot there first"
  ! [ "$their" -ef "$moot_dir" ] || die "a DM needs two participants; $who is this one"
  them=$(own_name "$their") || exit 1
  [ "$them" != "$me" ] || die "a DM needs two names; both sides are $me"
  room=$(dm_room "$me" "$them")
  mine="$rooms_dir/$room"; theirs="$their/rooms/$room"

  dm_closed "$rooms_dir" "$room"
  dm_closed "$their/rooms" "$room"
  if [ -L "$mine" ] && [ ! -e "$mine" ]; then
    die "rooms/$room leads nowhere; leave it first: $0 leave $room"
  fi
  # 1. Here already. If I keep it and the other has left, link it there again.
  if [ -d "$mine" ]; then
    if [ ! -L "$mine" ] && [ ! -e "$theirs" ] && [ ! -L "$theirs" ]; then
      out=$(dm_link_there) || printf 'moot: %s could not link rooms/%s again: %s\n' "$them" "$room" "${out#moot: }" >&2
    fi
    printf 'have rooms/%s\n' "$room"; return 0
  fi
  # 2. The other keeps it: join it.
  if [ -d "$theirs" ]; then
    cmd_join "$theirs" >/dev/null
    printf 'joined rooms/%s\n' "$room"; return 0
  fi
  # 3. Neither has it: start it here, and the other's script links it there.
  mkdir -p -- "$mine/posts"
  : > "$mine/posts/.gitkeep"
  if out=$(dm_link_there); then printf 'started rooms/%s\n' "$room"; return 0; fi
  # Both started at once, so each holds a real folder. The later name yields
  # if its room holds no posts; the first tries once more after a second.
  if [ -d "$theirs" ] && [ ! -L "$theirs" ]; then
    if [ "$me" \> "$them" ]; then
      ! dm_has_posts "$mine" || die "$room was started on both sides at once, and both hold posts: $mine and $theirs"
      rm -rf -- "${mine:?}"
      cmd_join "$theirs" >/dev/null
      printf 'joined rooms/%s\n' "$room"; return 0
    fi
    sleep 1
    if out=$(dm_link_there); then printf 'started rooms/%s\n' "$room"; return 0; fi
    die "$room was started on both sides at once: $mine and $theirs"
  fi
  die "started rooms/$room here, but $them could not join it: ${out#moot: }"
}

# ---------------------------------------------------------------- status

# .moot/status, this participant's own: line one is <UTC stamp> <text>. With -m,
# write it (beside, then renamed into place); either way print line one.
cmd_status() {
  local text= have=0 file="$moot_dir/status"
  while [ $# -gt 0 ]; do
    case $1 in
      -m) [ $# -ge 2 ] || die "-m needs text"; text=$2; have=1; shift 2 ;;
      -h|--help) usage; return 0 ;;
      *) die "unknown option for status: $1" ;;
    esac
  done
  if [ "$have" = 1 ]; then
    [ -n "${text//[[:space:]]/}" ] || die "refusing to write an empty status"
    printf '%s %s\n' "$(date -u +%Y%m%d-%H%M%S)" "$text" > "$moot_dir/.status.$$"
    mv -f -- "$moot_dir/.status.$$" "$file"
  fi
  if [ -r "$file" ]; then
    head -n 1 -- "$file"
  else
    printf 'moot: no status here yet; set one with: %s status -m <text>\n' "$0" >&2
  fi
}

# ---------------------------------------------------------------- dispatch

case ${1:-help} in help|-h|--help) ;; *) repair_links ;; esac

case ${1:-help} in
  create) shift; cmd_create "$@" ;;
  join) shift; cmd_join "$@" ;;
  leave) shift; cmd_leave "$@" ;;
  archive) shift; cmd_archive "$@" ;;
  dm) shift; cmd_dm "$@" ;;
  status) shift; cmd_status "$@" ;;
  rooms) shift; cmd_rooms "$@" ;;
  post) shift; cmd_post "$@" ;;
  read) shift; cmd_read "$@" ;;
  # Deprecated alias, kept for one release for callers that still run it.
  catchup) shift; cmd_read --new --mentions "$@" ;;
  watch) shift; cmd_watch "$@" ;;
  help|-h|--help) usage ;;
  *) usage >&2; die "unknown command: $1" ;;
esac
