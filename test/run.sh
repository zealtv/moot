#!/usr/bin/env bash
#
# moot test suite. Bash and coreutils only, same as the thing it tests.
#
#   ./test/run.sh

set -uo pipefail
export LC_ALL=C

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

pass=0; fail=0

ok()   { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
no()   { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; [ $# -gt 1 ] && printf '       %s\n' "$2"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "expected [$3] got [$2]"; fi; }
group() { printf '\n%s\n' "$1"; }

# A room with moot installed. Every test gets a fresh one.
new_room() {
  local dir; dir=$(mktemp -d "$work/room.XXXXXX")
  "$repo/install.sh" "$dir" >/dev/null
  printf '%s' "$dir"
}

# A stub `date` on PATH, so timestamps are deterministic and same-second
# collisions are reproducible rather than a race we hope to lose.
freeze_date() {
  local stamp=$1 bin="$work/bin"
  mkdir -p "$bin"
  cat > "$bin/date" <<STUB
#!/bin/sh
echo "$stamp"
STUB
  chmod +x "$bin/date"
  PATH="$bin:$PATH"
}
thaw_date() { PATH=${PATH#"$work/bin:"}; }

# ---------------------------------------------------------------- init

group 'init'
room=$(new_room)
[ -d "$room/posts" ] && ok 'init creates posts/' || no 'init creates posts/'
[ -d "$room/seen" ]  && ok 'init creates seen/'  || no 'init creates seen/'
[ -f "$room/posts/.gitkeep" ] && ok 'init seeds posts/.gitkeep' || no 'init seeds posts/.gitkeep'

"$room/.moot/moot.sh" post --as bob -m 'hello' >/dev/null
out=$("$room/.moot/moot.sh" init)
check 'init is idempotent' "$out" "moot already initialised at $room"
check 'init keeps existing posts' "$(ls "$room/posts"/*.md | wc -l | tr -d ' ')" '1'

out=$("$room/.moot/moot.sh" init --json)
case $out in *'"changed":false'*) ok 'init --json reports unchanged' ;; *) no 'init --json reports unchanged' "$out" ;; esac

# ---------------------------------------------------------------- posting

group 'post'
room=$(new_room)
out=$("$room/.moot/moot.sh" post --json --as bob -m 'first')
case $out in *'"ok":true'*'"sender":"bob"'*) ok 'post --json reports the post' ;; *) no 'post --json reports the post' "$out" ;; esac

id=$(printf '%s' "$out" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
check 'post body is the file, byte for byte' "$(cat "$room/posts/$id.md")" 'first'
case $id in [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]-bob) ok 'post id follows the filename grammar' ;; *) no 'post id follows the filename grammar' "$id" ;; esac

echo 'from stdin' | "$room/.moot/moot.sh" post --as bob - >/dev/null
printf 'from a file\n' > "$work/msg.md"
"$room/.moot/moot.sh" post --as bob -f "$work/msg.md" >/dev/null
check 'post accepts -m, -, and -f' "$(ls "$room/posts"/*.md | wc -l | tr -d ' ')" '3'

"$room/.moot/moot.sh" post --as bob -m '' >/dev/null 2>&1 && no 'post refuses an empty message' || ok 'post refuses an empty message'
"$room/.moot/moot.sh" post --as 'bad name' -m 'x' >/dev/null 2>&1 && no 'post refuses an unsafe sender name' || ok 'post refuses an unsafe sender name'

check 'there is no edit verb'   "$("$room/.moot/moot.sh" edit x 2>&1 >/dev/null | tail -1)" 'moot: unknown command: edit'
check 'there is no delete verb' "$("$room/.moot/moot.sh" delete x 2>&1 >/dev/null | tail -1)" 'moot: unknown command: delete'

group 'post is atomic'
room=$(new_room)
"$room/.moot/moot.sh" post --as bob -m 'done' >/dev/null
check 'post leaves no landing file' "$(ls -A "$room/posts" | grep -c landing)" '0'
# A post mid-compose must be invisible to every reader, tool or human.
: > "$room/posts/.20260829-120000-tengu.999.landing"
check 'a landing file is not a post' "$("$room/.moot/moot.sh" read | grep -c 'tengu')" '0'
check 'a landing file is not in posts/*' "$(printf '%s\n' "$room"/posts/* | grep -c landing)" '0'

