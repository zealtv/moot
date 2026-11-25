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
no()   { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; [ $# -gt 1 ] && printf '       %s\n' "$2"; return 0; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "expected [$3] got [$2]"; fi; }
group() { printf '\n%s\n' "$1"; }

# Commands as each kind of host runs them. They read $host, $room or $parent
# when called, so a group sets the variable and then uses the helper.
j() { "$host/.moot/moot.sh" "$@"; }
m() { "$room/.moot/moot.sh" "$@"; }
p() { printf '%s\n' "$3" > "$room/.moot/rooms/$1/posts/$2.md"; }
say() { printf '%s\n' "$2" > "$room/.moot/rooms/board/posts/$1.md"; }
a() { ( cd "$work" && MOOT_NAME= "$parent/alice/.moot/moot.sh" "$@" ); }
b() { ( cd "$work" && MOOT_NAME= "$parent/bob/.moot/moot.sh" "$@" ); }
c() { ( cd "$work" && MOOT_NAME= "$parent/carol/.moot/moot.sh" "$@" ); }
d() { ( cd "$work" && MOOT_NAME= "$parent/dave/.moot/moot.sh" "$@" ); }

# refuses <label> <word> <command...>: the command exits 1 and its stderr says <word>.
refuses() {
  local label=$1 word=$2 out rc; shift 2
  out=$("$@" 2>&1 >/dev/null); rc=$?
  case "$rc:$out" in "1:"*"$word"*) ok "$label" ;; *) no "$label" "$rc:$out" ;; esac
}

# A host directory with moot installed and one room kept. Every test gets a
# fresh one. The host is an ordinary working directory: everything moot owns is
# under its .moot/, and the room under test is rooms/board/.
new_room() {
  local dir; dir=$(mktemp -d "$work/host.XXXXXX")
  "$repo/install.sh" "$dir" >/dev/null
  # create, not mkdir: it leaves the join mark, so a first delivery here
  # starts from the room's beginning rather than from now.
  MOOT_NAME= "$dir/.moot/moot.sh" create board >/dev/null
  printf '%s' "$dir"
}

# Keep a room: a real folder in the host's own .moot/rooms/. No tool needed.
keep() { mkdir -p "$1/.moot/rooms/$2/posts"; }
# Keep one with create, which leaves the join mark: a first delivery there
# starts from the beginning, as for a room just made.
own() { MOOT_NAME= "$1/.moot/moot.sh" create "$2" >/dev/null; }

# A host with moot installed and no room.
new_host() {
  local dir; dir=$(mktemp -d "$work/host.XXXXXX")
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

# ---------------------------------------------------------------- rooms

group 'a bare participant'
host=$(new_host)
check 'the host holds nothing but .moot/' "$(ls -A "$host")" '.moot'
check 'a participant starts with no rooms' "$("$host/.moot/moot.sh" rooms | grep -c 'no rooms here yet')" '1'
refuses 'there is no init verb' 'unknown command' j init
refuses 'there is no subscribe verb' 'unknown command' j subscribe x
out=$("$host/.moot/moot.sh" post --as ben -m 'x' 2>&1 >/dev/null)
case $out in *'no rooms here yet'*'create <room>'*'join'*) ok 'post with no rooms says how to keep or hear one' ;; *) no 'post with no rooms says how to keep or hear one' "$out" ;; esac

group 'a room you keep'
room=$(new_room)
check 'a kept room holds nothing but posts/' "$(ls -A "$room/.moot/rooms/board")" 'posts'
check 'rooms lists it' "$("$room/.moot/moot.sh" rooms)" 'board'
"$room/.moot/moot.sh" post --as ben -m 'hello' >/dev/null
check 'a post lands in the kept folder' "$(ls "$room/.moot/rooms/board/posts"/*.md | wc -l | tr -d ' ')" '1'
check 'posting makes no cursor' "$(ls "$room/.moot/seen/board" 2>/dev/null | wc -l | tr -d ' ')" '0'
printf 'old\n' > "$room/.moot/rooms/board/posts/20260829-090000-ben.md"
"$room/.moot/moot.sh" read --new --as ben >/dev/null
[ -d "$room/.moot/seen/board" ] && ok 'the cursor directory is made when first needed' || no 'the cursor directory is made when first needed'
# A room dropped in by copy is heard by being there.
mkdir -p "$room/.moot/rooms/arrived/posts"
printf 'over rsync\n' > "$room/.moot/rooms/arrived/posts/20260829-100000-ben.md"
check 'a copied-in room is heard with no join' "$("$room/.moot/moot.sh" read --room arrived | grep -c 'over rsync')" '1'

# One folder per participant under a parent, as checkouts sit side by side.
group 'join is a link'
parent=$(mktemp -d "$work/layout.XXXXXX")
for p in carol alice dave; do mkdir -p "$parent/$p"; "$repo/install.sh" "$parent/$p" >/dev/null; done
keep "$parent/carol" ops; keep "$parent/carol" dev

out=$(a join "$parent/carol/.moot/rooms/ops")
check 'join reports the link it made' "$out" 'joined rooms/ops -> ../../../carol/.moot/rooms/ops'
[ -L "$parent/alice/.moot/rooms/ops" ] && ok 'the room is a link, not a folder' || no 'the room is a link, not a folder'
check 'and the target is relative' "$(readlink "$parent/alice/.moot/rooms/ops")" '../../../carol/.moot/rooms/ops'
[ "$parent/alice/.moot/rooms/ops" -ef "$parent/carol/.moot/rooms/ops" ] && ok 'and it leads to the keeper' || no 'and it leads to the keeper'
check 'join leaves the keeper alone' "$(ls -A "$parent/carol/.moot/rooms/ops")" 'posts'
check 'rooms lists a linked room' "$(a rooms)" 'ops'
a post -m 'from alice' >/dev/null
check 'a post through the link lands in the keeper folder' "$(ls "$parent/carol/.moot/rooms/ops/posts"/*-alice.md | wc -l | tr -d ' ')" '1'
check 'and the keeper reads it' "$(c read --room ops | grep -c 'from alice')" '1'
check 'join twice is a no-op' "$(a join "$parent/carol/.moot/rooms/ops")" 'already in rooms/ops'
check 'a trailing slash joins the same room' "$(a join "$parent/carol/.moot/rooms/ops/")" 'already in rooms/ops'
check 'the keeper joining its own room is a no-op' "$(c join "$parent/carol/.moot/rooms/ops")" 'already in rooms/ops'
[ -L "$parent/carol/.moot/rooms/ops" ] && no 'and it stays a real folder' || ok 'and it stays a real folder'

# Joining through another participant's link goes straight to the keeper.
d join "$parent/alice/.moot/rooms/ops" >/dev/null
check 'a link joined through a link leads straight to the keeper' "$(readlink "$parent/dave/.moot/rooms/ops")" '../../../carol/.moot/rooms/ops'

# The links are relative, so the whole layout can move.
moved=$(mktemp -d "$work/moved.XXXXXX"); mv "$parent" "$moved/layout"
check 'a relative link survives moving the layout' "$(( cd "$work" && "$moved/layout/alice/.moot/moot.sh" read --room ops ) | grep -c 'from alice')" '1'
mv "$moved/layout" "$parent"

group 'join only ever links'
before=$(ls -A "$parent/alice/.moot/rooms" | tr '\n' ' ')
out=$(a join runs 2>&1); rc=$?
check 'join of a bare name that is no room fails' "$rc" '1'
case $out in *"'runs' is not a room"*'create <room>'*) ok 'and says how to keep a room instead' ;; *) no 'and says how to keep a room instead' "$out" ;; esac
check 'and makes nothing' "$(ls -A "$parent/alice/.moot/rooms" | tr '\n' ' ')" "$before"
mkdir -p "$parent/not-a-room"
refuses 'a folder without posts/ is refused' 'not a room' a join "$parent/not-a-room"
[ -e "$parent/alice/.moot/rooms/not-a-room" ] && no 'and no link was made' || ok 'and no link was made'
refuses 'a path that does not exist is refused' 'not a room' a join "$parent/nowhere"
mkdir -p "$parent/bad room/posts"
out=$(a join "$parent/bad room" 2>&1 >/dev/null | tail -1)
check 'an unsafe room name is refused' "$out" "moot: room name 'bad room' is not filename-safe (use A-Z a-z 0-9 . _ -)"
[ -e "$parent/alice/.moot/rooms/bad room" ] && no 'and writes no path' || ok 'and writes no path'

# A room you keep is never replaced by a link, and a link is never silently repointed.
keep "$parent/alice" dev
a post --room dev -m 'alice keeps dev' >/dev/null
out=$(a join "$parent/carol/.moot/rooms/dev" 2>&1); rc=$?
check 'join will not replace a room you keep' "$rc" '1'
case $out in *'rooms/dev is a room kept here'*) ok 'and says so' ;; *) no 'and says so' "$out" ;; esac
[ -d "$parent/alice/.moot/rooms/dev" ] && [ ! -L "$parent/alice/.moot/rooms/dev" ] && ok 'and the kept room is untouched' || no 'and the kept room is untouched'
mkdir -p "$parent/other/.moot/rooms/ops/posts"
out=$(a join "$parent/other/.moot/rooms/ops" 2>&1); rc=$?
check 'join will not repoint a link to another room' "$rc" '1'
case $out in *'rooms/ops is already a link to ../../../carol/.moot/rooms/ops'*) ok 'and names where it points' ;; *) no 'and names where it points' "$out" ;; esac
ln -s "$work/nowhere-at-all" "$parent/dave/.moot/rooms/lost"
mkdir -p "$parent/x/lost/posts"
refuses 'join over a dangling link is refused' 'already' d join "$parent/x/lost"

group 'join in a bare copy'
bare=$(mktemp -d "$work/bare.XXXXXX"); mkdir -p "$bare/app"
cp -R "$repo/.moot" "$bare/app/"
rm -rf -- "${bare:?}/app/.moot/rooms" "${bare:?}/app/.moot/seen"
"$bare/app/.moot/moot.sh" join "$parent/carol/.moot/rooms/ops" >/dev/null && ok 'join makes rooms/ itself' || no 'join makes rooms/ itself'
[ -L "$bare/app/.moot/rooms/ops" ] && [ "$bare/app/.moot/rooms/ops" -ef "$parent/carol/.moot/rooms/ops" ] && ok 'and the link leads to the room' || no 'and the link leads to the room'

group 'leaving'
rm "$parent/dave/.moot/rooms/ops"
check 'rm of the link leaves the room' "$(ls "$parent/carol/.moot/rooms/ops/posts" | wc -l | tr -d ' ')" '1'
check 'and the participant hears nothing' "$(d rooms | grep -c 'no rooms here yet')" '1'

group 'room resolution'
host=$(new_host)
keep "$host" board
j post --as ben -m 'flagless' >/dev/null
check 'the sole room needs no flag' "$(ls "$host/.moot/rooms/board/posts"/*.md | wc -l | tr -d ' ')" '1'

keep "$host" release
out=$(j post --as ben -m 'x' 2>&1 >/dev/null)
case $out in *'several rooms here and none chosen'*) ok 'two rooms and no flag fails usefully' ;; *) no 'two rooms and no flag fails usefully' "$out" ;; esac
case $out in *board*release*) ok 'the error lists the rooms' ;; *) no 'the error lists the rooms' "$out" ;; esac
case $out in *'--room'*) ok 'the error names the fix' ;; *) no 'the error names the fix' "$out" ;; esac
# There is no room pointer and no environment default any more.
printf 'release\n' > "$host/.moot/room"
MOOT_ROOM=release refuses '.moot/room and $MOOT_ROOM no longer choose a room' 'rooms here' j post --as ben -m 'x'
j post --as ben --room release -m 'flag' >/dev/null
check '--room chooses' "$(ls "$host/.moot/rooms/release/posts"/*.md | wc -l | tr -d ' ')" '1'
check 'the rooms hold their own posts' "$(j read --room board | grep -c '^flag$')" '0'
refuses 'post refuses an unsafe room name' 'not filename-safe' j post --as ben --room 'bad room' -m 'x'
refuses 'post to a room that is not here fails' 'no room nosuch' j post --as ben --room nosuch -m 'x'
[ -e "$host/.moot/rooms/nosuch" ] && no 'and makes no room' || ok 'and makes no room'
refuses 'read of a room that is not here fails' 'no room nosuch' j read --room nosuch
check 'rooms lists both' "$(j rooms | tr '\n' ' ')" 'board release '

group 'the .gitignore pair'
host=$(new_host)
for line in /seen/ /name /watching /watch.paused 'rooms/*' '!rooms/*/'; do
  grep -qxF "$line" "$host/.moot/.gitignore" && ok "the installed .moot/.gitignore has $line" || no "the installed .moot/.gitignore has $line"
done
gi=$(mktemp -d "$work/gi.XXXXXX"); git -C "$gi" init -q
mkdir -p "$gi/.moot" "$gi/keeper/.moot/rooms/ops/posts"
cp "$repo/.moot/.gitignore" "$gi/.moot/.gitignore"
mkdir -p "$gi/.moot/rooms/dev/posts" "$gi/.moot/rooms/room/posts" "$gi/.moot/seen/dev"
ln -s ../../keeper/.moot/rooms/ops "$gi/.moot/rooms/ops"
: > "$gi/.moot/rooms/dev/posts/a.md"; : > "$gi/.moot/rooms/room/posts/b.md"
: > "$gi/.moot/seen/dev/ben"; : > "$gi/.moot/name"; : > "$gi/keeper/.moot/rooms/ops/posts/c.md"
status=$(git -C "$gi" status --porcelain -uall -- .moot)
case $status in *'.moot/rooms/dev/posts/a.md'*) ok 'a real room folder is tracked' ;; *) no 'a real room folder is tracked' "$status" ;; esac
case $status in *'.moot/rooms/room/posts/b.md'*) ok 'even one named room (patterns are anchored)' ;; *) no 'even one named room (patterns are anchored)' "$status" ;; esac
case $status in *'rooms/ops'*) no 'a linked room is ignored' "$status" ;; *) ok 'a linked room is ignored' ;; esac
case $status in *seen*|*'.moot/name'*) no 'seen/ and name are ignored' "$status" ;; *) ok 'seen/ and name are ignored' ;; esac
rm -rf "${gi:?}"

# ---------------------------------------------------------------- posting

group 'post'
room=$(new_room)
out=$("$room/.moot/moot.sh" post --json --as ben -m 'first')
case $out in *'"ok":true'*'"sender":"ben"'*) ok 'post --json reports the post' ;; *) no 'post --json reports the post' "$out" ;; esac
out2=$("$room/.moot/moot.sh" post --room board --json --as ben -m 'flag order' )
case $out2 in *'"room":"board"'*) ok 'post --json takes its place anywhere among the options' ;; *) no 'post --json takes its place anywhere among the options' "$out2" ;; esac
out3=$(printf 'from stdin\n' | "$room/.moot/moot.sh" post --json --room board --as ben -)
case $out3 in *'"ok":true'*'"path":"rooms/board/posts/'*) ok 'post --json --room <room> - posts from stdin' ;; *) no 'post --json --room <room> - posts from stdin' "$out3" ;; esac

id=$(printf '%s' "$out" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
check 'post body is the file, byte for byte' "$(cat "$room/.moot/rooms/board/posts/$id.md")" 'first'
case $id in [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]-ben) ok 'post id follows the filename grammar' ;; *) no 'post id follows the filename grammar' "$id" ;; esac

echo 'from stdin' | "$room/.moot/moot.sh" post --as ben - >/dev/null
printf 'from a file\n' > "$work/msg.md"
"$room/.moot/moot.sh" post --as ben -f "$work/msg.md" >/dev/null
check 'post accepts -m, -, and -f' "$(ls "$room/.moot/rooms/board/posts"/*.md | wc -l | tr -d ' ')" '5'

refuses 'post refuses an empty message' 'empty message' m post --as ben -m ''
refuses 'post refuses an unsafe sender name' 'not filename-safe' m post --as 'bad name' -m 'x'

check 'there is no edit verb'   "$("$room/.moot/moot.sh" edit x 2>&1 >/dev/null | tail -1)" 'moot: unknown command: edit'
check 'there is no delete verb' "$("$room/.moot/moot.sh" delete x 2>&1 >/dev/null | tail -1)" 'moot: unknown command: delete'

