#!/usr/bin/env bash
#
# moot — a directory of messages.
#
# This script is a convenience, never a dependency. Everything it does can be
# done by hand with date, cat, and ls; see README.md for the format itself.
#
# It operates on the .moot/ it lives in, so each deployed copy is
# self-contained.

set -euo pipefail
export LC_ALL=C

moot_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
room=$(dirname -- "$moot_dir")
posts_dir="$room/posts"
seen_dir="$room/seen"

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

  moot.sh init [--json]
  moot.sh post [--json] [--as <name>] [-m <text> | -f <file> | -]
  moot.sh read [--since <post-id>] [--tail <n>] [--follow]
  moot.sh catchup [--json] [--as <name>] [--deliver <dir>]

A post is <YYYYMMDD>-<HHMMSS>-<sender>.md in posts/, UTC, plain Markdown.
Posts are immutable: there is no edit and no delete. A correction is a new post.
USAGE
}

# ---------------------------------------------------------------- name resolution

# --as, then $MOOT_NAME, then the host's .gremlin/name, then $USER. Every step
# reads something that already exists, so a participant needs no moot config of
# its own. Shared with catchup: one chain, one concept.
gremlin_name() {
  local dir
  dir=$PWD
  while :; do
    if [ -r "$dir/.gremlin/name" ]; then
      head -n 1 -- "$dir/.gremlin/name" | tr -d '[:space:]'
      return 0
    fi
    [ "$dir" = / ] && break
    dir=$(dirname -- "$dir")
  done
  return 1
}

resolve_name() {
  local as=${1:-} name=
  if [ -n "$as" ]; then
    name=$as
  elif [ -n "${MOOT_NAME:-}" ]; then
    name=$MOOT_NAME
  elif name=$(gremlin_name) && [ -n "$name" ]; then
    :
  elif [ -n "${USER:-}" ]; then
    name=$USER
  fi
  [ -n "$name" ] || die "cannot resolve a sender name (try --as <name>)"
  case $name in
    *[!A-Za-z0-9._-]* | .* | '')
      die "sender name '$name' is not filename-safe (use A-Z a-z 0-9 . _ -)" ;;
  esac
  printf '%s' "$name"
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
  local json=0 changed=0 d
  [ "${1:-}" = --json ] && { json=1; shift; }
  for d in "$posts_dir" "$seen_dir"; do
    [ -d "$d" ] || { mkdir -p -- "$d"; changed=1; }
    # Git cannot track an empty directory; without this a moot committed
    # before its first post loses its trays on clone.
    [ -e "$d/.gitkeep" ] || { : > "$d/.gitkeep"; changed=1; }
  done
  if [ "$json" = 1 ]; then
    printf '{"schema_version":1,"command":"init","ok":true,"changed":%s,"room":"%s"}\n' \
      "$([ "$changed" = 1 ] && echo true || echo false)" "$(json_escape "$room")"
  elif [ "$changed" = 1 ]; then
    printf 'initialised moot at %s\n' "$room"
  else
    printf 'moot already initialised at %s\n' "$room"
  fi
}

# ---------------------------------------------------------------- post

cmd_post() {
  local json=0 as= body= have_body=0 stamp base target landing n

  [ "${1:-}" = --json ] && { json=1; shift; }

  while [ $# -gt 0 ]; do
    case $1 in
      --as) [ $# -ge 2 ] || die "--as needs a name"; as=$2; shift 2 ;;
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

  [ -d "$posts_dir" ] || die "no posts/ directory at $room (run: $0 init)"

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
    printf '{"schema_version":1,"command":"post","ok":true,"changed":true,"id":"%s","path":"%s","sender":"%s","timestamp":"%s"}\n' \
      "$(json_escape "$base")" "$(json_escape "posts/$base.md")" \
      "$(json_escape "$sender")" "$(json_escape "$stamp")"
  else
    printf 'posted posts/%s.md\n' "$base"
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
  local since= tail_n= follow=0 id last=

  while [ $# -gt 0 ]; do
    case $1 in
      --since) [ $# -ge 2 ] || die "--since needs a post id"; since=$2; shift 2 ;;
      --tail)  [ $# -ge 2 ] || die "--tail needs a count"; tail_n=$2; shift 2
               case $tail_n in ''|*[!0-9]*) die "--tail needs a number" ;; esac ;;
      --follow) follow=1; shift ;;
      -h|--help) usage; return 0 ;;
      *) die "unknown option for read: $1" ;;
    esac
  done

  [ -d "$posts_dir" ] || die "no posts/ directory at $room (run: $0 init)"
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