group 'same-second collision'
room=$(new_room)
freeze_date '20260829-163412'
"$room/.moot/moot.sh" post --as tengu -m 'one' >/dev/null
"$room/.moot/moot.sh" post --as tengu -m 'two' >/dev/null
"$room/.moot/moot.sh" post --as tengu -m 'three' >/dev/null
thaw_date
[ -f "$room/posts/20260829-163412-tengu.md" ]   && ok 'first post takes the plain name'   || no 'first post takes the plain name'
[ -f "$room/posts/20260829-163412-tengu-2.md" ] && ok 'second post takes the -2 name'      || no 'second post takes the -2 name'
[ -f "$room/posts/20260829-163412-tengu-3.md" ] && ok 'third post takes the -3 name'       || no 'third post takes the -3 name'
check 'no post was overwritten' "$(cat "$room/posts/20260829-163412-tengu.md")" 'one'
check 'the suffixed post kept its own body' "$(cat "$room/posts/20260829-163412-tengu-3.md")" 'three'

# ---------------------------------------------------------------- ordering

group 'ordering'
room=$(new_room)
for stamp in 20260829-120000 20260829-090000 20260830-010000 20260828-235959; do
  printf 'body %s\n' "$stamp" > "$room/posts/$stamp-bob.md"
done
out=$("$room/.moot/moot.sh" read | grep -c 'body ')
check 'read shows every post' "$out" '4'
first=$("$room/.moot/moot.sh" read | grep 'body ' | head -1)
last=$("$room/.moot/moot.sh" read | grep 'body ' | tail -1)
check 'read is newest-last: oldest first' "$first" 'body 20260828-235959'
check 'read is newest-last: newest last'  "$last"  'body 20260830-010000'
case $("$room/.moot/moot.sh" read | grep -m1 '──') in *'2026-08-28 23:59:59 UTC · bob'*) ok 'the heading is built from the filename' ;; *) no 'the heading is built from the filename' ;; esac

group 'read --since and --tail'
check '--since is exclusive of its own post' \
  "$("$room/.moot/moot.sh" read --since 20260829-090000-bob | grep -c 'body ')" '2'
check '--since a later post shows nothing' \
  "$("$room/.moot/moot.sh" read --since 20260830-010000-bob | grep -c 'body ')" '0'
check '--since a post id not on the board still works' \
  "$("$room/.moot/moot.sh" read --since 20260829-100000-nobody | grep -c 'body ')" '2'
check '--since before everything shows everything' \
  "$("$room/.moot/moot.sh" read --since 20200101-000000-nobody | grep -c 'body ')" '4'
check '--tail takes the newest n' \
  "$("$room/.moot/moot.sh" read --tail 2 | grep -c 'body ')" '2'
check '--tail keeps the newest post' \
  "$("$room/.moot/moot.sh" read --tail 1 | grep 'body ')" 'body 20260830-010000'
check '--tail beyond the board is harmless' \
  "$("$room/.moot/moot.sh" read --tail 99 | grep -c 'body ')" '4'
check '--since and --tail compose' \
  "$("$room/.moot/moot.sh" read --since 20260828-235959-bob --tail 1 | grep 'body ')" 'body 20260830-010000'

group 'read on an empty board'
room=$(new_room)
"$room/.moot/moot.sh" read >/dev/null 2>&1 && ok 'read of an empty board succeeds' || no 'read of an empty board succeeds'
check 'read of an empty board says nothing' "$("$room/.moot/moot.sh" read | wc -c | tr -d ' ')" '0'

group 'read --follow'
room=$(new_room)
printf 'already here\n' > "$room/posts/20260829-090000-bob.md"
MOOT_FOLLOW_INTERVAL=0.2 "$room/.moot/moot.sh" read --follow > "$work/follow.out" 2>&1 &
follow_pid=$!
sleep 1
printf 'arrived later\n' > "$room/posts/20260829-100000-tengu.md"
sleep 1
kill "$follow_pid" 2>/dev/null
wait "$follow_pid" 2>/dev/null
check '--follow prints the existing board' "$(grep -c 'already here' "$work/follow.out")" '1'
check '--follow appends a post that arrives' "$(grep -c 'arrived later' "$work/follow.out")" '1'
check '--follow does not repeat a post' "$(grep -c 'already here' "$work/follow.out")" '1'
check '--follow writes nothing back into the moot' "$(ls -A "$room/posts" | grep -vc gitkeep)" '2'