group 'post is atomic'
room=$(new_room)
"$room/.moot/moot.sh" post --as ben -m 'done' >/dev/null
check 'post leaves no landing file' "$(ls -A "$room/.moot/rooms/board/posts" | grep -c landing)" '0'
# A post mid-compose must be invisible to every reader, tool or human.
: > "$room/.moot/rooms/board/posts/.20260829-120000-alice.999.landing"
check 'a landing file is not a post' "$("$room/.moot/moot.sh" read | grep -c 'alice')" '0'
check 'a landing file is not in posts/*' "$(printf '%s\n' "$room"/.moot/rooms/board/posts/* | grep -c landing)" '0'

group 'same-second collision'
# A clock that hands out the given stamps in turn (repeating the last), and a
# sleep that returns at once, so a re-stamp is deterministic and instant.
step_date() {
  local bin="$work/bin" list="$work/stamps"
  mkdir -p "$bin"
  printf '%s\n' "$@" > "$list"
  cat > "$bin/date" <<STUB
#!/bin/sh
first=\$(head -n 1 "$list")
rest=\$(tail -n +2 "$list")
[ -n "\$rest" ] && printf '%s\n' "\$rest" > "$list"
echo "\$first"
STUB
  printf '#!/bin/sh\nexit 0\n' > "$bin/sleep"
  chmod +x "$bin/date" "$bin/sleep"
  PATH="$bin:$PATH"
}
thaw_step() { rm -f "$work/bin/sleep"; thaw_date; }

room=$(new_room)
posts="$room/.moot/rooms/board/posts"
# Three posts, the clock catching up a second at a time.
step_date 20260829-163412 20260829-163412 20260829-163413 20260829-163413 20260829-163414
"$room/.moot/moot.sh" post --as alice -m 'one' >/dev/null
"$room/.moot/moot.sh" post --as alice -m 'two' >/dev/null
"$room/.moot/moot.sh" post --as alice -m 'three' >/dev/null
thaw_step
check 'a same-second clash re-stamps instead of suffixing' "$(ls "$posts" | tr '\n' ' ')" \
  '20260829-163412-alice.md 20260829-163413-alice.md 20260829-163414-alice.md '
check 'no post was overwritten' "$(cat "$posts/20260829-163412-alice.md")" 'one'
check 'the re-stamped post kept its own body' "$(cat "$posts/20260829-163414-alice.md")" 'three'
check 'read shows them in the order written' \
  "$("$room/.moot/moot.sh" read | grep -E '^(one|two|three)$' | tr '\n' ' ')" 'one two three '
check 'read names the sender plainly' "$("$room/.moot/moot.sh" read | grep -c '· alice ──')" '3'

# A hyphenated sender, the case a -N suffix could not be told apart from.
room=$(new_room)
posts="$room/.moot/rooms/board/posts"
step_date 20260829-163412 20260829-163412 20260829-163413
"$room/.moot/moot.sh" post --as alice-bot -m 'a' >/dev/null
"$room/.moot/moot.sh" post --as alice-bot -m 'b' >/dev/null
thaw_step
check 'a hyphenated sender re-stamps too' "$(ls "$posts" | tr '\n' ' ')" \
  '20260829-163412-alice-bot.md 20260829-163413-alice-bot.md '

# A directory post holds the id as surely as a file does.
room=$(new_room)
posts="$room/.moot/rooms/board/posts"
mkdir "$posts/20260829-163412-ben"; printf 'with files\n' > "$posts/20260829-163412-ben/post.md"
step_date 20260829-163412 20260829-163413
"$room/.moot/moot.sh" post --as ben -m 'plain' >/dev/null
thaw_step
[ -f "$posts/20260829-163413-ben.md" ] && ok 'a directory post of the same id counts as taken' \
  || no 'a directory post of the same id counts as taken'

# A clock that never moves gives up rather than spin.
room=$(new_room)
posts="$room/.moot/rooms/board/posts"
step_date 20260829-163412
"$room/.moot/moot.sh" post --as alice -m 'first' >/dev/null
err=$("$room/.moot/moot.sh" post --as alice -m 'stuck' 2>&1 >/dev/null); rc=$?
thaw_step
[ "$rc" -ne 0 ] && ok 'a stopped clock fails the post' || no 'a stopped clock fails the post'
check 'and says why' "$(printf '%s' "$err" | grep -c 'clock is not moving')" '1'
check 'and leaves no landing file behind' "$(ls -A "$posts" | grep -c landing)" '0'
check 'and claims nothing' "$(ls "$posts" | wc -l | tr -d ' ')" '1'

# Only a clock that stays put counts against the retries. Seven earlier posts
# under the same name, and a clock that moves a second each time: the post
# must wait its way past all of them rather than give up after five.
room=$(new_room)
posts="$room/.moot/rooms/board/posts"
for t in 12 13 14 15 16 17 18; do printf 'earlier %s\n' "$t" > "$posts/20260829-1634$t-alice.md"; done
step_date 20260829-163412 20260829-163413 20260829-163414 20260829-163415 20260829-163416 20260829-163417 20260829-163418 20260829-163419
"$room/.moot/moot.sh" post --as alice -m 'late but landed' >/dev/null; rc=$?
thaw_step
check 'a post that waits more than five seconds still lands' "$rc" '0'
check 'and lands on the first free second' "$(cat "$posts/20260829-163419-alice.md" 2>/dev/null)" 'late but landed'

# A burst, on the real clock: four posts under one name at once. Each takes the
# next free second, and every body lands.
room=$(new_room)
posts="$room/.moot/rooms/board/posts"
for i in 1 2 3 4; do "$room/.moot/moot.sh" post --as alice -m "burst $i" >/dev/null 2>"$work/burst.$i.err" & done
wait
check 'four concurrent posts under one name all land' "$(ls "$posts"/*.md | wc -l | tr -d ' ')" '4'
check 'and each body is there' "$(cat "$posts"/*.md | sort | tr '\n' ' ')" 'burst 1 burst 2 burst 3 burst 4 '
check 'and none of them died' "$(cat "$work"/burst.*.err | wc -c | tr -d ' ')" '0'
check 'and no landing file is left' "$(ls -A "$posts" | grep -c landing)" '0'

# ---------------------------------------------------------------- ordering

group 'ordering'
room=$(new_room)
for stamp in 20260829-120000 20260829-090000 20260830-010000 20260828-235959; do
  printf 'body %s\n' "$stamp" > "$room/.moot/rooms/board/posts/$stamp-ben.md"
done
out=$("$room/.moot/moot.sh" read | grep -c 'body ')
check 'read shows every post' "$out" '4'
first=$("$room/.moot/moot.sh" read | grep 'body ' | head -1)
last=$("$room/.moot/moot.sh" read | grep 'body ' | tail -1)
check 'read is newest-last: oldest first' "$first" 'body 20260828-235959'
check 'read is newest-last: newest last'  "$last"  'body 20260830-010000'
case $(TZ=UTC0 "$room/.moot/moot.sh" read | grep -m1 '──') in *'2026-08-28 23:59:59 +0000 · ben'*) ok 'the heading is built from the filename' ;; *) no 'the heading is built from the filename' ;; esac

group 'read --since and --tail'
check '--since is exclusive of its own post' \
  "$("$room/.moot/moot.sh" read --since 20260829-090000-ben | grep -c 'body ')" '2'
check '--since a later post shows nothing' \
  "$("$room/.moot/moot.sh" read --since 20260830-010000-ben | grep -c 'body ')" '0'
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
  "$("$room/.moot/moot.sh" read --since 20260828-235959-ben --tail 1 | grep 'body ')" 'body 20260830-010000'

group 'read on an empty board'
room=$(new_room)
"$room/.moot/moot.sh" read >/dev/null 2>&1 && ok 'read of an empty board succeeds' || no 'read of an empty board succeeds'
check 'read of an empty board says nothing' "$("$room/.moot/moot.sh" read | wc -c | tr -d ' ')" '0'

group 'read --follow is gone'
room=$(new_room)
refuses 'read --follow is refused' 'unknown option' m read --follow

# ---------------------------------------------------------------- attachments

group 'attachments'
room=$(new_room)
mkdir -p "$room/.moot/rooms/board/posts/20260829-164070-ben"
printf 'see the patch @alice\n' > "$room/.moot/rooms/board/posts/20260829-164070-ben/post.md"
printf 'diff goes here\n' > "$room/.moot/rooms/board/posts/20260829-164070-ben/diff.patch"
printf 'a plain one\n' > "$room/.moot/rooms/board/posts/20260829-170000-alice.md"
out=$("$room/.moot/moot.sh" read)
case $out in *'see the patch @alice'*) ok 'an attachment post renders post.md' ;; *) no 'an attachment post renders post.md' ;; esac
case $out in *'attached: diff.patch'*) ok 'an attachment post lists its files' ;; *) no 'an attachment post lists its files' "$out" ;; esac
case $out in *'attached: post.md'*) no 'post.md is not listed as an attachment' ;; *) ok 'post.md is not listed as an attachment' ;; esac
case $out in *'2026-08-29 16:40:70 UTC · ben'*) ok 'an attachment directory gets a normal heading' ;; *) no 'an attachment directory gets a normal heading' ;; esac
check 'an attachment post is one post, not many' "$(printf '%s\n' "$out" | grep -c '──')" '2'
check 'an attachment post has a --since id' \
  "$("$room/.moot/moot.sh" read --since 20260829-164070-ben | grep -c 'a plain one')" '1'

# ---------------------------------------------------------------- name resolution

