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
  moot.sh rooms
  moot.sh post [--json] [--as <name>] [--room <name>] [-m <text> | -f <file> | -]
  moot.sh read [--room <name>] [--since <post-id>] [--tail <n>] [--follow]
  moot.sh catchup [--json] [--as <name>] [--room <name>] [--deliver <dir>]

A post is <YYYYMMDD>-<HHMMSS>-<sender>.md in rooms/<room>/posts/, UTC, plain
Markdown. Posts are immutable: there is no edit and no delete. A correction is
a new post.

post and read are aimed at one room; catchup sweeps every room here unless
--room narrows it.
USAGE
}

# ---------------------------------------------------------------- name resolution

# --as, then $MOOT_NAME, then .moot/name, then the sibling .gremlin/name, then
# $USER. Nobody is obliged to have a name file: every other step reads
# something that already exists. Shared with catchup: one chain, one concept.

moot_name() {
  [ -r "$moot_dir/name" ] || return 1
  head -n 1 -- "$moot_dir/name" | tr -d '[:space:]'
}

# .gremlin/name is a key=value file (name=tengu, source=generated), so take the
# field rather than the line. An older bare-name file has no =, and still
# resolves. Searched upward from the working directory, because a gremlin runs
# catchup from its own repo root while the room lives somewhere else.
gremlin_name() {
  local dir file value
  dir=$PWD
  while :; do
    file="$dir/.gremlin/name"
    if [ -r "$file" ]; then
      value=$(sed -n 's/^name=//p' "$file" | head -n 1 | tr -d '[:space:]')
      [ -n "$value" ] || value=$(head -n 1 -- "$file" | tr -d '[:space:]')
      printf '%s' "$value"
      return 0
    fi
    [ "$dir" = / ] && break
    dir=$(dirname -- "$dir")
  done
  return 1
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
  elif [ -n "${USER:-}" ]; then
    name=$USER
  fi
  [ -n "$name" ] || die "cannot resolve a sender name (try --as <name>)"
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
  done
}

post_body_path() {
  local id=$1
  if [ -d "$posts_dir/$id" ]; then
    printf '%s' "$posts_dir/$id/post.md"
  else
    printf '%s' "$posts_dir/$id.md"
  fi
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

  local sender; sender=$(resolve_name "$as")
  stamp=$(date -u +%Y%m%d-%H%M%S)

  # Compose out of sight, then link into place. A hidden name keeps the
  # in-progress post out of posts/* for every reader, tool or human.
  landing="$posts_dir/.$stamp-$sender.$$.landing"
  printf '%s\n' "$body" > "$landing"

  # link(2) fails if the target exists, so claiming a name is atomic: on a
  # same-second clash the writer simply takes the next free -N name.
  base="$stamp-$sender"
  target="$posts_dir/$base.md"
  n=1
  while ! ln -- "$landing" "$target" 2>/dev/null; do
    [ -e "$target" ] || { rm -f -- "$landing"; die "cannot write $target"; }
    n=$((n + 1))
    [ "$n" -le 999 ] || { rm -f -- "$landing"; die "too many posts in one second"; }
    base="$stamp-$sender-$n"
    target="$posts_dir/$base.md"
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

render_post() {
  local id=$1 body dim reset day time sender rest
  day=${id%%-*}; rest=${id#*-}
  time=${rest%%-*}; sender=${rest#*-}
  dim=''; reset=''
  if [ "$colour_on" = 1 ]; then dim=$(printf '\033[2m'); reset=$(printf '\033[0m'); fi

  printf '\n%s── %s-%s-%s %s:%s:%s UTC · %s ──%s\n\n' \
    "$dim" "${day:0:4}" "${day:4:2}" "${day:6:2}" \
    "${time:0:2}" "${time:2:2}" "${time:4:2}" "$sender" "$reset"

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

cmd_read() {
  local since= tail_n= follow=0 room_opt= id last=

  while [ $# -gt 0 ]; do
    case $1 in
      --room)  [ $# -ge 2 ] || die "--room needs a room"; room_opt=$2; shift 2 ;;
      --since) [ $# -ge 2 ] || die "--since needs a post id"; since=$2; shift 2 ;;
      --tail)  [ $# -ge 2 ] || die "--tail needs a count"; tail_n=$2; shift 2
               case $tail_n in ''|*[!0-9]*) die "--tail needs a number" ;; esac ;;
      --follow) follow=1; shift ;;
      -h|--help) usage; return 0 ;;
      *) die "unknown option for read: $1" ;;
    esac
  done

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
  local cursor_file="$seen_dir/$room/$me" cursor=
  [ -r "$cursor_file" ] && cursor=$(head -n 1 -- "$cursor_file" | tr -d '[:space:]')

  local ids=() new=() newest=
  while IFS= read -r id; do ids+=("$id"); done < <(post_ids)
  for id in ${ids[@]+"${ids[@]}"}; do
    newest=$id
    if [ -z "$cursor" ] || [ "$id" \> "$cursor" ]; then new+=("$id"); fi
  done

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

  # Advance the cursor past everything read, mentioned or not. The cursor is
  # this participant's own state and never travels with the room, so two
  # divergent copies reconcile on posts/ alone.
  local cursor_written=0
  if [ -n "$newest" ] && [ "$newest" != "$cursor" ]; then
    if mkdir -p -- "$seen_dir/$room" 2>/dev/null && printf '%s\n' "$newest" > "$cursor_file" 2>/dev/null; then
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
    "$([ -n "$newest" ] && printf '"%s"' "$(json_escape "$newest")" || printf null)" \
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
  for r in ${rooms[@]+"${rooms[@]}"}; do
    use_room "$r"
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
  rooms) shift; cmd_rooms "$@" ;;
  post) shift; cmd_post "$@" ;;
  read) shift; cmd_read "$@" ;;
  catchup) shift; cmd_catchup "$@" ;;
  help|-h|--help) usage ;;
  *) usage >&2; die "unknown command: $1" ;;
esac