# A delivered item carries the path to the moot and its own post id, not just
# the body. A cursor may have advanced silently past thirty announcements
# before one asks for something, so the recipient needs to be able to read
# backwards on demand — pull, not push. The board is right there.
deliver_post() {
  local id=$1 dir=$2 body out landing day time sender rest
  day=${id%%-*}; rest=${id#*-}
  time=${rest%%-*}; sender=${rest#*-}
  body=$(post_body_path "$id")
  out="$dir/moot-$id.md"

  # The post id is in the filename, so a re-run delivers nothing twice even if
  # the cursor could not be written.
  [ -e "$out" ] && return 1

  landing="$dir/.moot-$id.$$.landing"
  {
    printf '# moot mention · %s · %s-%s-%s %s:%s:%s UTC\n\n' \
      "$sender" "${day:0:4}" "${day:4:2}" "${day:6:2}" \
      "${time:0:2}" "${time:2:2}" "${time:4:2}"
    printf -- '- moot: `%s`\n' "$room"
    printf -- '- post: `%s`\n' "$id"
    printf -- '- read back: `%s read --tail 20`\n\n' "$moot_dir/moot.sh"
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

cmd_catchup() {
  local json=0 as= deliver= id

  [ "${1:-}" = --json ] && { json=1; shift; }

  while [ $# -gt 0 ]; do
    case $1 in
      --as)      [ $# -ge 2 ] || die "--as needs a name"; as=$2; shift 2 ;;
      --deliver) [ $# -ge 2 ] || die "--deliver needs a directory"; deliver=$2; shift 2 ;;
      -h|--help) usage; return 0 ;;
      *) die "unknown option for catchup: $1" ;;
    esac
  done

  [ -d "$posts_dir" ] || die "no posts/ directory at $room (run: $0 init)"

  local me; me=$(resolve_name "$as")
  local cursor_file="$seen_dir/$me" cursor=
  [ -r "$cursor_file" ] && cursor=$(head -n 1 -- "$cursor_file" | tr -d '[:space:]')

  if [ -n "$deliver" ]; then
    mkdir -p -- "$deliver" || die "cannot use deliver directory $deliver"
    deliver=$(cd -- "$deliver" && pwd)
  fi

  local ids=() new=() delivered=() newest=
  while IFS= read -r id; do ids+=("$id"); done < <(post_ids)
  for id in ${ids[@]+"${ids[@]}"}; do
    newest=$id
    if [ -z "$cursor" ] || [ "$id" \> "$cursor" ]; then new+=("$id"); fi
  done

  [ "$json" = 1 ] || init_colour

  for id in ${new[@]+"${new[@]}"}; do
    # No mention: advance past it silently. Still readable with `read`,
    # interrupts nobody.
    post_mentions_me "$(post_body_path "$id")" "$me" || continue
    if [ -n "$deliver" ]; then
      deliver_post "$id" "$deliver" && delivered+=("$id")
    else
      delivered+=("$id")
      [ "$json" = 1 ] || render_post "$id"
    fi
  done

  # Advance the cursor past everything read, mentioned or not. One writer per
  # path: only this participant ever writes seen/<its own name>, which is what
  # keeps two divergent copies of the room reconciling as cleanly as posts do.
  local cursor_written=0
  if [ -n "$newest" ] && [ "$newest" != "$cursor" ]; then
    if mkdir -p -- "$seen_dir" 2>/dev/null && printf '%s\n' "$newest" > "$cursor_file" 2>/dev/null; then
      cursor_written=1
    else
      # A board reachable read-only is a normal way to run: delivery is still
      # correct, because delivered filenames carry the post id.
      printf 'moot: cannot write %s (read-only moot); nothing was delivered twice anyway\n' \
        "seen/$me" >&2
    fi
  fi

  if [ "$json" = 1 ]; then
    local list= sep=
    for id in ${delivered[@]+"${delivered[@]}"}; do
      list="$list$sep\"$(json_escape "$id")\""; sep=,
    done
    printf '{"schema_version":1,"command":"catchup","ok":true,"changed":%s,"sender":"%s","since":%s,"cursor":%s,"cursor_written":%s,"scanned":%s,"delivered":[%s]}\n' \
      "$([ ${#delivered[@]} -gt 0 ] || [ "$cursor_written" = 1 ] && echo true || echo false)" \
      "$(json_escape "$me")" \
      "$([ -n "$cursor" ] && printf '"%s"' "$(json_escape "$cursor")" || printf null)" \
      "$([ -n "$newest" ] && printf '"%s"' "$(json_escape "$newest")" || printf null)" \
      "$([ "$cursor_written" = 1 ] && echo true || echo false)" \
      "${#new[@]}" "$list"
  elif [ ${#delivered[@]} -gt 0 ]; then
    if [ -n "$deliver" ]; then
      printf 'delivered %s mention(s) to %s\n' "${#delivered[@]}" "$deliver"
    else
      printf '\n'
    fi
  elif [ -n "$deliver" ]; then
    printf 'nothing for %s\n' "$me"
  fi
}

# ---------------------------------------------------------------- dispatch

case ${1:-help} in
  init) shift; cmd_init "$@" ;;
  post) shift; cmd_post "$@" ;;
  read) shift; cmd_read "$@" ;;
  catchup) shift; cmd_catchup "$@" ;;
  help|-h|--help) usage ;;
  *) usage >&2; die "unknown command: $1" ;;
esac