group 'name resolution'
room=$(new_room)
sender_of() { ls "$1/.moot/rooms/board/posts"/*.md | sed -n 's/.*-\([^-]*\)\.md$/\1/p' | tail -1; }

MOOT_NAME=envname USER=username "$room/.moot/moot.sh" post --as flagname -m 'x' >/dev/null
check '--as wins' "$(sender_of "$room")" 'flagname'

room=$(new_room)
MOOT_NAME=envname USER=username "$room/.moot/moot.sh" post -m 'x' >/dev/null
check '$MOOT_NAME comes next' "$(sender_of "$room")" 'envname'

room=$(new_room)
printf 'localname\n' > "$room/.moot/name"
mkdir -p "$room/.gremlin"
printf 'name=alice\n' > "$room/.gremlin/name"
( cd "$room" && MOOT_NAME= USER=username "$room/.moot/moot.sh" post -m 'x' >/dev/null )
check '.moot/name comes next' "$(sender_of "$room")" 'localname'

# .gremlin/name is a key=value file. Taking the whole line yields "name=alice",
# which is not a filename-safe sender.
room=$(new_room)
mkdir -p "$room/.gremlin"
printf 'name=alice\nsource=generated\nvocabulary=1\n' > "$room/.gremlin/name"
( cd "$room" && MOOT_NAME= USER=username "$room/.moot/moot.sh" post -m 'x' >/dev/null )
check '.gremlin/name comes next' "$(sender_of "$room")" 'alice'

room=$(new_room)
mkdir -p "$room/.gremlin"
printf 'alice\n' > "$room/.gremlin/name"
( cd "$room" && MOOT_NAME= USER=username "$room/.moot/moot.sh" post -m 'x' >/dev/null )
check 'a bare .gremlin/name still resolves' "$(sender_of "$room")" 'alice'

room=$(new_room)
printf 'bad=name\n' > "$room/.moot/name"
( cd "$room" && MOOT_NAME= USER=username "$room/.moot/moot.sh" post -m 'x' >/dev/null 2>&1 ) \
  && no 'an unsafe .moot/name is an error' || ok 'an unsafe .moot/name is an error'


# A gremlin posts under its own name, not its folder's. .gremlin/ is a sibling
# of .moot/, so the name resolves from the script's own location and the
# working directory does not come into it.
room=$(new_room)
mkdir -p "$room/.gremlin" "$room/deep/nested"
printf 'name=fanta\n' > "$room/.gremlin/name"
( cd "$room/deep/nested" && MOOT_NAME= USER=username "$room/.moot/moot.sh" post -m 'x' >/dev/null )
check 'the sibling .gremlin/name resolves from a subdirectory' "$(sender_of "$room")" 'fanta'
room=$(new_room)
mkdir -p "$room/.gremlin"
printf 'name=fanta\n' > "$room/.gremlin/name"
( cd / && MOOT_NAME= USER=username "$room/.moot/moot.sh" post -m 'x' >/dev/null )
check 'and from outside the host entirely' "$(sender_of "$room")" 'fanta'

# A .gremlin/ somewhere above the host is not this participant's gremlin.
outer=$(mktemp -d "$work/outer.XXXXXX")
mkdir -p "$outer/.gremlin"
printf 'name=notmine\n' > "$outer/.gremlin/name"
inner="$outer/host"; mkdir -p "$inner"
"$repo/install.sh" "$inner" >/dev/null
keep "$inner" board
( cd "$inner" && MOOT_NAME= USER=username "$inner/.moot/moot.sh" post -m 'x' >/dev/null )
check 'an ancestor .gremlin/name is not a sibling' "$(sender_of "$inner")" 'host'

# The wiring line a gremlin host runs is relative, from the host root.
room=$(new_room)
mkdir -p "$room/.gremlin" "$room/.nest/in"
printf 'name=fanta\n' > "$room/.gremlin/name"
printf '@fanta over to you\n' > "$room/.moot/rooms/board/posts/20260829-100000-ben.md"
( cd "$room" && MOOT_NAME= USER=username ./.moot/moot.sh read --new --deliver .nest/in/ >/dev/null )
check 'the relative wiring line delivers' "$(ls "$room/.nest/in" | wc -l | tr -d ' ')" '1'

# The last resort is the folder .moot/ sits in, so a repo needs no name file.
named="$work/myApp"; mkdir -p "$named"
"$repo/install.sh" "$named" >/dev/null; keep "$named" board
( cd "$work" && MOOT_NAME= USER=username "$named/.moot/moot.sh" post -m 'x' >/dev/null )
check 'the host folder name is the last resort, not $USER' "$(sender_of "$named")" 'myApp'
( cd / && env -u MOOT_NAME -u USER "$named/.moot/moot.sh" post -m 'y' >/dev/null )
check 'and needs no $USER at all' "$(ls "$named/.moot/rooms/board/posts" | grep -c 'myApp')" '2'

spaced="$work/My Project"; mkdir -p "$spaced"
"$repo/install.sh" "$spaced" >/dev/null; keep "$spaced" board
err=$( cd "$work" && MOOT_NAME= "$spaced/.moot/moot.sh" post -m 'x' 2>&1 >/dev/null ) \
  && no 'an unsafe folder name is an error' || ok 'an unsafe folder name is an error'
check 'and the error names the fix' "$(printf '%s' "$err" | grep -c '.moot/name')" '1'
printf 'pedal\n' > "$spaced/.moot/name"
( cd "$work" && MOOT_NAME= "$spaced/.moot/moot.sh" post -m 'x' >/dev/null )
check '.moot/name rescues it' "$(sender_of "$spaced")" 'pedal'

# ---------------------------------------------------------------- no tool needed

group 'a moot needs no tool'
room=$(new_room)
# The hand-posting incantation from the README must produce a readable post.
( cd "$room" && echo 'posted by hand' > ".moot/rooms/board/posts/$(date -u +%Y%m%d-%H%M%S)-ben.md" )
check 'a hand-written post is a post' "$("$room/.moot/moot.sh" read | grep -c 'posted by hand')" '1'
"$room/.moot/moot.sh" post --as alice -m 'posted by tool' >/dev/null
check 'a tool-written post is readable by hand' "$(cat "$room"/.moot/rooms/board/posts/*-alice.md)" 'posted by tool'

# ---------------------------------------------------------------- read --new --mentions

group 'read --new --mentions'
room=$(new_room)

say 20260829-100000-ben   'board is up'
say 20260829-100100-ben   'hey @alice can you look at the thing'
say 20260829-100200-ben   'unrelated announcement'
say 20260829-100300-ben   '@all standup moved'
say 20260829-100400-ben   'nice work @fanta'

out=$(m read --new --mentions --as alice)
check '--mentions shows a direct mention' "$(printf '%s' "$out" | grep -c 'can you look at')" '1'
check '--mentions shows @all'             "$(printf '%s' "$out" | grep -c 'standup moved')" '1'
check '--mentions skips an unmentioned post' "$(printf '%s' "$out" | grep -c 'unrelated')" '0'
check '--mentions skips someone else atted'  "$(printf '%s' "$out" | grep -c 'nice work')" '0'
check 'the heading counts what mentions me'  "$(printf '%s' "$out" | grep -c '══ board · 2 for alice ══')" '1'
check '--mentions writes the cursor past everything' "$(cat "$room/.moot/seen/board/alice")" '20260829-100400-ben'

out=$(m read --new --mentions --as alice)
check 'a re-run shows nothing'  "$(printf '%s' "$out" | grep -c 'can you look at')" '0'
check 'and says so' "$out" 'nothing new for alice'
check 'the cursor did not move back' "$(cat "$room/.moot/seen/board/alice")" '20260829-100400-ben'

say 20260829-100500-ben '@alice one more'
out=$(m read --new --mentions --as alice)
check '--mentions resumes from the cursor' "$(printf '%s' "$out" | grep -c 'one more')" '1'
check 'and does not repeat older mentions' "$(printf '%s' "$out" | grep -c 'can you look at')" '0'
check 'the whole board is still readable' "$(m read | grep -c 'unrelated announcement')" '1'

group 'read --new shows every post'
room=$(new_room)
say 20260829-100000-ben 'an announcement'
say 20260829-100100-ben '@alice a mention'
out=$(m read --new --as alice)
check 'without --mentions the announcement shows' "$(printf '%s' "$out" | grep -c 'an announcement')" '1'
check 'and so does the mention' "$(printf '%s' "$out" | grep -c 'a mention')" '1'
check 'and the heading counts them all' "$(printf '%s' "$out" | grep -c '══ board · 2 new ══')" '1'
refuses 'plain read refuses --mentions' 'only go with --new' m read --room board --mentions
refuses 'plain read refuses --deliver' 'only go with --new' m read --room board --deliver "$work/nowhere-inbox"

group 'mentions in code'
room=$(new_room)
say 20260829-100000-ben 'the flag waits for an `@alice` or `@all`'
printf 'example:\n\n```sh\nmoot.sh post -m "@all standup"\n```\n' > "$room/.moot/rooms/board/posts/20260829-100100-ben.md"
say 20260829-100200-ben 'use `watch --mentions`, @alice please try it'
say 20260829-100300-ben 'an unclosed ` @alice still counts'
out=$(m read --new --mentions --as alice)
check 'an @ in an inline code span is not a mention' "$(printf '%s' "$out" | grep -c 'the flag waits')" '0'
check 'an @ in a fenced block is not a mention' "$(printf '%s' "$out" | grep -c 'standup')" '0'
check 'an @ beside a code span still is' "$(printf '%s' "$out" | grep -c 'please try it')" '1'
check 'an unclosed backtick hides nothing' "$(printf '%s' "$out" | grep -c 'still counts')" '1'

group 'a mention of nobody'
room=$(new_room)
say 20260829-100000-ben 'hello @nobodyatall'
out=$(m read --new --mentions --as alice)
check 'a mention of nobody reaches nobody' "$(printf '%s' "$out" | grep -c 'hello')" '0'
check 'a mention of nobody still advances the cursor' "$(cat "$room/.moot/seen/board/alice")" '20260829-100000-ben'
check 'the mistyped mention is visible on the board' "$(m read | grep -c '@nobodyatall')" '1'

group 'mention matching'
room=$(new_room)
say 20260829-100000-ben 'thanks @alice.'
say 20260829-100100-ben 'ask @alice, please'
say 20260829-100200-ben 'not @alicelike'
say 20260829-100300-ben 'an email a@alice is not a mention of a'
out=$(m read --new --mentions --as alice)
check 'a trailing full stop still mentions'   "$(printf '%s' "$out" | grep -c 'thanks')" '1'
check 'a trailing comma still mentions'       "$(printf '%s' "$out" | grep -c 'please')" '1'
check 'a longer name is a different name'     "$(printf '%s' "$out" | grep -c 'not @alicelike')" '0'

# Under bash 3.2 a pass over a few hundred posts aborted (exit 134) about half
# the time while mention matching opened a process substitution per post
# (reported 2026-11-23). Three cursorless passes over 300 posts catch it
# most runs; run the suite with /bin/bash first on PATH to test 3.2.
group 'a long mentions pass'
room=$(new_room)
for i in $(seq 100 399); do
  if [ $((i % 3)) = 0 ]; then say "20260829-100$i-ben" "ask @alice about $i"; else say "20260829-100$i-ben" "note $i"; fi
done
rcs=''
for i in 1 2 3; do
  rm -f "$room/.moot/seen/board/alice"
  out=$(m read --new --mentions --as alice); rc=$?
  rcs="$rcs$rc:$(printf '%s\n' "$out" | grep -c '^── ') "
done
check 'three passes over 300 posts each exit 0 and find all 100 mentions' "$rcs" '0:100 0:100 0:100 '

group 'read --new --deliver'
room=$(new_room)
inbox="$work/inbox"; rm -rf "$inbox"
say 20260829-100000-ben 'quiet announcement'
say 20260829-100100-ben '@alice please handle the thing ben raised earlier'
out=$(m read --new --as alice --deliver "$inbox")
check '--deliver implies --mentions: one file for the one mention' "$(ls "$inbox" | wc -l | tr -d ' ')" '1'
check '--deliver prints one summary line' "$out" "delivered 1 mention(s) to $(cd "$inbox" && pwd)"
delivered=$(ls "$inbox")
case $delivered in *20260829-100100-ben*) ok 'a delivered filename carries the post id' ;; *) no 'a delivered filename carries the post id' "$delivered" ;; esac
case $delivered in moot-board-*) ok 'a delivered filename carries the room' ;; *) no 'a delivered filename carries the room' "$delivered" ;; esac
check '--deliver leaves no landing file' "$(ls -A "$inbox" | grep -c landing)" '0'
body=$(cat "$inbox/$delivered")
case $body in *"please handle the thing"*) ok 'a delivered item carries the body' ;; *) no 'a delivered item carries the body' ;; esac
case $body in *"$room"*) ok 'a delivered item carries the path to the room' ;; *) no 'a delivered item carries the path to the room' ;; esac
case $body in *'20260829-100100-ben'*) ok 'a delivered item carries its own post id' ;; *) no 'a delivered item carries its own post id' ;; esac
case $body in *'read --room board --tail'*) ok 'a delivered item says how to read backwards' ;; *) no 'a delivered item says how to read backwards' "$body" ;; esac
case $body in *'- room: `board`'*) ok 'a delivered item names its room' ;; *) no 'a delivered item names its room' "$body" ;; esac
check '--deliver delivers only mentions' "$(grep -rc 'quiet announcement' "$inbox" | grep -c ':1$')" '0'
check '--deliver prints no post to the terminal' "$(printf '%s' "$out" | grep -c 'please handle')" '0'

m read --new --as alice --deliver "$inbox" >/dev/null
check 'a re-run delivers nothing twice' "$(ls "$inbox" | wc -l | tr -d ' ')" '1'

# Moot does not know what a nest is: gremlin integration is a path.
rm -rf "$work/nest"; mkdir -p "$work/nest/in"
rm -f "$room/.moot/seen/board/alice"; : > "$room/.moot/seen/board/.joined"
m read --new --as alice --deliver "$work/nest/in" >/dev/null
check '--deliver takes any directory the caller names' "$(ls "$work/nest/in" | wc -l | tr -d ' ')" '1'
rm -f "$room/.moot/seen/board/alice"; : > "$room/.moot/seen/board/.joined"
m read --new --as alice --deliver "$work/nest/in" >/dev/null
check 'even with the cursor gone, nothing is delivered twice' "$(ls "$work/nest/in" | wc -l | tr -d ' ')" '1'
out=$(m read --new --as alice --deliver "$work/nest/in")
check 'and an empty heartbeat says nothing new' "$out" 'nothing new for alice'

group 'read --new on a read-only moot'
room=$(new_room)
say 20260829-100000-ben '@alice the board is read-only from here'
inbox="$work/ro-inbox"; rm -rf "$inbox"; mkdir -p "$inbox"
mkdir -p "$room/.moot/seen/board"
chmod -w "$room/.moot/seen/board"
m read --new --as alice --deliver "$inbox" >/dev/null 2>"$work/ro.err"
check 'a read-only moot still delivers' "$(ls "$inbox" | wc -l | tr -d ' ')" '1'
check 'a read-only moot warns about the cursor' "$(grep -c 'read-only room' "$work/ro.err")" '1'
m read --new --as alice --deliver "$inbox" >/dev/null 2>&1
check 'a read-only moot still delivers nothing twice' "$(ls "$inbox" | wc -l | tr -d ' ')" '1'
chmod +w "$room/.moot/seen/board"

group 'read --new --mentions name resolution'
room=$(new_room)
mkdir -p "$room/.gremlin"; printf 'name=fanta\n' > "$room/.gremlin/name"
say 20260829-100000-ben '@fanta over to you'
( cd "$room" && MOOT_NAME= USER=username "$room/.moot/moot.sh" read --new --mentions >/dev/null )
[ -f "$room/.moot/seen/board/fanta" ] && ok 'read --new uses the same name chain as post' || no 'read --new uses the same name chain as post'

group 'a read --new pass covers every room'
host=$(new_host)
for r in board release ops; do
  own "$host" "$r"
  printf '@alice the %s thing\n' "$r" > "$host/.moot/rooms/$r/posts/20260829-100000-ben.md"
done
inbox="$work/pass-inbox"; rm -rf "$inbox"
out=$(j read --new --as alice --deliver "$inbox")
check 'one call delivers from every room' "$(ls "$inbox" | wc -l | tr -d ' ')" '3'
check 'and says so on one line' "$(printf '%s' "$out" | wc -l | tr -d ' ')" '0'
check 'the pass advances every cursor' "$(ls "$host/.moot/seen"/*/alice | wc -l | tr -d ' ')" '3'
j read --new --as alice --deliver "$inbox" >/dev/null
check 'a second pass delivers nothing twice' "$(ls "$inbox" | wc -l | tr -d ' ')" '3'

# Two rooms can produce the same post id in the same second from the same
# sender. The filename is the whole duplicate-suppression mechanism.
host=$(new_host)
own "$host" board; own "$host" release
printf '@alice same second, board\n' > "$host/.moot/rooms/board/posts/20260829-100000-ben.md"
printf '@alice same second, release\n' > "$host/.moot/rooms/release/posts/20260829-100000-ben.md"
inbox="$work/clash-inbox"; rm -rf "$inbox"
j read --new --as alice --deliver "$inbox" >/dev/null
check 'a same-second clash across rooms delivers both' "$(ls "$inbox" | wc -l | tr -d ' ')" '2'
check 'and neither body was lost' "$(cat "$inbox"/* | grep -c 'same second,')" '2'

group 'read --new --room narrows the pass'
host=$(new_host)
own "$host" board; own "$host" release
printf '@alice board\n' > "$host/.moot/rooms/board/posts/20260829-100000-ben.md"
printf '@alice release\n' > "$host/.moot/rooms/release/posts/20260829-100000-ben.md"
inbox="$work/narrow-inbox"; rm -rf "$inbox"
j read --new --as alice --room board --deliver "$inbox" >/dev/null
check '--room delivers from that room only' "$(ls "$inbox" | wc -l | tr -d ' ')" '1'
[ -f "$host/.moot/seen/board/alice" ] && ok '--room advances that cursor' || no '--room advances that cursor'
[ -e "$host/.moot/seen/release/alice" ] && no '--room leaves the other cursor alone' || ok '--room leaves the other cursor alone'
refuses '--room on a room that is not here is an error' 'no room nosuch' j read --new --as alice --room nosuch

group 'a read-only room does not stop the pass'
host=$(new_host)
# bb has no mark, so its delivery can't record "now" and must still deliver.
for r in aa bb cc; do
  if [ "$r" = bb ]; then keep "$host" "$r"; else own "$host" "$r"; fi
  printf '@alice the %s thing\n' "$r" > "$host/.moot/rooms/$r/posts/20260829-100000-ben.md"
done
mkdir -p "$host/.moot/seen/bb"; chmod -w "$host/.moot/seen/bb"
inbox="$work/ro-pass"; rm -rf "$inbox"
j read --new --as alice --deliver "$inbox" >/dev/null 2>"$work/ro-pass.err"
check 'the read-only room still delivered' "$(ls "$inbox" | wc -l | tr -d ' ')" '3'
check 'and warned about its cursor' "$(grep -c 'read-only room' "$work/ro-pass.err")" '1'
[ -f "$host/.moot/seen/cc/alice" ] && ok 'the room after it was still read' || no 'the room after it was still read'
chmod +w "$host/.moot/seen/bb"

group 'read --new with no rooms at all'
host=$(new_host)
"$host/.moot/moot.sh" read --new --as alice >/dev/null 2>&1 && ok 'a host with no rooms exits clean' || no 'a host with no rooms exits clean'
check 'and says nothing new' "$("$host/.moot/moot.sh" read --new --as alice 2>&1)" 'nothing new for alice'
check 'also with --deliver' "$("$host/.moot/moot.sh" read --new --as alice --deliver "$work/none-inbox" 2>&1)" 'nothing new for alice'

group 'read --new on an empty board'
room=$(new_room)
"$room/.moot/moot.sh" read --new --as alice >/dev/null 2>&1 && ok 'an empty board succeeds' || no 'an empty board succeeds'
[ -e "$room/.moot/seen/board/alice" ] && no 'an empty board writes no cursor' || ok 'an empty board writes no cursor'