# ---------------------------------------------------------------- attachments

group 'attachments'
room=$(new_room)
mkdir -p "$room/posts/20260829-164070-bob"
printf 'see the patch @tengu\n' > "$room/posts/20260829-164070-bob/post.md"
printf 'diff goes here\n' > "$room/posts/20260829-164070-bob/diff.patch"
printf 'a plain one\n' > "$room/posts/20260829-170000-tengu.md"
out=$("$room/.moot/moot.sh" read)
case $out in *'see the patch @tengu'*) ok 'an attachment post renders post.md' ;; *) no 'an attachment post renders post.md' ;; esac
case $out in *'attached: diff.patch'*) ok 'an attachment post lists its files' ;; *) no 'an attachment post lists its files' "$out" ;; esac
case $out in *'attached: post.md'*) no 'post.md is not listed as an attachment' ;; *) ok 'post.md is not listed as an attachment' ;; esac
case $out in *'2026-08-29 16:40:70 UTC · bob'*) ok 'an attachment directory gets a normal heading' ;; *) no 'an attachment directory gets a normal heading' ;; esac
check 'an attachment post is one post, not many' "$(printf '%s\n' "$out" | grep -c '──')" '2'
check 'an attachment post has a --since id' \
  "$("$room/.moot/moot.sh" read --since 20260829-164070-bob | grep -c 'a plain one')" '1'

# ---------------------------------------------------------------- name resolution

group 'name resolution'
room=$(new_room)
sender_of() { ls "$1/posts"/*.md | sed -n 's/.*-\([^-]*\)\.md$/\1/p' | tail -1; }

MOOT_NAME=envname USER=username "$room/.moot/moot.sh" post --as flagname -m 'x' >/dev/null
check '--as wins' "$(sender_of "$room")" 'flagname'

room=$(new_room)
MOOT_NAME=envname USER=username "$room/.moot/moot.sh" post -m 'x' >/dev/null
check '$MOOT_NAME comes next' "$(sender_of "$room")" 'envname'

room=$(new_room)
mkdir -p "$room/.gremlin"
printf 'tengu\n' > "$room/.gremlin/name"
( cd "$room" && MOOT_NAME= USER=username "$room/.moot/moot.sh" post -m 'x' >/dev/null )
check '.gremlin/name comes next' "$(sender_of "$room")" 'tengu'

# A gremlin posts under its own name, not its folder's, and finds that name by
# walking up from where it is working.
room=$(new_room)
mkdir -p "$room/.gremlin" "$room/deep/nested"
printf 'fanta\n' > "$room/.gremlin/name"
( cd "$room/deep/nested" && MOOT_NAME= USER=username "$room/.moot/moot.sh" post -m 'x' >/dev/null )
check '.gremlin/name is found from a subdirectory' "$(sender_of "$room")" 'fanta'

room=$(new_room)
( cd "$work" && MOOT_NAME= USER=username "$room/.moot/moot.sh" post -m 'x' >/dev/null )
check '$USER is the last resort' "$(sender_of "$room")" 'username'

room=$(new_room)
( cd "$work" && env -u MOOT_NAME -u USER "$room/.moot/moot.sh" post -m 'x' >/dev/null 2>&1 ) \
  && no 'no name at all is an error' || ok 'no name at all is an error'

# ---------------------------------------------------------------- no tool needed

group 'a moot needs no tool'
room=$(new_room)
# The hand-posting incantation from the README must produce a readable post.
( cd "$room" && echo 'posted by hand' > "posts/$(date -u +%Y%m%d-%H%M%S)-bob.md" )
check 'a hand-written post is a post' "$("$room/.moot/moot.sh" read | grep -c 'posted by hand')" '1'
"$room/.moot/moot.sh" post --as tengu -m 'posted by tool' >/dev/null
check 'a tool-written post is readable by hand' "$(cat "$room"/posts/*-tengu.md)" 'posted by tool'

# ---------------------------------------------------------------- install

group 'install'
room=$(new_room)
[ -x "$room/.moot/moot.sh" ] && ok 'install deploys an executable moot.sh' || no 'install deploys an executable moot.sh'
[ -f "$room/.moot/README.md" ] && ok 'install deploys the README' || no 'install deploys the README'
"$repo/install.sh" "$room" >/dev/null
check 'install is repeatable' "$(ls -A "$room/.moot" | wc -l | tr -d ' ')" '2'

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