group 'read --new and attachments'
room=$(new_room)
mkdir -p "$room/.moot/rooms/board/posts/20260829-100000-ben"
printf '@alice see the patch\n' > "$room/.moot/rooms/board/posts/20260829-100000-ben/post.md"
printf 'diff\n' > "$room/.moot/rooms/board/posts/20260829-100000-ben/diff.patch"
inbox="$work/att-inbox"; rm -rf "$inbox"
m read --new --as alice --deliver "$inbox" >/dev/null
check 'an attachment post is delivered' "$(ls "$inbox" | wc -l | tr -d ' ')" '1'
case $(cat "$inbox"/*) in *'diff.patch'*) ok 'a delivered attachment post points at its files' ;; *) no 'a delivered attachment post points at its files' ;; esac

group 'catchup is a deprecated alias'
room=$(new_room)
say 20260829-100000-ben 'an announcement'
say 20260829-100100-ben '@alice please look'
out=$(m catchup --as alice)
check 'catchup shows what mentions me' "$(printf '%s' "$out" | grep -c 'please look')" '1'
check 'and hides the announcements, as it always did' "$(printf '%s' "$out" | grep -c 'an announcement')" '0'
check 'and moves the same cursor' "$(cat "$room/.moot/seen/board/alice")" '20260829-100100-ben'
say 20260829-100200-ben '@alice again'
inbox="$work/alias-inbox"; rm -rf "$inbox"
m catchup --as alice --deliver "$inbox" >/dev/null
check 'catchup --deliver still delivers' "$(ls "$inbox" | wc -l | tr -d ' ')" '1'
refuses 'catchup --json is gone' 'unknown option' m catchup --json

# ---------------------------------------------------------------- install

group 'install'
host=$(new_host)
[ -x "$host/.moot/moot.sh" ] && ok 'install deploys an executable moot.sh' || no 'install deploys an executable moot.sh'
[ -f "$host/.moot/README.md" ] && ok 'install deploys the README' || no 'install deploys the README'
[ -f "$host/.moot/SKILL.md" ] && ok 'install deploys the skill as SKILL.md' || no 'install deploys the skill as SKILL.md'
cmp -s "$repo/.moot/SKILL.md" "$host/.moot/SKILL.md" && ok 'SKILL.md is the skill from .moot/SKILL.md' || no 'SKILL.md is the skill from .moot/SKILL.md'
check 'install claims nothing outside .moot/' "$(ls -A "$host")" '.moot'
printf 'stale\n' > "$host/.moot/SKILL.md"
"$repo/install.sh" "$host" >/dev/null
cmp -s "$repo/.moot/SKILL.md" "$host/.moot/SKILL.md" && ok 're-running install refreshes the skill' || no 're-running install refreshes the skill'
check 'install is repeatable' "$(ls -A "$host/.moot" | wc -l | tr -d ' ')" '4'

# The tracked .moot/ ships its own .gitignore for this participant's state, and
# install copies it. Install writes no .gitignore in the host (the pair itself
# is tested under 'the .gitignore pair').
hint=$("$repo/install.sh" "$host")
case $hint in *'join <path-to-room>'*) ok 'install hints at join <path-to-room>' ;; *) no 'install hints at join <path-to-room>' "$hint" ;; esac
case $hint in *'moot.sh create <room>'*) ok 'and at keeping a room with create' ;; *) no 'and at keeping a room with create' "$hint" ;; esac
[ ! -e "$host/.gitignore" ] && ok 'install writes no .gitignore in the host' || no 'install writes no .gitignore in the host'

# Run through a symlink, install still finds the files beside the real script,
# whether the link target is absolute or relative to the link's folder.
host=$(mktemp -d "$work/viaarg.XXXXXX"); bindir=$(mktemp -d "$work/bin-links.XXXXXX")
ln -s "$repo/install.sh" "$bindir/moot-install"
"$bindir/moot-install" "$host" >/dev/null 2>&1 && ok 'install runs through an absolute symlink' || no 'install runs through an absolute symlink'
cmp -s "$repo/.moot/moot.sh" "$host/.moot/moot.sh" && ok 'and installs the real moot.sh' || no 'and installs the real moot.sh'
host=$(mktemp -d "$work/viarel.XXXXXX"); mkdir -p "$work/two/bin"
ln -s "$repo" "$work/two/repo"; ln -s ../repo/install.sh "$work/two/bin/link-install"
"$work/two/bin/link-install" "$host" >/dev/null 2>&1 && ok 'install runs through a relative symlink' || no 'install runs through a relative symlink'
# A script without its siblings fails before it makes anything.
host=$(mktemp -d "$work/lonely.XXXXXX"); mkdir "$work/lonely-src"; cp "$repo/install.sh" "$work/lonely-src/"
err=$("$work/lonely-src/install.sh" "$host" 2>&1 >/dev/null); rc=$?
[ "$rc" -ne 0 ] && ok 'install with files missing fails' || no 'install with files missing fails'
check 'and says what it could not find' "$(printf '%s' "$err" | grep -c 'cannot find .moot/moot.sh')" '1'
[ -e "$host/.moot" ] && no 'and leaves no empty .moot/ behind' || ok 'and leaves no empty .moot/ behind'

# install.sh upgrades. Over a copied, customised .moot/, what the host owns
# survives byte for byte, what moot ships refreshes, and a second run changes
# nothing. A host adds its linked rooms to .moot/.gitignore, so that file is the
# host's once it exists.
host=$(mktemp -d "$work/upgrade.XXXXXX")
cp -R "$repo/.moot" "$host/.moot"
printf '# older script\n' > "$host/.moot/moot.sh"; chmod +x "$host/.moot/moot.sh"
printf 'older readme\n' > "$host/.moot/README.md"
printf 'older skill\n' > "$host/.moot/SKILL.md"
printf 'seen/\nname\nroom\nrooms/dev\n' > "$host/.moot/.gitignore"
mkdir -p "$host/.moot/rooms/board/posts" "$host/.moot/seen/board"
printf 'a post\n' > "$host/.moot/rooms/board/posts/20260101T000000Z-alice-1.md"
printf 'cursor\n' > "$host/.moot/seen/board/alice"
printf 'alice\n' > "$host/.moot/name"
printf 'board\n' > "$host/.moot/room"
owned() { (cd "$host/.moot" && find . -type f ! -path ./moot.sh ! -path ./README.md ! -path ./SKILL.md -exec cksum {} + | sort); }
before=$(owned)
"$repo/install.sh" "$host" >/dev/null
check 'upgrade leaves rooms, seen, name, room and .gitignore byte for byte' "$(owned)" "$before"
check 'upgrade keeps the linked room the host added to .gitignore' "$(grep -c '^rooms/dev$' "$host/.moot/.gitignore")" '1'
for f in moot.sh README.md SKILL.md; do
  cmp -s "$repo/.moot/$f" "$host/.moot/$f" && ok "upgrade refreshes $f" || no "upgrade refreshes $f"
done
[ -x "$host/.moot/moot.sh" ] && ok 'upgrade leaves moot.sh executable' || no 'upgrade leaves moot.sh executable'
after=$(cd "$host/.moot" && find . -type f -exec cksum {} + | sort)
"$repo/install.sh" "$host" >/dev/null
check 'a second upgrade changes no file' "$(cd "$host/.moot" && find . -type f -exec cksum {} + | sort)" "$after"
# A missing .gitignore is seeded.
rm -f -- "$host/.moot/.gitignore"
"$repo/install.sh" "$host" >/dev/null
cmp -s "$repo/.moot/.gitignore" "$host/.moot/.gitignore" && ok 'upgrade seeds a missing .gitignore' || no 'upgrade seeds a missing .gitignore'
# Source and destination the same file: ./install.sh . inside a checkout.
selfcopy=$(mktemp -d "$work/selfcopy.XXXXXX")
cp -R "$repo/.moot" "$repo/install.sh" "$selfcopy/"
rm -rf -- "${selfcopy:?}/.moot/seen" "${selfcopy:?}/.moot/rooms" "${selfcopy:?}/.moot/name" "${selfcopy:?}/.moot/room"
( cd "$selfcopy" && ./install.sh . >/dev/null 2>&1 ) && ok 'install.sh . inside a checkout succeeds' || no 'install.sh . inside a checkout succeeds'
cmp -s "$repo/.moot/moot.sh" "$selfcopy/.moot/moot.sh" && ok '...and leaves moot.sh as it was' || no '...and leaves moot.sh as it was'

# .moot/ is a dotdir among dotdirs: installing beside the rest of the family
# touches none of it.
host=$(mktemp -d "$work/family.XXXXXX")
mkdir -p "$host/.loom/threads" "$host/.nest/in"
printf 'a thread\n' > "$host/.loom/threads/keep.md"
"$repo/install.sh" "$host" >/dev/null
check 'install leaves .loom/ alone' "$(cat "$host/.loom/threads/keep.md")" 'a thread'
[ -d "$host/.nest/in" ] && ok 'install leaves .nest/ alone' || no 'install leaves .nest/ alone'
check 'and the dotdirs are peers' "$(ls -A "$host" | tr '\n' ' ')" '.loom .moot .nest '

# The repo's own .moot/ is the copy unit: copied bare into an empty folder, with
# no install step, it works.
group 'plain copy of .moot/'
[ -x "$repo/.moot/moot.sh" ] && ok 'the repo tracks an executable .moot/moot.sh' || no 'the repo tracks an executable .moot/moot.sh'
[ -f "$repo/.moot/SKILL.md" ] && ok 'the repo tracks .moot/SKILL.md' || no 'the repo tracks .moot/SKILL.md'
[ ! -e "$repo/.gitignore" ] && ok 'the repo has no root .gitignore' || no 'the repo has no root .gitignore'
[ ! -e "$repo/moot.sh" ] && ok 'the repo has no root moot.sh' || no 'the repo has no root moot.sh'
plain=$(mktemp -d "$work/plain.XXXXXX")
cp -R "$repo/.moot" "$plain/"
# Remove any state a run in the repo itself left in the copy; the copy under
# test starts as a fresh checkout would.
rm -rf -- "${plain:?}/.moot/seen" "${plain:?}/.moot/rooms" "${plain:?}/.moot/name" "${plain:?}/.moot/room"
check 'a bare copy lists no rooms' "$("$plain/.moot/moot.sh" rooms | grep -c 'no rooms here yet')" '1'
"$plain/.moot/moot.sh" read --new --as alice >/dev/null && ok 'read --new works before any room' || no 'read --new works before any room'
keep "$plain" board; ok 'a bare copy keeps a room with mkdir alone'
"$plain/.moot/moot.sh" post --as alice -m 'hello' >/dev/null && ok 'a bare copy posts' || no 'a bare copy posts'
out=$("$plain/.moot/moot.sh" read)
case $out in *hello*) ok 'a bare copy reads the post back' ;; *) no 'a bare copy reads the post back' "$out" ;; esac
# read --new leaves the current second for the next pass, so give it an older post.
printf '@ben hello\n' > "$plain/.moot/rooms/board/posts/20260829-090000-alice.md"
"$plain/.moot/moot.sh" read --new --as ben >/dev/null && ok 'a bare copy catches up' || no 'a bare copy catches up'
[ -f "$plain/.moot/seen/board/ben" ] && ok 'and keeps the cursor in its own seen/' || no 'and keeps the cursor in its own seen/'
check 'the copy touches nothing outside .moot/' "$(ls -A "$plain")" '.moot'
# The tracked .moot/ carries no instance state: nothing git tracks there is
# per-participant.
if git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
  tracked=$(git -C "$repo" ls-files .moot | grep -E '^\.moot/(seen|rooms)/|^\.moot/(name|room|status)$' || true)
  check 'the repo tracks no instance state in .moot/' "$tracked" ''
fi

# Each participant keeps a copy of the room, and their state inside it. The
# folder that syncs is posts/, and nothing in it is written by two hands.
group 'two participants'
room=$(new_room)
printf '@alice morning\n' > "$room/.moot/rooms/board/posts/20260829-090000-ben.md"
twin="$work/twin"; rm -rf "$twin"; cp -r "$room" "$twin"
m read --new --as ben >/dev/null
"$twin/.moot/moot.sh" read --new --as alice >/dev/null
[ -e "$room/.moot/seen/board/alice" ] && no 'a cursor never travels to the other copy' || ok 'a cursor never travels to the other copy'
[ -e "$twin/.moot/seen/board/ben" ] && no 'the other copy holds only its own cursor' || ok 'the other copy holds only its own cursor'
"$twin/.moot/moot.sh" post --as alice -m 'on it' >/dev/null
before=$(cat "$room/.moot/seen/board/ben")
check 'the first read --new did write a cursor to compare against' "$before" '20260829-090000-ben'
rsync -a "$twin/.moot/rooms/board/posts/" "$room/.moot/rooms/board/posts/"; rsync -a "$room/.moot/rooms/board/posts/" "$twin/.moot/rooms/board/posts/"
check 'the rooms reconcile on posts/ alone' "$(ls "$room/.moot/rooms/board/posts"/*.md | wc -l | tr -d ' ')" '2'
check 'syncing the room leaves the cursor alone' "$(cat "$room/.moot/seen/board/ben")" "$before"

group 'rooms linked into several repos'
# One keeper holds the real room; two repos beside it link it in with join. Each
# repo keeps its own name (its folder) and its own cursor. No path has two writers.
parent=$(mktemp -d "$work/repos.XXXXXX")
"$repo/install.sh" "$parent" >/dev/null
printf 'ben\n' > "$parent/.moot/name"
keep "$parent" dev
for r in myApp carol; do
  mkdir -p "$parent/$r"
  "$repo/install.sh" "$parent/$r" >/dev/null
  ( cd "$work" && "$parent/$r/.moot/moot.sh" join "$parent/.moot/rooms/dev" >/dev/null )
done
app() { ( cd "$work" && MOOT_NAME= "$parent/myApp/.moot/moot.sh" "$@" ); }
h() { ( cd "$work" && MOOT_NAME= "$parent/.moot/moot.sh" "$@" ); }

check 'a linked room is a room' "$(app rooms | grep -c dev)" '1'
check 'and the keeper holds the real folder' "$([ -L "$parent/.moot/rooms/dev" ] && echo link || echo folder)" 'folder'
step_date 20260829-100000 20260829-100000 20260829-100000
app post -m '@carol dispatching two workers' >/dev/null
c post -m '@myApp ok, holding mine' >/dev/null
h post -m '@all usage is fine' >/dev/null
thaw_step
check 'three repos posting in one second get three ids' \
  "$(ls "$parent/.moot/rooms/dev/posts" | tr '\n' ' ')" \
  '20260829-100000-ben.md 20260829-100000-carol.md 20260829-100000-myApp.md '

out_e=$(c read --new --mentions)
check 'each repo catches up under its folder name' "$(printf '%s' "$out_e" | grep -c '══ dev · 2 for carol ══')" '1'
check 'and gets what mentions it' "$(printf '%s' "$out_e" | grep -c -e 'dispatching two workers' -e 'usage is fine')" '2'
[ -f "$parent/carol/.moot/seen/dev/carol" ] && ok 'the cursor lives in the reading repo' || no 'the cursor lives in the reading repo'
[ ! -e "$parent/.moot/seen/dev/carol" ] && ok 'and never in the keeper' || no 'and never in the keeper'
[ ! -e "$parent/.moot/rooms/dev/seen" ] && [ "$(ls -A "$parent/.moot/rooms/dev")" = posts ] \
  && ok 'the room holds posts/ and nothing else' || no 'the room holds posts/ and nothing else'
check "one repo's catch-up leaves another's cursor alone" "$(ls "$parent/myApp/.moot/seen/dev" 2>/dev/null | wc -l | tr -d ' ')" '0'
out_b=$(app read --new --mentions)
check 'the other repo still gets its own mentions' "$(printf '%s' "$out_b" | grep -c -e 'holding mine' -e 'usage is fine')" '2'
check 'and a second pass shows nothing twice' "$(app read --new --mentions)" 'nothing new for myApp'

group 'a pass leaves the current second for the next'
# A post can land in the second a pass reads, under a name that sorts below the
# cursor's (ben after carol). If the cursor moved onto that second, the late
# post would be skipped for good. The stubbed clock stands at the second
# being read; a pass leaves that second alone.
room=$(new_room)
say 20260829-095959-carol 'settled earlier'
say 20260829-100000-carol '@alice same second, sorts last'
freeze_date 20260829-100000
out=$(m read --new --mentions --as alice)
check 'a pass shows only what is settled' "$(printf '%s' "$out" | grep -c 'same second')" '0'
check 'and parks the cursor on the last settled post' "$(cat "$room/.moot/seen/board/alice")" '20260829-095959-carol'
say 20260829-100000-ben '@alice same second, sorts first'
thaw_date; freeze_date 20260829-100001
out=$(m read --new --mentions --as alice)
check 'the next pass shows both same-second posts' "$(printf '%s' "$out" | grep -c 'same second')" '2'
check 'in post-id order' "$(printf '%s' "$out" | grep 'same second' | tr '\n' '|')" '@alice same second, sorts first|@alice same second, sorts last|'
check 'and moves the cursor onto them' "$(cat "$room/.moot/seen/board/alice")" '20260829-100000-carol'
check 'and a third pass finds nothing' "$(m read --new --mentions --as alice)" 'nothing new for alice'
thaw_date

room=$(new_room)
say 20260829-100000-carol 'first, same second'
freeze_date 20260829-100000
check 'read --new shows nothing from the current second' "$(m read --new --as alice)" 'nothing new for alice'
[ -e "$room/.moot/seen/board/alice" ] && no 'and writes no cursor' || ok 'and writes no cursor'
say 20260829-100000-ben 'second, sorts first'
thaw_date; freeze_date 20260829-100001
out=$(m read --new --as alice)
check 'the next read --new shows both' "$(printf '%s' "$out" | grep -c -e 'first, same second' -e 'second, sorts first')" '2'
check 'in post-id order' "$(printf '%s' "$out" | grep -e 'first, same' -e 'second, sorts' | tr '\n' '|')" 'second, sorts first|first, same second|'
check 'and the heading counts them' "$(printf '%s' "$out" | grep -c '══ board · 2 new ══')" '1'
thaw_date

# Stamps from a clock ahead of mine wait too.
room=$(new_room)
say 20260829-100000-ben 'now'
say 20260829-100500-ben 'five minutes ahead of my clock'
freeze_date 20260829-100000
out=$(m read --new --as alice)
check 'a post stamped later than my clock is not read yet' "$(printf '%s' "$out" | grep -c 'ahead of my clock')" '0'
thaw_date
out=$(m read --new --as alice)
check 'and is read once the clock has passed it' "$(printf '%s' "$out" | grep -c -e 'ahead of my clock' -e 'now')" '2'
# A stray file that is not a stamp never moves the cursor (it would sort after
# every stamp, and park the cursor beyond every later post).
say README 'not a post'
say 20260829-100600-ben 'real post'
out=$(m read --new --as alice)
check 'a non-stamp file is not read by a pass' "$(printf '%s' "$out" | grep -c 'not a post')" '0'
check 'and does not hide the post after it' "$(printf '%s' "$out" | grep -c 'real post')" '1'
check 'because the cursor stays on the last stamp' "$(cat "$room/.moot/seen/board/alice")" '20260829-100600-ben'

# read --new through a linked room: each repo's cursor stays in its own seen/.
rp_dev() { printf '%s\n' "$2" > "$parent/.moot/rooms/dev/posts/$1.md"; }
rp_dev 20260829-110000-ben '@all a late note'
out=$(app read --new)
check 'read --new reads a linked room' "$(printf '%s' "$out" | grep -c 'a late note')" '1'
[ -f "$parent/myApp/.moot/seen/dev/myApp" ] && ok 'and its cursor is in the reading repo' || no 'and its cursor is in the reading repo'
[ ! -e "$parent/.moot/seen/dev/myApp" ] && ok 'and not in the keeper' || no 'and not in the keeper'
check "so another repo's --new still shows the post" "$(c read --new | grep -c 'a late note')" '1'
check 'and a second --new in the first repo shows nothing' "$(app read --new)" 'nothing new for myApp'

# ---------------------------------------------------------------- local time

group 'read headings are in local time'
room=$(new_room)
posts="$room/.moot/rooms/board/posts"
printf 'late\n' > "$posts/20260828-233000-alice.md"
head_of() { "$room/.moot/moot.sh" read | grep -m1 '──'; }
# POSIX zone strings, so the test needs no zoneinfo: XXX-11 is UTC+11.
heading_checks() {
  local label=$1
  case $(TZ=XXX-11 head_of) in *'2026-08-29 10:30:00 +1100 · alice'*) ok "$label: a +1100 reader sees the next day, 10:30" ;; *) no "$label: a +1100 reader sees the next day, 10:30" "$(TZ=XXX-11 head_of)" ;; esac
  case $(TZ=XXX+5 head_of) in *'2026-08-28 18:30:00 -0500 · alice'*) ok "$label: a -0500 reader sees 18:30 the same day" ;; *) no "$label: a -0500 reader sees 18:30 the same day" "$(TZ=XXX+5 head_of)" ;; esac
  case $(TZ=XXX-11 head_of) in *UTC*) no "$label: a local heading does not say UTC" ;; *) ok "$label: a local heading does not say UTC" ;; esac
}
heading_checks 'native date'
[ -e "$posts/20260828-233000-alice.md" ] && ok 'the filename stays UTC' || no 'the filename stays UTC'

# The other flavour of date, when this machine has one: GNU date as gdate on
# macOS, or the reverse is not testable (a Linux box has no BSD date to shim).
if command -v gdate >/dev/null 2>&1; then
  mkdir -p "$work/gnu"; ln -sf "$(command -v gdate)" "$work/gnu/date"
  PATH="$work/gnu:$PATH"
  heading_checks 'GNU date'
  PATH=${PATH#"$work/gnu:"}
else
  printf '  skip GNU date headings (no gdate here to shim as date)\n'
fi

# One date fork per heading, whichever flavour. A wrapper logs each call and
# runs the real date; five posts may cost one probe or two plus five headings.
fork_count() {
  mkdir -p "$work/count"
  printf '#!/bin/sh\necho x >> "%s/calls"\nexec "%s" "$@"\n' "$work/count" "$(command -v date)" > "$work/count/date"
  chmod +x "$work/count/date"; rm -f "$work/count/calls"
  PATH="$work/count:$PATH"
  "$room/.moot/moot.sh" read >/dev/null
  PATH=${PATH#"$work/count:"}
  wc -l < "$work/count/calls" | tr -d ' '
}
room=$(new_room)
posts="$room/.moot/rooms/board/posts"
for t in 100000 100100 100200 100300 100400; do printf 'x\n' > "$posts/20260829-$t-alice.md"; done
calls=$(fork_count)
[ "$calls" -le 7 ] && ok "five headings cost $calls date forks (one each, plus at most two probes)" || no 'five headings cost one date fork each' "$calls forks"
if command -v gdate >/dev/null 2>&1; then
  PATH="$work/gnu:$PATH"; calls=$(fork_count); PATH=${PATH#"$work/gnu:"}
  [ "$calls" -le 7 ] && ok "GNU date: five headings cost $calls date forks" || no 'GNU date: five headings cost one date fork each' "$calls forks"
fi

# A name in posts/ that is not a stamp shows as itself, not as a garbled time.
room=$(new_room)
posts="$room/.moot/rooms/board/posts"
printf 'odd\n' > "$posts/notastamp-alice.md"
printf 'readme\n' > "$posts/README.md"
out=$("$room/.moot/moot.sh" read)
check 'a non-stamp id is its own heading' "$(printf '%s' "$out" | grep '──' | tr '\n' '|')" '── README ──|── notastamp-alice ──|'
printf 'real\n' > "$posts/20260828-233000-alice.md"
check 'a stamped post beside them still gets a time and a sender' \
  "$(printf '%s' "$("$room/.moot/moot.sh" read)" | grep -c '· alice ──')" '1'
# A well-formed stamp that is not a real time keeps the UTC label.
printf 'impossible\n' > "$posts/20261399-250000-alice.md"
case $("$room/.moot/moot.sh" read | grep '──') in *'2026-13-99 25:00:00 UTC · alice'*) ok 'a stamp that is not a time falls back to UTC, not an error' ;; *) no 'a stamp that is not a time falls back to UTC, not an error' ;; esac

# ---------------------------------------------------------------- read --new

group 'read --new'
parent=$(mktemp -d "$work/new.XXXXXX")
mkdir -p "$parent/ben"
"$repo/install.sh" "$parent/ben" >/dev/null
mz() { ( cd "$work" && MOOT_NAME= TZ=XXX-11 "$parent/ben/.moot/moot.sh" "$@" ); }
keep "$parent/ben" runs; keep "$parent/ben" dev
rp() { printf '%s\n' "$2" > "$parent/ben/.moot/rooms/$1/posts/$3.md"; }
rp runs 'run one done' 20260829-100000-alice
rp runs '@ben please look' 20260829-110000-alice
rp dev  'dev note' 20260829-103000-carol

out=$(mz read --new)
check 'read --new with several rooms and no --room needs no choice' "$(printf '%s' "$out" | grep -c 'run one done')" '1'
check 'it shows every post, not just mentions' "$(printf '%s' "$out" | grep -c -e 'run one done' -e 'dev note' -e 'please look')" '3'
check 'each room gets a heading with its count' "$(printf '%s' "$out" | grep -c -e '══ dev · 1 new ══' -e '══ runs · 2 new ══')" '2'
check 'rooms stay separate: dev comes before runs, not interleaved by time' \
  "$(printf '%s' "$out" | grep -e 'dev note' -e 'run one' -e 'please look' | tr '\n' '|')" 'dev note|run one done|@ben please look|'
case $out in *'2026-08-29 21:00:00 +1100 · alice'*) ok 'headings are in local time' ;; *) no 'headings are in local time' ;; esac
check 'the cursors moved to the newest post in each room' \
  "$(cat "$parent/ben/.moot/seen/runs/ben") $(cat "$parent/ben/.moot/seen/dev/ben")" \
  '20260829-110000-alice 20260829-103000-carol'
check 'a second call shows nothing new' "$(mz read --new)" 'nothing new for ben'

rp runs 'run two done' 20260829-120000-alice
out=$(mz read --new)
check 'a later call shows only what arrived since' "$(printf '%s' "$out" | grep -c -e 'run two done' -e 'run one done' -e 'dev note')" '1'
check 'and only the room that changed gets a heading' "$(printf '%s' "$out" | grep -c '══')" '1'

# Plain read never touches the cursor.
rp runs 'run three done' 20260829-130000-alice
mz read --room runs >/dev/null
check 'plain read leaves the cursor alone' "$(cat "$parent/ben/.moot/seen/runs/ben")" '20260829-120000-alice'
check 'so --new still shows what read showed' "$(mz read --new | grep -c 'run three done')" '1'

# --room narrows; the other room's cursor stays put.
rp runs 'run four done' 20260829-140000-alice
rp dev  'dev two' 20260829-141000-carol
out=$(mz read --new --room dev)
check '--new --room shows that room only' "$(printf '%s' "$out" | grep -c -e 'dev two' -e 'run four')" '1'
check "and leaves the other room's cursor" "$(cat "$parent/ben/.moot/seen/runs/ben")" '20260829-130000-alice'

# --mentions keeps the cursor moving past everything.
rp runs '@ben after' 20260829-150000-alice
rp runs 'plain after' 20260829-151000-alice
out=$(mz read --new --mentions --room runs)
check '--mentions shows only the mention' "$(printf '%s' "$out" | grep -c -e '@ben after')" '1'
check 'and not the plain post' "$(printf '%s' "$out" | grep -c 'plain after')" '0'
check '--mentions moves the cursor past both' "$(cat "$parent/ben/.moot/seen/runs/ben")" '20260829-151000-alice'
check 'so a plain --new shows nothing after it' "$(mz read --new --room runs)" 'nothing new for ben'

# Names: --as picks the cursor; another name has its own.
check 'another name starts from the top' "$(mz read --new --as alice | grep -c '══')" '2'
check 'and keeps its own cursor' "$(mz read --new --as alice)" 'nothing new for alice'

# Options that fight the cursor are refused, not ignored.
for opt in '--since x' '--tail 1'; do
  # shellcheck disable=SC2086
  mz read --new $opt >/dev/null 2>&1; rc=$?
  [ "$rc" -ne 0 ] && ok "--new refuses $opt" || no "--new refuses $opt"
done
refuses '--as without --new is refused' 'only go with --new' mz read --room runs --as ben
refuses '--new --room of an unknown room fails' 'no room nonesuch' mz read --new --room nonesuch

# A room that cannot take a cursor still reads, and says so.
ro=$(new_room)
printf 'hello\n' > "$ro/.moot/rooms/board/posts/20260829-100000-alice.md"
mkdir -p "$ro/.moot/seen/board"; chmod a-w "$ro/.moot/seen/board" 2>/dev/null
if [ -w "$ro/.moot/seen/board" ]; then
  ok '(skipped: running as a user who can write anywhere)'
else
  err=$("$ro/.moot/moot.sh" read --new --as ben 2>&1 >/dev/null)
  check 'a read-only cursor still shows the post' "$("$ro/.moot/moot.sh" read --new --as ben 2>/dev/null | grep -c hello)" '1'
  check 'and warns that it will show again' "$(printf '%s' "$err" | grep -c 'read-only room')" '1'
fi
chmod u+w "$ro/.moot/seen/board" 2>/dev/null

# No rooms at all is not an error.
bare=$(new_host)
check 'read --new with no rooms says nothing new and succeeds' "$("$bare/.moot/moot.sh" read --new --as ben)" 'nothing new for ben'

# ---------------------------------------------------------------- watch

# Start a watch in the background; wait_watch waits up to ~5s for it to exit
# and sets rc to its status (or 'running' if it never did).
start_watch() { MOOT_WATCH_INTERVAL=0.2 "$@" > "$work/watch.out" 2> "$work/watch.err" & watch_pid=$!; sleep 0.6; }
wait_watch() {
  local n=0
  while kill -0 "$watch_pid" 2>/dev/null && [ $n -lt 25 ]; do sleep 0.2; n=$((n + 1)); done
  if kill -0 "$watch_pid" 2>/dev/null; then
    rc=running; kill "$watch_pid" 2>/dev/null; wait "$watch_pid" 2>/dev/null
  else
    wait "$watch_pid"; rc=$?
  fi
}
posts_of() { printf '%s/.moot/rooms/board/posts' "$1"; }

group 'watch'
room=$(new_room)
printf 'old\n' > "$(posts_of "$room")/20260829-090000-alice.md"
start_watch "$room/.moot/moot.sh" watch --as ben
check 'watch does not fire on history' "$(kill -0 "$watch_pid" 2>/dev/null && echo waiting)" 'waiting'
[ -e "$room/.moot/watching" ] && ok 'watch holds .moot/watching' || no 'watch holds .moot/watching'
check 'watching names the watcher' "$(sed -n 's/^name=//p' "$room/.moot/watching")" 'ben'
printf 'mine\n' > "$(posts_of "$room")/20260829-091000-ben.md"
sleep 0.6
check 'watch ignores my own post' "$(kill -0 "$watch_pid" 2>/dev/null && echo waiting)" 'waiting'
printf 'new\n' > "$(posts_of "$room")/20260829-092000-alice.md"
wait_watch
check 'watch exits 0 on a new post' "$rc" '0'
check 'watch prints room/id' "$(cat "$work/watch.out")" 'board/20260829-092000-alice'
[ ! -e "$room/.moot/watching" ] && ok 'watch releases .moot/watching on exit' || no 'watch releases .moot/watching on exit'
[ ! -e "$room/.moot/seen/board/ben" ] && ok 'watch never writes the cursor' || no 'watch never writes the cursor'

group 'watch from the cursor'
room=$(new_room)
printf 'a\n' > "$(posts_of "$room")/20260829-090000-alice.md"
"$room/.moot/moot.sh" read --new --as ben >/dev/null
printf 'b\n' > "$(posts_of "$room")/20260829-093000-alice.md"
start_watch "$room/.moot/moot.sh" watch --as ben
wait_watch
check 'a post since the cursor fires at once' "$rc:$(cat "$work/watch.out")" '0:board/20260829-093000-alice'
check 'and the cursor stays where read --new put it' "$(cat "$room/.moot/seen/board/ben")" '20260829-090000-alice'

group 'watch --mentions'
room=$(new_room)
start_watch "$room/.moot/moot.sh" watch --as ben --mentions
printf 'just news\n' > "$(posts_of "$room")/20260829-090000-alice.md"
sleep 0.6
check '--mentions ignores a post without @ben' "$(kill -0 "$watch_pid" 2>/dev/null && echo waiting)" 'waiting'
printf 'see `@ben`\n' > "$(posts_of "$room")/20260829-090050-alice.md"
sleep 0.6
check '--mentions ignores an @ in code' "$(kill -0 "$watch_pid" 2>/dev/null && echo waiting)" 'waiting'
printf '@ben please look\n' > "$(posts_of "$room")/20260829-090100-alice.md"
wait_watch
check '--mentions fires on @ben' "$rc" '0'
check 'the output names room and post' "$(cat "$work/watch.out")" 'board/20260829-090100-alice'

group 'watch paused'
room=$(new_room)
touch "$room/.moot/watch.paused"
start_watch "$room/.moot/moot.sh" watch --as ben
printf 'while paused\n' > "$(posts_of "$room")/20260829-090000-alice.md"
sleep 0.6
check 'a paused watch does not fire' "$(kill -0 "$watch_pid" 2>/dev/null && echo waiting)" 'waiting'
rm -f "$room/.moot/watch.paused"
sleep 0.6
check 'unpause is quiet: what landed while paused does not fire' "$(kill -0 "$watch_pid" 2>/dev/null && echo waiting)" 'waiting'
printf 'after\n' > "$(posts_of "$room")/20260829-091000-alice.md"
wait_watch
check 'after unpause a new post fires' "$rc:$(cat "$work/watch.out")" '0:board/20260829-091000-alice'

group 'one watcher'
room=$(new_room)
start_watch "$room/.moot/moot.sh" watch --as ben
first=$watch_pid
MOOT_WATCH_INTERVAL=0.2 "$room/.moot/moot.sh" watch --as ben >/dev/null 2>"$work/err2"; rc=$?
check 'a second watch is refused with exit 3' "$rc" '3'
check 'and says who holds it' "$(grep -c "pid $first" "$work/err2")" '1'
check 'the refusal leaves the first watch its file' "$(sed -n 's/^pid=//p' "$room/.moot/watching")" "$first"
kill "$first" 2>/dev/null; wait "$first" 2>/dev/null
[ ! -e "$room/.moot/watching" ] && ok 'a killed watch releases its file' || no 'a killed watch releases its file'
printf 'pid=999999\nname=ben\n' > "$room/.moot/watching"
start_watch "$room/.moot/moot.sh" watch --as ben
check 'a stale watching file is taken over' "$(sed -n 's/^pid=//p' "$room/.moot/watching")" "$watch_pid"
kill "$watch_pid" 2>/dev/null; wait "$watch_pid" 2>/dev/null

group 'a watch just killed does not block its restart'
room=$(new_room)
start_watch "$room/.moot/moot.sh" watch --as ben
first=$watch_pid
kill "$first" 2>/dev/null
start_watch "$room/.moot/moot.sh" watch --as ben
check 'the restart waits for the dying holder, then takes the file' "$(sed -n 's/^pid=//p' "$room/.moot/watching")" "$watch_pid"
check 'and is still running' "$(kill -0 "$watch_pid" 2>/dev/null && echo waiting)" 'waiting'
kill "$watch_pid" 2>/dev/null; wait "$watch_pid" 2>/dev/null; wait "$first" 2>/dev/null

group 'an orphaned watch'
room=$(new_room)
# Started in a subshell that exits at once, so the watch is left with no parent.
( MOOT_WATCH_INTERVAL=0.2 "$room/.moot/moot.sh" watch --as ben >/dev/null 2>"$work/orphan.err" & )
# Wait for its message, not a fixed time: a slow start may not have begun yet.
n=0; while ! grep -q parent "$work/orphan.err" 2>/dev/null && [ $n -lt 25 ]; do sleep 0.2; n=$((n + 1)); done
n=0; while [ -e "$room/.moot/watching" ] && [ $n -lt 25 ]; do sleep 0.2; n=$((n + 1)); done
[ ! -e "$room/.moot/watching" ] && ok 'an orphaned watch exits and releases .moot/watching' || no 'an orphaned watch exits and releases .moot/watching'
check 'and says why' "$(grep -c 'parent' "$work/orphan.err")" '1'

group 'a holder that is orphaned or stale'
room=$(new_room)
printf 'pid=999999\nparent=1\nname=ben\n' > "$room/.moot/watching"
start_watch "$room/.moot/moot.sh" watch --as ben
check 'a holder whose pid is gone is taken over' "$(sed -n 's/^pid=//p' "$room/.moot/watching")" "$watch_pid"
kill "$watch_pid" 2>/dev/null; wait "$watch_pid" 2>/dev/null
# A live watch that recorded a different parent than it has now: an orphan.
start_watch "$room/.moot/moot.sh" watch --as ben
holder=$watch_pid
sed -i.bak 's/^parent=.*/parent=999999/' "$room/.moot/watching"; rm -f "$room/.moot/watching.bak"
start_watch "$room/.moot/moot.sh" watch --as ben
check 'a live watch that lost its parent is taken over' "$(sed -n 's/^pid=//p' "$room/.moot/watching")" "$watch_pid"
n=0; while kill -0 "$holder" 2>/dev/null && [ $n -lt 15 ]; do sleep 0.2; n=$((n + 1)); done
kill -0 "$holder" 2>/dev/null && no 'and is asked to stop' || ok 'and is asked to stop'
kill "$watch_pid" 2>/dev/null; wait "$watch_pid" 2>/dev/null; wait "$holder" 2>/dev/null
# A recycled pid: a live, unrelated process whose parent is pid 1 (detached).
( sleep 30 >/dev/null 2>&1 & echo $! > "$work/unrelated.pid" )
unrelated=$(cat "$work/unrelated.pid")
printf 'pid=%s\nparent=1\nname=ben\n' "$unrelated" > "$room/.moot/watching"
start_watch "$room/.moot/moot.sh" watch --as ben
check 'a live unrelated pid in watching is taken over' "$(sed -n 's/^pid=//p' "$room/.moot/watching")" "$watch_pid"
kill -0 "$unrelated" 2>/dev/null && ok 'and the unrelated process is not signalled' || no 'and the unrelated process is not signalled'
kill "$watch_pid" 2>/dev/null; wait "$watch_pid" 2>/dev/null; kill "$unrelated" 2>/dev/null

group 'a watch killed at a realistic interval'
room=$(new_room)
start_watch "$room/.moot/moot.sh" watch --as ben --interval 3
first=$watch_pid
kill "$first" 2>/dev/null
start_watch "$room/.moot/moot.sh" watch --as ben --interval 3
check 'a restart at once takes the file from a watch killed mid-sleep' "$(sed -n 's/^pid=//p' "$room/.moot/watching")" "$watch_pid"
check 'and the killed watch is gone' "$(kill -0 "$first" 2>/dev/null && echo alive)" ''
kill "$watch_pid" 2>/dev/null; wait "$watch_pid" 2>/dev/null; wait "$first" 2>/dev/null

group 'the orphan exit status'
room=$(new_room)
# A stand-in ps that reports another parent for every ppid query, as if the
# real parent had gone, so the watch can stay our child and be waited on.
mkdir -p "$work/psbin"
realps=$(command -v ps)
printf '#!/bin/sh\ncase "$*" in *ppid*) echo 4242 ;; *) exec %s "$@" ;; esac\n' "$realps" > "$work/psbin/ps"
chmod +x "$work/psbin/ps"
PATH="$work/psbin:$PATH" start_watch "$room/.moot/moot.sh" watch --as ben
wait_watch
check 'a watch that lost its parent exits 4' "$rc" '4'
[ ! -e "$room/.moot/watching" ] && ok 'and releases .moot/watching' || no 'and releases .moot/watching'

group 'a room removed while watching'
room=$(new_room); keep "$room" other
printf 'old\n' > "$(posts_of "$room")/20260829-090000-alice.md"
printf 'old\n' > "$room/.moot/rooms/other/posts/20260829-090000-alice.md"
start_watch "$room/.moot/moot.sh" watch --as ben
rm -rf "${room:?}/.moot/rooms/other"
sleep 0.6
check 'the watch carries on' "$(kill -0 "$watch_pid" 2>/dev/null && echo waiting)" 'waiting'
printf 'new\n' > "$(posts_of "$room")/20260829-091000-alice.md"
wait_watch
check 'and still hears the other room' "$rc:$(cat "$work/watch.out")" '0:board/20260829-091000-alice'

group 'a room joined while watching starts from nothing'
room=$(new_room)
printf 'old\n' > "$(posts_of "$room")/20260829-090000-alice.md"
start_watch "$room/.moot/moot.sh" watch --as ben
keeper=$(new_host); keep "$keeper" ops
printf 'first\n' > "$keeper/.moot/rooms/ops/posts/20260829-090000-carol.md"
"$room/.moot/moot.sh" join "$keeper/.moot/rooms/ops" >/dev/null
wait_watch
check 'its first post fires, though it was there when the room appeared' "$rc:$(cat "$work/watch.out")" '0:ops/20260829-090000-carol'

group 'watch --room (repeatable) and mixed mode'
room=$(new_room); keep "$room" run; keep "$room" runs; keep "$room" other
for r in board run runs other; do p "$r" 20260829-090000-alice 'old'; done
start_watch "$room/.moot/moot.sh" watch --as ben --room run --room board
p other 20260829-091000-alice 'hello @ben'
sleep 0.6
check '--room alone ignores other rooms, mentions or not' "$(kill -0 "$watch_pid" 2>/dev/null && echo waiting)" 'waiting'
p board 20260829-091100-alice 'plain'
wait_watch
check 'each --room is heard fully' "$rc:$(cat "$work/watch.out")" '0:board/20260829-091100-alice'

room=$(new_room); keep "$room" run
for r in board run; do p "$r" 20260829-090000-alice 'old'; done
start_watch "$room/.moot/moot.sh" watch --as ben --room run --mentions
check 'watching names the full rooms and the mentions flag' "$(grep -c '^rooms=run$' "$room/.moot/watching"):$(grep -c '^mentions=1$' "$room/.moot/watching")" '1:1'
p board 20260829-091000-alice 'unmentioned elsewhere'
sleep 0.6
check 'an unmentioned post in another room does not fire' "$(kill -0 "$watch_pid" 2>/dev/null && echo waiting)" 'waiting'
p board 20260829-091100-alice 'in code `@ben` only'
sleep 0.6
check 'an @ in code elsewhere does not fire' "$(kill -0 "$watch_pid" 2>/dev/null && echo waiting)" 'waiting'
p board 20260829-091200-alice 'hey @ben'
wait_watch
check 'a mention in another room fires' "$rc:$(cat "$work/watch.out")" '0:board/20260829-091200-alice'

start_watch "$room/.moot/moot.sh" watch --as ben --room run --mentions
p run 20260829-092000-alice 'no mention needed here'
wait_watch
check 'a post in the full room fires with no mention' "$rc:$(cat "$work/watch.out")" '0:run/20260829-092000-alice'

start_watch "$room/.moot/moot.sh" watch --as ben --mentions
p run 20260829-093000-alice 'plain'
sleep 0.6
check 'with no --room, --mentions still means mentions everywhere' "$(kill -0 "$watch_pid" 2>/dev/null && echo waiting)" 'waiting'
p run 20260829-093100-alice '@ben'
wait_watch
check 'and fires on one' "$rc:$(cat "$work/watch.out")" '0:run/20260829-093100-alice'

refuses 'a --room that is not here is refused' 'no room nosuch' m watch --as ben --room nosuch

group 'install beside a running watch'
room=$(new_room)
start_watch "$room/.moot/moot.sh" watch --as ben
before=$(ls -i "$room/.moot/moot.sh" | awk '{print $1}')
"$repo/install.sh" "$room" >/dev/null
after=$(ls -i "$room/.moot/moot.sh" | awk '{print $1}')
[ "$before" != "$after" ] && ok 'install renames moot.sh into place, not over the running file' \
  || no 'install renames moot.sh into place, not over the running file'
check 'install leaves no temporary file' "$(ls -A "$room/.moot" | grep -c installing)" '0'
printf 'after install\n' > "$(posts_of "$room")/20260829-090000-alice.md"
wait_watch
check 'the running watch still fires after an install' "$rc:$(cat "$work/watch.out")" '0:board/20260829-090000-alice'

group 'watch has no --json'
room=$(new_room)
refuses 'watch --json is gone' 'unknown option' m watch --json

# ---------------------------------------------------------------- room verbs

group 'create'
host=$(new_host)
check 'create prints the room it made' "$(j create ops)" 'created rooms/ops'
check 'and the room holds posts/ with a .gitkeep' "$(ls -A "$host/.moot/rooms/ops/posts")" '.gitkeep'
check 'and nothing else' "$(ls -A "$host/.moot/rooms/ops")" 'posts'
out=$(j create ops 2>&1); rc=$?
check 'create refuses a name already here' "$rc:$out" '1:moot: rooms/ops is already here'
mkdir -p "$host/.moot/rooms/old.archived/posts"
out=$(j create old 2>&1); rc=$?
check 'create refuses a name whose archived form is here' "$rc:$out" '1:moot: rooms/old.archived is already here'
out=$(j create dm-alice-bob 2>&1); rc=$?
check 'create refuses a dm- name' "$rc" '1'
case $out in *'kept for direct messages'*' dm <who>'*) ok 'and names dm instead' ;; *) no 'and names dm instead' "$out" ;; esac
[ -e "$host/.moot/rooms/dm-alice-bob" ] && no 'and makes nothing' || ok 'and makes nothing'
refuses 'create refuses a name ending .archived' 'kept for archived rooms' j create x.archived
refuses 'create refuses an unsafe name' 'not filename-safe' j create 'bad room'

# One folder per participant under a parent, as checkouts sit side by side.
# Each name comes from its folder.
pair_layout() {
  parent=$(mktemp -d "$work/pair.XXXXXX")
  for p in alice bob carol dave; do mkdir -p "$parent/$p"; "$repo/install.sh" "$parent/$p" >/dev/null; done
}

group 'leave'
pair_layout
c create ops >/dev/null
a join "$parent/carol/.moot/rooms/ops" >/dev/null
printf 'x\n' > "$parent/carol/.moot/rooms/ops/posts/20260829-090000-carol.md"
a read --new >/dev/null
check 'leave prints the room it left' "$(a leave ops)" 'left rooms/ops'
[ ! -e "$parent/alice/.moot/rooms/ops" ] && [ ! -L "$parent/alice/.moot/rooms/ops" ] && ok 'and the link is gone' || no 'and the link is gone'
[ ! -e "$parent/alice/.moot/seen/ops" ] && ok 'and so is its cursor' || no 'and so is its cursor'
check 'and the keeper keeps every post' "$(ls "$parent/carol/.moot/rooms/ops/posts" | wc -l | tr -d ' ')" '1'
out=$(c leave ops 2>&1); rc=$?
check 'leave refuses a room kept here' "$rc" '1'
case $out in *'kept here (a real folder)'*) ok 'and says so' ;; *) no 'and says so' "$out" ;; esac
[ -d "$parent/carol/.moot/rooms/ops/posts" ] && ok 'and leaves the real folder' || no 'and leaves the real folder'
refuses 'leave of a room not here fails' 'no room ops here' a leave ops

# ---------------------------------------------------------------- archive and link repair

group 'archive'
pair_layout
c create ops >/dev/null
printf 'before\n' > "$parent/carol/.moot/rooms/ops/posts/20260829-090000-alice.md"
a join "$parent/carol/.moot/rooms/ops" >/dev/null
a read --new >/dev/null; c read --new >/dev/null
out=$(a archive ops 2>&1); rc=$?
check 'archive by a hearer is refused' "$rc" '1'
case $out in *'heard here, not kept'*"/carol/.moot/rooms/ops"*) ok 'and names the keeper' ;; *) no 'and names the keeper' "$out" ;; esac
check 'archive by the keeper renames the room' "$(c archive ops)" 'archived rooms/ops.archived'
[ -d "$parent/carol/.moot/rooms/ops.archived/posts" ] && [ ! -e "$parent/carol/.moot/rooms/ops" ] && ok 'the folder is now ops.archived' || no 'the folder is now ops.archived'
check 'nothing inside the room changed' "$(ls -A "$parent/carol/.moot/rooms/ops.archived"):$(ls "$parent/carol/.moot/rooms/ops.archived/posts")" 'posts:20260829-090000-alice.md'
check "and the keeper's own cursor moved with it" "$(cat "$parent/carol/.moot/seen/ops.archived/carol" 2>/dev/null):$([ -e "$parent/carol/.moot/seen/ops" ] && echo left)" '20260829-090000-alice:'
check 'archive again is already so, exit 0' "$(c archive ops; echo "rc=$?")" "$(printf 'already archived rooms/ops.archived\nrc=0')"
mkdir -p "$parent/carol/.moot/rooms/dm-alice-carol/posts"
out=$(c archive dm-alice-carol 2>&1); rc=$?
check 'archive refuses a dm- room' "$rc" '1'
case $out in *'never archived'*) ok 'and says a DM is never archived' ;; *) no 'and says a DM is never archived' "$out" ;; esac
[ -d "$parent/carol/.moot/rooms/dm-alice-carol" ] && ok 'and leaves it as it was' || no 'and leaves it as it was'
refuses 'archive of a room not here fails' 'no room nosuch here' c archive nosuch

group 'link repair follows an archive'
err=$(a read --new 2>&1 >/dev/null)
check "a hearer's next command (read --new) relinks the room" "$(readlink "$parent/alice/.moot/rooms/ops.archived")" '../../../carol/.moot/rooms/ops.archived'
[ ! -e "$parent/alice/.moot/rooms/ops" ] && [ ! -L "$parent/alice/.moot/rooms/ops" ] && ok 'and removes the old link' || no 'and removes the old link'
check 'and moves the cursor with it' "$(cat "$parent/alice/.moot/seen/ops.archived/alice" 2>/dev/null):$([ -e "$parent/alice/.moot/seen/ops" ] && echo left)" '20260829-090000-alice:'
check 'and says how to read the rest' "$err" 'moot: rooms/ops is archived, now rooms/ops.archived (read --new --room ops.archived shows the rest)'
check 'a second command has nothing to repair' "$(a rooms 2>&1)" 'ops.archived'

group 'an archived room'
out=$(a post --room ops -m 'too late' 2>&1); rc=$?
check 'post in an archived room is refused' "$rc:$out" '1:moot: ops is archived; posting is closed'
refuses 'even by its keeper' 'posting is closed' c post --room ops.archived -m 'too late'
check 'and nothing landed' "$(ls "$parent/carol/.moot/rooms/ops.archived/posts" | wc -l | tr -d ' ')" '1'
check 'read --room ops still finds ops.archived' "$(a read --room ops | grep -c '^before$')" '1'
printf 'a last word\n' > "$parent/carol/.moot/rooms/ops.archived/posts/20260829-100000-carol.md"
check 'read --new leaves an archived room out' "$(a read --new)" 'nothing new for alice'
check 'unless --room names it' "$(a read --new --room ops | grep -c 'a last word')" '1'
check 'and that moves its cursor' "$(cat "$parent/alice/.moot/seen/ops.archived/alice")" '20260829-100000-carol'
check 'archive of a heard archived room is already so' "$(a archive ops)" 'already archived rooms/ops.archived'
c create dev >/dev/null; c create zed >/dev/null
check 'rooms lists live rooms first, then archived ones' "$(c rooms | tr '\n' ' ')" 'dev dm-alice-carol zed ops.archived '

host=$(new_host)
j create board >/dev/null; j create old >/dev/null; j archive old >/dev/null
j post --as ben -m 'to the sole live room' >/dev/null
check 'the sole-room default counts live rooms only' "$(ls "$host/.moot/rooms/board/posts"/*.md | wc -l | tr -d ' ')" '1'

group 'link repair follows an un-archive'
mv "$parent/carol/.moot/rooms/ops.archived" "$parent/carol/.moot/rooms/ops"
err=$(a post --room ops -m 'back' 2>&1 >/dev/null); rc=$?
check 'a by-hand mv back is followed (by post)' "$(readlink "$parent/alice/.moot/rooms/ops")" '../../../carol/.moot/rooms/ops'
check 'with the cursor' "$(cat "$parent/alice/.moot/seen/ops/alice" 2>/dev/null)" '20260829-100000-carol'
check 'and says so' "$err" 'moot: rooms/ops.archived is open again, now rooms/ops'
check 'and that post lands in the open room' "$rc:$(cat "$parent/carol/.moot/rooms/ops/posts"/*-alice.md | grep -c '^back$')" '0:1'

group 'link repair clears an archived room that has gone'
c archive ops >/dev/null; err=$(a status 2>&1 >/dev/null)
case $err in *'rooms/ops is archived, now rooms/ops.archived'*) ok 'status repairs too' ;; *) no 'status repairs too' "$err" ;; esac
rm -rf "${parent:?}/carol/.moot/rooms/ops.archived"
a help >/dev/null 2>&1
[ -L "$parent/alice/.moot/rooms/ops.archived" ] && ok 'help leaves a dangling link as it was' || no 'help leaves a dangling link as it was'
err=$(a status 2>&1 >/dev/null)
[ ! -e "$parent/alice/.moot/rooms/ops.archived" ] && [ ! -L "$parent/alice/.moot/rooms/ops.archived" ] && ok 'the dangling archived link is removed' || no 'the dangling archived link is removed'
[ ! -e "$parent/alice/.moot/seen/ops.archived" ] && ok 'with its cursor' || no 'with its cursor'
case $err in *'rooms/ops.archived has gone from its keeper'*) ok 'and says so' ;; *) no 'and says so' "$err" ;; esac

group 'link repair leaves any other dangling link'
d join "$parent/carol/.moot/rooms/dev" >/dev/null
printf 'x\n' > "$parent/carol/.moot/rooms/dev/posts/20260829-090000-carol.md"
d read --new >/dev/null
mv "$parent/carol/.moot/rooms/dev" "$parent/carol/dev-away"
err=$(d rooms 2>&1 >/dev/null)
refuses 'archive of a link that leads nowhere is refused' 'leads nowhere; leave it with' d archive dev
[ -L "$parent/dave/.moot/rooms/dev" ] && ok 'a live room that has gone stays linked' || no 'a live room that has gone stays linked'
[ -f "$parent/dave/.moot/seen/dev/dave" ] && ok 'and keeps its cursor' || no 'and keeps its cursor'
check 'and rooms reports it with the leave line' "$err" "moot: rooms/dev leads nowhere (../../../carol/.moot/rooms/dev); leave it with: $parent/dave/.moot/moot.sh leave dev"
mv "$parent/carol/dev-away" "$parent/carol/.moot/rooms/dev"
check 'so the room is heard again when it comes back' "$(d rooms 2>&1)" 'dev'
ln -s ../../../ghost/.moot/rooms/gone.archived "$parent/dave/.moot/rooms/gone.archived"
d rooms >/dev/null 2>&1
[ -L "$parent/dave/.moot/rooms/gone.archived" ] && ok "an archived link stays when its keeper's rooms/ is not there" || no "an archived link stays when its keeper's rooms/ is not there"
check 'and leave lets it go' "$(d leave gone.archived)" 'left rooms/gone.archived'

group "link repair carries the keeper's own cursor"
pair_layout
c create ops >/dev/null
for t in 090000 090100 090200; do printf '@carol %s\n' "$t" > "$parent/carol/.moot/rooms/ops/posts/20260829-$t-alice.md"; done
c read --new >/dev/null
c archive ops >/dev/null
mv "$parent/carol/.moot/rooms/ops.archived" "$parent/carol/.moot/rooms/ops"
check 'after a by-hand un-archive nothing replays' "$(c read --new)" 'nothing new for carol'
check 'because the cursor followed the room' "$(cat "$parent/carol/.moot/seen/ops/carol" 2>/dev/null)" '20260829-090200-alice'
inbox="$work/unarchive-inbox"; rm -rf "$inbox"
c read --new --deliver "$inbox" >/dev/null
check 'and nothing is delivered twice' "$(ls "$inbox" 2>/dev/null | wc -l | tr -d ' ')" '0'
mv "$parent/carol/.moot/rooms/ops" "$parent/carol/.moot/rooms/ops.archived"
check 'a by-hand archive carries it too' "$(c read --new --room ops)" 'nothing new for carol'
[ -f "$parent/carol/.moot/seen/ops.archived/carol" ] && [ ! -e "$parent/carol/.moot/seen/ops" ] && ok 'into seen/ops.archived' || no 'into seen/ops.archived'

group 'a watch started after an archive'
pair_layout
c create ops >/dev/null; a create board >/dev/null
a join "$parent/carol/.moot/rooms/ops" >/dev/null
c archive ops >/dev/null
start_watch env MOOT_NAME= "$parent/alice/.moot/moot.sh" watch
check 'watch repairs the link when it starts' "$(readlink "$parent/alice/.moot/rooms/ops.archived")" '../../../carol/.moot/rooms/ops.archived'
printf 'late\n' > "$parent/carol/.moot/rooms/ops.archived/posts/20260829-091000-carol.md"
sleep 0.6
check 'and leaves the archived room out' "$(kill -0 "$watch_pid" 2>/dev/null && echo waiting)" 'waiting'
printf 'new\n' > "$parent/alice/.moot/rooms/board/posts/20260829-092000-carol.md"
wait_watch
check 'while it hears the live one' "$rc:$(cat "$work/watch.out")" '0:board/20260829-092000-carol'

group 'link repair leaves a rename whose new name is taken'
pair_layout
c create ops >/dev/null; d join "$parent/carol/.moot/rooms/ops" >/dev/null
c archive ops >/dev/null
ln -s ../../../carol/.moot/rooms/ops.archived "$parent/dave/.moot/rooms/ops.archived"
err=$(d rooms 2>&1 >/dev/null)
[ -L "$parent/dave/.moot/rooms/ops" ] && ok 'the old link stays' || no 'the old link stays'
case $err in *'rooms/ops leads nowhere'*) ok 'and rooms reports it' ;; *) no 'and rooms reports it' "$err" ;; esac

group 'a link carries its room'"'"'s mark'
pair_layout
c create ops >/dev/null; c create dev >/dev/null; c archive ops >/dev/null
printf 'x\n' > "$parent/carol/.moot/rooms/ops.archived/posts/20260829-090000-carol.md"
mkdir -p "$parent/alice/.moot/rooms"
# A live-named link to an archived room: it is archived, whatever it is called.
ln -s ../../../carol/.moot/rooms/ops.archived "$parent/alice/.moot/rooms/hist"
mkdir -p "$parent/alice/.moot/seen/hist"; printf '20260829-090000-carol\n' > "$parent/alice/.moot/seen/hist/alice"
err=$(a rooms 2>&1 >/dev/null)
check 'a live-named link to an archived room takes the mark' "$(readlink "$parent/alice/.moot/rooms/hist.archived")" '../../../carol/.moot/rooms/ops.archived'
[ ! -L "$parent/alice/.moot/rooms/hist" ] && ok 'and the old name goes' || no 'and the old name goes'
check 'with its cursor' "$(cat "$parent/alice/.moot/seen/hist.archived/alice" 2>/dev/null)" '20260829-090000-carol'
check 'and says so' "$err" 'moot: rooms/hist is archived, now rooms/hist.archived (read --new --room hist.archived shows the rest)'
refuses 'so post refuses it under the new name' 'posting is closed' a post --room hist -m 'x'
check 'and nothing landed in the archived room' "$(ls "$parent/carol/.moot/rooms/ops.archived/posts" | wc -l | tr -d ' ')" '1'
check 'a second command has nothing to repair' "$(a rooms 2>&1 >/dev/null)" ''
# An archived-named link to a live room: it is open, whatever it is called.
ln -s ../../../carol/.moot/rooms/dev "$parent/alice/.moot/rooms/old.archived"
mkdir -p "$parent/alice/.moot/seen/old.archived"; printf '20260829-090000-carol\n' > "$parent/alice/.moot/seen/old.archived/alice"
err=$(a post --room old -m 'in the open' 2>&1 >/dev/null); rc=$?
check 'an archived-named link to a live room takes the mark' "$(readlink "$parent/alice/.moot/rooms/old")" '../../../carol/.moot/rooms/dev'
check 'with its cursor' "$(cat "$parent/alice/.moot/seen/old/alice" 2>/dev/null)" '20260829-090000-carol'
check 'and says so' "$err" 'moot: rooms/old.archived is open again, now rooms/old'
check 'so a post lands in the live room' "$rc:$(cat "$parent/carol/.moot/rooms/dev/posts"/*-alice.md | grep -c '^in the open$')" '0:1'
# Repair leaves a link alone when the name it would take is taken.
ln -s ../../../carol/.moot/rooms/ops.archived "$parent/alice/.moot/rooms/busy"
ln -s ../../../carol/.moot/rooms/dev "$parent/alice/.moot/rooms/busy.archived"
a rooms >/dev/null 2>&1
check 'a mark is not taken onto a name already there' "$([ -L "$parent/alice/.moot/rooms/busy" ] && echo kept):$([ -L "$parent/alice/.moot/rooms/busy.archived" ] && echo kept)" 'kept:kept'

group 'join and the two forms of a name'
pair_layout
c create ops >/dev/null; c archive ops >/dev/null
check 'join of an archived room links it under that name' "$(a join "$parent/carol/.moot/rooms/ops.archived")" 'joined rooms/ops.archived -> ../../../carol/.moot/rooms/ops.archived'
d create ops >/dev/null
out=$(a join "$parent/dave/.moot/rooms/ops" 2>&1); rc=$?
check 'join refuses a name whose other form is here' "$rc:$out" '1:moot: rooms/ops.archived is already here'
check 'leave by the old name finds the archived room' "$(a leave ops)" 'left rooms/ops.archived'

group 'a link another command made a moment ago is never followed'
# A stand-in ln that acts out a second command making the same link first,
# between the test that the name is free and the ln itself.
mkdir -p "$work/lnbin"; real_ln=$(command -v ln)
cat > "$work/lnbin/ln" <<'STUB'
#!/bin/sh
for dest; do :; done
eval "src=\${$(($# - 1))}"
[ -e "$dest" ] || [ -L "$dest" ] || "$REAL_LN" -s "$src" "$dest"
exec "$REAL_LN" "$@"
STUB
chmod +x "$work/lnbin/ln"
raced() { ( cd "$work" && PATH="$work/lnbin:$PATH" REAL_LN=$real_ln MOOT_NAME= "$@" ); }
pair_layout
c create ops >/dev/null; c create dev >/dev/null
a join "$parent/carol/.moot/rooms/ops" >/dev/null
c archive ops >/dev/null
raced "$parent/alice/.moot/moot.sh" rooms >/dev/null 2>&1
check 'link repair losing the race writes nothing into the room' "$(ls -A "$parent/carol/.moot/rooms/ops.archived")" 'posts'
check 'and the link is there' "$(readlink "$parent/alice/.moot/rooms/ops.archived")" '../../../carol/.moot/rooms/ops.archived'
out=$(raced "$parent/dave/.moot/moot.sh" join "$parent/carol/.moot/rooms/dev" 2>&1); rc=$?
check 'join losing the race succeeds' "$rc:$out" '0:joined rooms/dev -> ../../../carol/.moot/rooms/dev'
check 'and writes nothing into the room' "$(ls -A "$parent/carol/.moot/rooms/dev")" 'posts'

# ---------------------------------------------------------------- direct messages

group 'dm'
pair_layout
out=$( cd "$work" && MOOT_NAME=zed "$parent/alice/.moot/moot.sh" dm "$parent/bob" ); rc=$?
check 'dm with neither side holding it starts it, named from the folders, not $MOOT_NAME' "$rc:$out" '0:started rooms/dm-alice-bob'
[ -d "$parent/alice/.moot/rooms/dm-alice-bob/posts" ] && [ ! -L "$parent/alice/.moot/rooms/dm-alice-bob" ] && ok 'the starter keeps it' || no 'the starter keeps it'
check "and the other's own join links it" "$(readlink "$parent/bob/.moot/rooms/dm-alice-bob")" '../../../alice/.moot/rooms/dm-alice-bob'
check 'dm again finds it' "$(a dm "$parent/bob")" 'have rooms/dm-alice-bob'
check 'and from the other side, by name, too' "$(b dm alice)" 'have rooms/dm-alice-bob'
b leave dm-alice-bob >/dev/null
check 'a hearer that left joins again' "$(b dm alice)" 'joined rooms/dm-alice-bob'
b leave dm-alice-bob >/dev/null
check 'the keeper finds it while the other has left' "$(a dm bob)" 'have rooms/dm-alice-bob'
[ -L "$parent/bob/.moot/rooms/dm-alice-bob" ] && ok "and makes the other's link again" || no "and makes the other's link again"
check 'a DM started from the other side lands in the same name' "$(c dm "$parent/alice")" 'started rooms/dm-alice-carol'
[ -d "$parent/carol/.moot/rooms/dm-alice-carol" ] && [ -L "$parent/alice/.moot/rooms/dm-alice-carol" ] && ok 'kept by the side that started it' || no 'kept by the side that started it'
refuses 'dm takes no --as' 'unknown option for dm' a dm --as zed
refuses 'a DM with oneself is refused' 'needs two participants' a dm "$parent/alice"
out=$(a dm nobody 2>&1); rc=$?
check 'a name with no sibling folder is refused' "$rc" '1'
case $out in *'pass its directory'*) ok 'and asks for the directory' ;; *) no 'and asks for the directory' "$out" ;; esac
mkdir -p "$parent/empty"
refuses 'a folder with no .moot/ is refused' 'no .moot/ there' a dm "$parent/empty"

group 'dm and the reserved names'
out=$(d join "$parent/alice/.moot/rooms/dm-alice-bob" 2>&1); rc=$?
check 'a third party joining a DM is refused' "$rc" '1'
case $out in *'direct message for two others'*) ok 'and says the DM is for its pair' ;; *) no 'and says the DM is for its pair' "$out" ;; esac
[ ! -e "$parent/dave/.moot/rooms/dm-alice-bob" ] && ok 'and no link was made' || no 'and no link was made'
refuses 'the keeper cannot archive a DM' 'never archived' a archive dm-alice-bob

group 'dm on an archived DM'
mv "$parent/alice/.moot/rooms/dm-alice-bob" "$parent/alice/.moot/rooms/dm-alice-bob.archived"
keeper_rooms=$(cd -P "$parent/alice/.moot/rooms" && pwd -P)
want="moot: dm-alice-bob is archived; its keeper reopens it with: mv $keeper_rooms/dm-alice-bob.archived $keeper_rooms/dm-alice-bob"
out=$(b dm alice 2>&1 >/dev/null | tail -1); rc=$(b dm alice >/dev/null 2>&1; echo $?)
check 'dm from the hearer refuses an archived DM' "$rc" '1'
check 'naming the keeper and the mv' "$out" "$want"
out=$(a dm bob 2>&1); rc=$?
check 'and so does dm from the keeper' "$rc:$out" "1:$want"
[ ! -e "$parent/alice/.moot/rooms/dm-alice-bob" ] && ok 'and nothing new is made' || no 'and nothing new is made'

group 'dm has a DM only while the other side hears it'
pair_layout
a dm bob >/dev/null
rm "$parent/bob/.moot/rooms/dm-alice-bob"; ln -s ../../../elsewhere/dm-alice-bob "$parent/bob/.moot/rooms/dm-alice-bob"
err=$(a dm bob 2>&1 >/dev/null); out=$(a dm bob 2>/dev/null); rc=$?
check "the keeper still has it while the other side's link leads nowhere" "$rc:$out" '0:have rooms/dm-alice-bob'
case $err in *'bob could not link rooms/dm-alice-bob again'*'leave dm-alice-bob'*) ok 'and says the other side must leave its own first' ;; *) no 'and says the other side must leave its own first' "$err" ;; esac
rm "$parent/bob/.moot/rooms/dm-alice-bob"; mkdir -p "$parent/bob/.moot/rooms/dm-alice-bob/posts"
out=$(a dm bob 2>&1); rc=$?
check 'a DM kept on both sides is refused' "$rc" '1'
case $out in *'kept on both sides'*"$parent/alice/.moot/rooms/dm-alice-bob"*"$parent/bob/.moot/rooms/dm-alice-bob"*) ok 'naming both folders' ;; *) no 'naming both folders' "$out" ;; esac
out=$(b dm alice 2>&1); rc=$?
check 'from the other side too' "$rc" '1'
case $out in *'kept on both sides'*) ok 'and every time' ;; *) no 'and every time' "$out" ;; esac

group 'dm: the other branches'
pair_layout
far=$(mktemp -d "$work/far.XXXXXX"); mkdir -p "$far/zoe"; "$repo/install.sh" "$far/zoe" >/dev/null
a dm "$far/zoe" >/dev/null
check 'a name with no sibling folder finds a DM already here' "$(a dm zoe)" 'have rooms/dm-alice-zoe'
a dm bob >/dev/null; b leave dm-alice-bob >/dev/null
mv "$parent/alice/.moot/rooms/dm-alice-bob" "$parent/alice/.moot/rooms/dm-alice-bob.archived"
refuses 'dm refuses a DM archived on the other side, with no link here' 'is archived; its keeper reopens it with: mv' b dm alice
[ ! -e "$parent/bob/.moot/rooms/dm-alice-bob" ] && [ ! -L "$parent/bob/.moot/rooms/dm-alice-bob" ] && ok 'and makes no link' || no 'and makes no link'
c dm alice >/dev/null
mv "$parent/carol/.moot/rooms/dm-alice-carol" "$parent/carol/away"
refuses 'dm refuses a link that leads nowhere' 'leads nowhere; leave it first' a dm carol

group 'a DM counts as a mention'
pair_layout
a dm bob >/dev/null
printf 'no at in this\n' > "$parent/alice/.moot/rooms/dm-alice-bob/posts/20260829-090000-alice.md"
printf 'my own note\n' > "$parent/alice/.moot/rooms/dm-alice-bob/posts/20260829-090100-bob.md"
out=$(b read --new --mentions)
check 'every post from the other side counts' "$(printf '%s' "$out" | grep -c 'no at in this')" '1'
check 'but not my own' "$(printf '%s' "$out" | grep -c 'my own note')" '0'
inbox="$work/dm-inbox"; rm -rf "$inbox"; rm -rf "${parent:?}/bob/.moot/seen"
mkdir -p "$parent/bob/.moot/seen/dm-alice-bob"; : > "$parent/bob/.moot/seen/dm-alice-bob/.joined"
b read --new --deliver "$inbox" >/dev/null
check 'and --deliver delivers it' "$(ls "$inbox" | wc -l | tr -d ' ')" '1'
c create plain >/dev/null; b join "$parent/carol/.moot/rooms/plain" >/dev/null
printf 'no at here either\n' > "$parent/carol/.moot/rooms/plain/posts/20260829-090000-carol.md"
check 'in any other room a post with no @ does not' "$(b read --new --mentions)" 'nothing new for bob'

group 'a new DM wakes a running watch'
pair_layout
c create ops >/dev/null; b join "$parent/carol/.moot/rooms/ops" >/dev/null
start_watch env MOOT_NAME= "$parent/bob/.moot/moot.sh" watch --mentions
a dm bob >/dev/null
printf 'are you free?\n' > "$parent/alice/.moot/rooms/dm-alice-bob/posts/20260829-090000-alice.md"
wait_watch
check 'its first post fires a mentions watch' "$rc:$(cat "$work/watch.out")" '0:dm-alice-bob/20260829-090000-alice'

group 'watch and archived rooms'
room=$(new_room); keep "$room" old
printf 'old\n' > "$(posts_of "$room")/20260829-090000-alice.md"
printf 'old\n' > "$room/.moot/rooms/old/posts/20260829-090000-alice.md"
"$room/.moot/moot.sh" archive old >/dev/null
start_watch "$room/.moot/moot.sh" watch --as ben
printf 'late\n' > "$room/.moot/rooms/old.archived/posts/20260829-091000-alice.md"
sleep 0.6
check 'watch leaves an archived room out' "$(kill -0 "$watch_pid" 2>/dev/null && echo waiting)" 'waiting'
printf 'new\n' > "$(posts_of "$room")/20260829-092000-alice.md"
wait_watch
check 'and still hears the live one' "$rc:$(cat "$work/watch.out")" '0:board/20260829-092000-alice'
start_watch "$room/.moot/moot.sh" watch --as ben --room old
printf 'later\n' > "$room/.moot/rooms/old.archived/posts/20260829-093000-alice.md"
wait_watch
check 'unless --room names it' "$rc:$(cat "$work/watch.out")" '0:old.archived/20260829-093000-alice'

# ---------------------------------------------------------------- the dm race

# A stand-in moot.sh for the other side whose first join acts out that side's
# own dm reaching "start it" at the same instant: it makes its own real room, so
# the real join then refuses. $1 is the scenario.
race_wrapper() {
  local dir=$1 scenario=$2
  mv "$dir/.moot/moot.sh" "$dir/.moot/moot.real.sh"
  cat > "$dir/.moot/moot.sh" <<STUB
#!/usr/bin/env bash
d=\$(cd "\$(dirname "\$0")" && pwd)
if [ "\$1" = join ] && [ ! -e "\$d/raced" ]; then
  : > "\$d/raced"
  mkdir -p "\$d/rooms/$3/posts"
  case $scenario in
    yields) ( sleep 0.3; rm -rf "\$d/rooms/$3"; "\$d/moot.real.sh" join "\$2" ) >/dev/null 2>&1 & ;;
    holds) printf 'mine\n' > "\$d/rooms/$3/posts/20260829-090000-x.md" ;;
    posts-there) printf 'mine\n' > "${4:-}/posts/20260829-090000-y.md" ;;
  esac
fi
exec "\$d/moot.real.sh" "\$@"
STUB
  chmod +x "$dir/.moot/moot.sh"
}

group 'the dm race'
pair_layout
race_wrapper "$parent/alice" plain dm-alice-bob
out=$(b dm alice 2>&1); rc=$?
check 'the side that sorts later yields and joins' "$rc:$out" '0:joined rooms/dm-alice-bob'
check 'so its link leads to the other room' "$(readlink "$parent/bob/.moot/rooms/dm-alice-bob")" '../../../alice/.moot/rooms/dm-alice-bob'

pair_layout
race_wrapper "$parent/bob" yields dm-alice-bob
out=$(a dm bob 2>&1); rc=$?
check 'the side that sorts first tries again, and starts it' "$rc:$out" '0:started rooms/dm-alice-bob'
[ -d "$parent/alice/.moot/rooms/dm-alice-bob" ] && [ ! -L "$parent/alice/.moot/rooms/dm-alice-bob" ] && [ -L "$parent/bob/.moot/rooms/dm-alice-bob" ] \
  && ok 'kept on its side, linked on the other' || no 'kept on its side, linked on the other'
[ -e "$parent/bob/.moot/raced" ] && ok 'after the other side really raced it' || no 'after the other side really raced it'

pair_layout
race_wrapper "$parent/bob" holds dm-alice-bob
out=$(a dm bob 2>&1); rc=$?
check 'a race that leaves posts on the other side exits 1' "$rc" '1'
case $out in *"$parent/alice/.moot/rooms/dm-alice-bob"*"$parent/bob/.moot/rooms/dm-alice-bob"*) ok 'and names both folders' ;; *) no 'and names both folders' "$out" ;; esac
check 'and removes no post' "$(ls "$parent/bob/.moot/rooms/dm-alice-bob/posts")" '20260829-090000-x.md'

pair_layout
race_wrapper "$parent/alice" posts-there dm-alice-bob "$parent/bob/.moot/rooms/dm-alice-bob"
out=$(b dm alice 2>&1); rc=$?
check 'the side that would yield keeps a room that holds posts' "$rc" '1'
case $out in *"this side's holds posts"*) ok 'and says it is this side that holds them' ;; *) no 'and says it is this side that holds them' "$out" ;; esac
[ -f "$parent/bob/.moot/rooms/dm-alice-bob/posts/20260829-090000-y.md" ] && ok 'and its post' || no 'and its post'

# ---------------------------------------------------------------- status

group 'status'
host=$(new_host)
out=$(j status 2>/dev/null); rc=$?
check 'with no status, status prints nothing and exits 0' "$rc:$out" '0:'
freeze_date 20261122-093012
check 'status -m writes and prints a stamped line' "$(j status -m 'closing the ops run')" '20261122-093012 closing the ops run'
thaw_date
check 'line one of .moot/status is that line' "$(head -n 1 "$host/.moot/status")" '20261122-093012 closing the ops run'
check 'status prints it back' "$(j status)" '20261122-093012 closing the ops run'
printf 'by hand, no stamp\nmore lines\n' > "$host/.moot/status"
check 'a by-hand status is read as it stands' "$(j status)" 'by hand, no stamp'
refuses 'an empty status is refused' 'empty status' j status -m '  '
check 'status leaves no temporary file' "$(ls -A "$host/.moot" | grep -c '^\.status')" '0'

# ---------------------------------------------------------------- a first delivery

group 'a delivery with no cursor and no mark starts from now'
host=$(new_host); keep "$host" board
printf '@alice old work\n' > "$host/.moot/rooms/board/posts/20260829-090000-ben.md"
inbox="$work/now-inbox"; rm -rf "$inbox"
check 'it delivers nothing old' "$(j read --new --as alice --deliver "$inbox")" 'nothing new for alice'
check 'and writes no file' "$(ls "$inbox" | wc -l | tr -d ' ')" '0'
check 'but leaves its cursor at the newest post' "$(cat "$host/.moot/seen/board/alice")" '20260829-090000-ben'
printf '@alice new work\n' > "$host/.moot/rooms/board/posts/20260829-091000-ben.md"
j read --new --as alice --deliver "$inbox" >/dev/null
check 'the next post delivers' "$(ls "$inbox")" 'moot-board-20260829-091000-ben.md'
case $(j read --new --as carol) in *'old work'*) ok 'a catch-up with no cursor still shows history' ;; *) no 'a catch-up with no cursor still shows history' ;; esac

group 'a renamed reader is not handed old mentions again'
host=$(new_host); keep "$host" board
printf '@all old news\n' > "$host/.moot/rooms/board/posts/20260829-090000-ben.md"
inbox="$work/rename-inbox"; rm -rf "$inbox"
j read --new --as fanta --deliver "$inbox" >/dev/null
j read --new --as fanta-2 --deliver "$inbox" >/dev/null
check 'a new name delivers nothing old' "$(ls "$inbox" | wc -l | tr -d ' ')" '0'

group 'a cursorless delivery in an empty room starts from its first post'
host=$(new_host); keep "$host" board
inbox="$work/empty-inbox"; rm -rf "$inbox"
j read --new --as alice --deliver "$inbox" >/dev/null
[ -f "$host/.moot/seen/board/.joined" ] && ok 'it leaves an empty mark' || no 'it leaves an empty mark'
[ -e "$host/.moot/seen/board/alice" ] && no 'and no cursor' || ok 'and no cursor'
printf '@alice the first\n' > "$host/.moot/rooms/board/posts/20260829-090000-ben.md"
j read --new --as alice --deliver "$inbox" >/dev/null
check 'the first post delivers' "$(ls "$inbox" | wc -l | tr -d ' ')" '1'
[ -e "$host/.moot/seen/board/.joined" ] && no 'and the mark is gone' || ok 'and the mark is gone'

group 'join leaves a mark, so a mention after the link still arrives'
keeper=$(new_host); keep "$keeper" ops
printf '@alice before the join\n' > "$keeper/.moot/rooms/ops/posts/20260829-090000-carol.md"
host=$(new_host)
j join "$keeper/.moot/rooms/ops" >/dev/null
check 'the mark is the newest post at the join' "$(cat "$host/.moot/seen/ops/.joined")" '20260829-090000-carol'
printf '@alice after the join\n' > "$keeper/.moot/rooms/ops/posts/20260829-091000-carol.md"
inbox="$work/join-inbox"; rm -rf "$inbox"
j read --new --as alice --deliver "$inbox" >/dev/null
check 'only the mention after the join delivers' "$(ls "$inbox")" 'moot-ops-20260829-091000-carol.md'
[ -e "$host/.moot/seen/ops/.joined" ] && no 'the first cursor removes the mark' || ok 'the first cursor removes the mark'
check 'the mark never reaches the keeper' "$(ls -A "$keeper/.moot/rooms/ops")" 'posts'
check 'join prints what it always did' "$(cd "$work" && MOOT_NAME= "$host/.moot/moot.sh" join "$keeper/.moot/rooms/ops")" 'already in rooms/ops'

group 'a catch-up after a join still shows history, and leaves the mark'
keeper=$(new_host); keep "$keeper" ops
printf 'the charter\n' > "$keeper/.moot/rooms/ops/posts/20260829-090000-carol.md"
host=$(new_host)
j join "$keeper/.moot/rooms/ops" >/dev/null
printf '@bot please start\n' > "$keeper/.moot/rooms/ops/posts/20260829-091000-carol.md"
case $(j read --new --as alice) in *'the charter'*) ok 'read --new shows the room from its start' ;; *) no 'read --new shows the room from its start' ;; esac
[ -f "$host/.moot/seen/ops/.joined" ] && ok 'a catch-up leaves the mark' || no 'a catch-up leaves the mark'
inbox="$work/bot-inbox"; rm -rf "$inbox"
j read --new --as bot --deliver "$inbox" >/dev/null
check 'so a heartbeat under its own name still gets the mention' "$(ls "$inbox")" 'moot-ops-20260829-091000-carol.md'
[ -e "$host/.moot/seen/ops/.joined" ] && no 'and its delivery spends the mark' || ok 'and its delivery spends the mark'

group 'a delivery where seen/ is read-only and there is no mark'
host=$(new_host); keep "$host" ops
for t in 090000 090100 090200; do printf '@alice %s\n' "$t" > "$host/.moot/rooms/ops/posts/20260829-$t-ben.md"; done
mkdir -p "$host/.moot/seen/ops"; chmod -w "$host/.moot/seen/ops"
inbox="$work/ro-now-inbox"; rm -rf "$inbox"
j read --new --as alice --deliver "$inbox" >/dev/null 2>"$work/ro-now.err"
check 'it delivers as from the start, since it cannot record now' "$(ls "$inbox" | wc -l | tr -d ' ')" '3'
j read --new --as alice --deliver "$inbox" >/dev/null 2>&1
check 'and a repeat delivers nothing twice' "$(ls "$inbox" | wc -l | tr -d ' ')" '3'
check 'and warns about its cursor' "$(grep -c 'read-only room' "$work/ro-now.err")" '1'
chmod +w "$host/.moot/seen/ops"

group 'create and dm leave an empty mark'
host=$(new_host)
j create board >/dev/null
check 'create: an empty mark' "$(cat "$host/.moot/seen/board/.joined" 2>&1)" ''
printf '@alice early\n' > "$host/.moot/rooms/board/posts/20260829-090000-ben.md"
inbox="$work/create-inbox"; rm -rf "$inbox"
j read --new --as alice --deliver "$inbox" >/dev/null
check 'a post before the first delivery delivers' "$(ls "$inbox" | wc -l | tr -d ' ')" '1'
pair_layout
a dm bob >/dev/null
[ -f "$parent/alice/.moot/seen/dm-alice-bob/.joined" ] && ok 'dm: the starter has a mark' || no 'dm: the starter has a mark'
[ -f "$parent/bob/.moot/seen/dm-alice-bob/.joined" ] && ok 'dm: the other side has one too' || no 'dm: the other side has one too'
printf '@bob are you free?\n' > "$parent/alice/.moot/rooms/dm-alice-bob/posts/20260829-090000-alice.md"
inbox="$work/dm-mark-inbox"; rm -rf "$inbox"
b read --new --deliver "$inbox" >/dev/null
check 'a DM first post delivers' "$(ls "$inbox" | wc -l | tr -d ' ')" '1'

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
