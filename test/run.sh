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

# A host directory with moot installed and one room joined. Every test gets a
# fresh one. The host is an ordinary working directory: everything moot owns is
# under its .moot/, and the room under test is rooms/board/.
new_room() {
  local dir; dir=$(mktemp -d "$work/host.XXXXXX")
  "$repo/install.sh" "$dir" >/dev/null
  "$dir/.moot/moot.sh" join board >/dev/null
  printf '%s' "$dir"
}

# A host with moot installed and no room joined.
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

# ---------------------------------------------------------------- init

group 'init'
host=$(new_host)
[ -d "$host/.moot/rooms" ] && ok 'init creates .moot/rooms/' || no 'init creates .moot/rooms/'
[ -d "$host/.moot/seen" ] && ok 'init creates .moot/seen/' || no 'init creates .moot/seen/'
# init makes a participant, not a room: it no longer knows which one.
check 'init creates no room' "$(ls -A "$host/.moot/rooms" | wc -l | tr -d ' ')" '0'
# A working directory holds .moot/ and nothing else of moot's.
check 'the host holds nothing but .moot/' "$(ls -A "$host")" '.moot'

out=$("$host/.moot/moot.sh" init)
case $out in *'no rooms yet'*) ok 'init with no rooms names join' ;; *) no 'init with no rooms names join' "$out" ;; esac
out=$("$host/.moot/moot.sh" init --json)
case $out in *'"room":null'*) ok 'init --json reports no default room as null' ;; *) no 'init --json reports no default room as null' "$out" ;; esac

room=$(new_room)
[ -d "$room/.moot/rooms/board/posts" ] && ok 'join creates posts/' || no 'join creates posts/'
[ -f "$room/.moot/rooms/board/posts/.gitkeep" ] && ok 'join seeds posts/.gitkeep' || no 'join seeds posts/.gitkeep'
[ -d "$room/.moot/seen/board" ] && ok 'join creates the room cursor directory' || no 'join creates the room cursor directory'
# rooms/<room>/ is the folder that syncs, and posts/ is all of it. A .gitkeep
# anywhere else in .moot/ would invite committing one participant's state.
[ -e "$room/.moot/seen/board/.gitkeep" ] && no 'join leaves seen/ ungitkept' || ok 'join leaves seen/ ungitkept'
check 'the room holds nothing but posts/' "$(ls -A "$room/.moot/rooms/board")" 'posts'

"$room/.moot/moot.sh" post --as bob -m 'hello' >/dev/null
out=$("$room/.moot/moot.sh" init)
check 'init is idempotent' "$out" "moot already initialised at $room/.moot"
check 'init keeps existing posts' "$(ls "$room/.moot/rooms/board/posts"/*.md | wc -l | tr -d ' ')" '1'

out=$("$room/.moot/moot.sh" init --json)
case $out in *'"changed":false'*) ok 'init --json reports unchanged' ;; *) no 'init --json reports unchanged' "$out" ;; esac
case $out in *'"room":"board"'*) ok 'init --json reports the resolved default room' ;; *) no 'init --json reports the resolved default room' "$out" ;; esac

group 'join and rooms'
host=$(new_host); j() { "$host/.moot/moot.sh" "$@"; }
out=$(j join board)
check 'join reports the room it made' "$out" 'joined rooms/board'
out=$(j join board)
check 'join twice is a no-op' "$out" 'already in rooms/board'
j post --as bob -m 'still here' >/dev/null
j join board >/dev/null
check 'join keeps the posts already there' "$(ls "$host/.moot/rooms/board/posts"/*.md | wc -l | tr -d ' ')" '1'

j join release >/dev/null
check 'rooms lists what is subscribed' "$(j rooms | sed 's/^..//' | tr '\n' ' ')" 'board release '
check 'rooms marks no default when there is none' "$(j rooms | grep -c '^\*')" '0'
j init --room release >/dev/null
check 'init --room writes .moot/room' "$(cat "$host/.moot/room")" 'release'
check 'rooms marks the default' "$(j rooms | grep '^\*')" '* release'

# A room dropped in by copy is subscribed by being there.
mkdir -p "$host/.moot/rooms/arrived/posts"
printf 'over rsync\n' > "$host/.moot/rooms/arrived/posts/20260829-100000-bob.md"
check 'a copied-in room is subscribed with no join' "$(j read --room arrived | grep -c 'over rsync')" '1'
out=$(j join arrived)
check 'join on a copied-in room only makes the cursor dir' "$out" 'joined rooms/arrived'
check 'and it left the posts alone' "$(ls "$host/.moot/rooms/arrived/posts"/*.md | wc -l | tr -d ' ')" '1'

j join 'bad room' >/dev/null 2>&1 && no 'join refuses an unsafe room name' || ok 'join refuses an unsafe room name'
check 'and says why' "$(j join 'bad room' 2>&1 >/dev/null | tail -1)" \
  "moot: room name 'bad room' is not filename-safe (use A-Z a-z 0-9 . _ -)"
[ -e "$host/.moot/rooms/bad room" ] && no 'an unsafe room name writes no path' || ok 'an unsafe room name writes no path'

# ---------------------------------------------------------------- subscribe

# A room that already lives somewhere else. Every test here clones from a local
# bare repository, so the suite stays bash and coreutils and never touches a
# network.
new_remote() {
  local dir; dir=$(mktemp -d "$work/remote.XXXXXX")
  git init -q --bare "$dir/board.git"
  printf '%s' "$dir/board.git"
}

group 'subscribe'
remote=$(new_remote)
host=$(new_host); s() { "$host/.moot/moot.sh" "$@"; }
out=$(s subscribe "$remote")
check 'subscribe reports the room it made' "$out" 'subscribed rooms/board'
check 'and the name came from the url' "$(s rooms | sed 's/^..//' | tr -d '\n')" 'board'
check 'the room is the clone' "$(git -C "$host/.moot/rooms/board" remote get-url origin)" "$remote"
check 'so the address needs no file of its own' "$(ls -A "$host/.moot" | grep -c '^remotes$')" '0'
check 'and posts/ is ready before the remote has one' \
  "$([ -e "$host/.moot/rooms/board/posts/.gitkeep" ] && echo yes)" 'yes'

s post --as bob -m 'over git' >/dev/null
check 'a subscribed room posts and reads like any other' "$(s read | grep -c 'over git')" '1'
check 'and .git is not a post' "$(s read | grep -c '\.git')" '0'
check 'the cursor is beside the room, not in it' \
  "$([ -d "$host/.moot/seen/board" ] && echo yes)" 'yes'
[ -e "$host/.moot/rooms/board/seen" ] && no 'nothing of mine lands inside the clone' || ok 'nothing of mine lands inside the clone'

out=$(s subscribe "$remote" 2>&1 >/dev/null | tail -1)
check 'subscribe refuses a room already here' "$out" 'moot: room board is already here (rooms/board)'
s subscribe "$remote" release >/dev/null
check 'an explicit name overrides the url' "$(s rooms | sed 's/^..//' | tr '\n' ' ')" 'board release '
check 'a trailing slash still derives the name' \
  "$(s subscribe "$remote/" third >/dev/null; s rooms | sed 's/^..//' | tr '\n' ' ')" 'board release third '
check 'subscribe --json names the room' \
  "$(s subscribe --json "$remote" fourth | sed 's/.*"room":"\([^"]*\)".*/\1/')" 'fourth'

s subscribe "$remote" 'bad room' >/dev/null 2>&1 && no 'subscribe refuses an unsafe room name' || ok 'subscribe refuses an unsafe room name'
out=$(s subscribe "$work/nope.git" 2>&1 >/dev/null | tail -1)
case $out in 'moot: cannot clone '*) ok 'a clone that fails says so in moot'"'"'s voice' ;; *) no 'a clone that fails says so in moot'"'"'s voice' "$out" ;; esac
[ -e "$host/.moot/rooms/nope" ] && no 'and leaves no half-room behind' || ok 'and leaves no half-room behind'

# The one verb with a hard dependency says which one, rather than leaking
# git's own stderr from three frames down.
# A PATH with everything the tool uses except the one thing this verb needs.
mkdir -p "$work/nogit"
for p in /bin/* /usr/bin/*; do
  b=${p##*/}
  [ "$b" = git ] && continue
  ln -sf "$p" "$work/nogit/$b" 2>/dev/null
done
out=$(PATH="$work/nogit" "$work/nogit/bash" "$host/.moot/moot.sh" subscribe "$remote" solo 2>&1 >/dev/null | tail -1)
check 'subscribe without git says so plainly' "$out" 'moot: subscribe needs git on PATH'

# ---------------------------------------------------------------- git transport

# Two clones of one bare repository, exchanging posts with no manual git.
group 'a cloned room syncs both ways'
remote=$(new_remote)
a=$(new_host); b=$(new_host)
"$a/.moot/moot.sh" subscribe "$remote" >/dev/null
"$b/.moot/moot.sh" subscribe "$remote" >/dev/null
al() { "$a/.moot/moot.sh" "$@"; }; bo() { "$b/.moot/moot.sh" "$@"; }
al post --as alice -m 'hello from alice' >/dev/null
bo catchup --as bob >/dev/null
check 'a post reaches the other clone through catchup' "$(bo read | grep -c 'hello from alice')" '1'
bo post --as bob -m 'and back' >/dev/null
al catchup --as alice >/dev/null
check 'and the reply comes back the same way' "$(al read | grep -c 'and back')" '1'
id=$(al post --json --as alice -m 'named commit' | sed 's/.*"id":"\([^"]*\)".*/\1/')
check 'the commit is named for the post' "$(git -C "$a/.moot/rooms/board" log -1 --pretty=%s)" "$id"
check 'and nothing outside posts/ is tracked' "$(git -C "$a/.moot/rooms/board" ls-files | grep -cv '^posts/')" '0'

# The one failure a board must not have. The post is a file before git is
# involved, so the network can only cost a warning.
group 'a post survives an unreachable remote'
mv "$remote" "$remote.gone"
al post --as alice -m 'written while offline' 2>"$work/warn" >/dev/null; rc=$?
check 'and exits clean' "$rc" '0'
check 'post warns rather than failing' "$(tail -1 "$work/warn")" 'moot: posted, but could not push board to its remote'
check 'and the post is here regardless' "$(al read | grep -c 'written while offline')" '1'
out=$(bo catchup --as bob 2>&1 >/dev/null | tail -1)
check 'catchup warns and reads what is here' "$out" 'moot: could not fetch board; reading what is here'
mv "$remote.gone" "$remote"
al catchup --as alice >/dev/null
bo catchup --as bob >/dev/null
check 'the backlog drains on the next catchup' "$(bo read | grep -c 'written while offline')" '1'

# Immutable uniquely-named files mean the rebase behind the push retry has no
# conflict available to have.
group 'two clones posting at once'
al post --as alice -m 'alice over bob' >/dev/null 2>&1
bo post --as bob -m 'bob over alice' >/dev/null 2>&1
al catchup --as alice >/dev/null; bo catchup --as bob >/dev/null
al catchup --as alice >/dev/null
check 'both messages reach alice' "$(al read | grep -c ' over ')" '2'
check 'both messages reach bob' "$(bo read | grep -c ' over ')" '2'
check 'and neither clone invented a post' \
  "$(ls "$a/.moot/rooms/board/posts"/*.md | wc -l | tr -d ' ')" \
  "$(ls "$b/.moot/rooms/board/posts"/*.md | wc -l | tr -d ' ')"

# A room that is a clone syncs; a room that is not, does not.
group 'a room that is not a clone is untouched'
host=$(new_room); m() { "$host/.moot/moot.sh" "$@"; }
m post --as bob -m 'plain room' >/dev/null
check 'catchup on a plain room says nothing about git' "$(m catchup --as bob 2>&1 >/dev/null)" ''
check 'post on a plain room says nothing about git' "$(m post --as bob -m 'again' 2>&1 >/dev/null)" ''
[ -e "$host/.moot/rooms/board/.git" ] && no 'and no repository appears' || ok 'and no repository appears'

group 'room resolution'
host=$(new_host); j() { "$host/.moot/moot.sh" "$@"; }
out=$(j post --as bob -m 'x' 2>&1 >/dev/null)
case $out in *'no rooms here yet'*) ok 'no rooms at all fails usefully' ;; *) no 'no rooms at all fails usefully' "$out" ;; esac
check 'and rooms says the same' "$(j rooms | grep -c 'no rooms here yet')" '1'

j join board >/dev/null
j post --as bob -m 'flagless' >/dev/null
check 'the sole room needs no flag' "$(ls "$host/.moot/rooms/board/posts"/*.md | wc -l | tr -d ' ')" '1'

j join release >/dev/null
out=$(j post --as bob -m 'x' 2>&1 >/dev/null)
case $out in *'several rooms here and none chosen'*) ok 'two rooms and no pointer fails usefully' ;; *) no 'two rooms and no pointer fails usefully' "$out" ;; esac
case $out in *board*release*) ok 'the error lists what is subscribed' ;; *) no 'the error lists what is subscribed' "$out" ;; esac
case $out in *'--room'*) ok 'the error names the fix' ;; *) no 'the error names the fix' "$out" ;; esac

printf 'release\n' > "$host/.moot/room"
j post --as bob -m 'pointed' >/dev/null
check '.moot/room makes it work again' "$(ls "$host/.moot/rooms/release/posts"/*.md | wc -l | tr -d ' ')" '1'
MOOT_ROOM=board j post --as bob -m 'env' >/dev/null
check '$MOOT_ROOM overrides .moot/room' "$(ls "$host/.moot/rooms/board/posts"/*.md | wc -l | tr -d ' ')" '2'
MOOT_ROOM=board j post --as bob --room release -m 'flag' >/dev/null
check '--room overrides $MOOT_ROOM' "$(ls "$host/.moot/rooms/release/posts"/*.md | wc -l | tr -d ' ')" '2'

check 'the two rooms hold their own posts' "$(j read --room board | grep -c 'pointed')" '0'
j catchup --as bob --room board >/dev/null
[ -f "$host/.moot/seen/board/bob" ] && ok 'a cursor is per-room' || no 'a cursor is per-room'
[ -e "$host/.moot/seen/release/bob" ] && no 'and the other room keeps its own' || ok 'and the other room keeps its own'

j post --as bob --room 'bad room' -m 'x' >/dev/null 2>&1 && no 'post refuses an unsafe room name' || ok 'post refuses an unsafe room name'

# ---------------------------------------------------------------- posting

group 'post'
room=$(new_room)
out=$("$room/.moot/moot.sh" post --json --as bob -m 'first')
case $out in *'"ok":true'*'"sender":"bob"'*) ok 'post --json reports the post' ;; *) no 'post --json reports the post' "$out" ;; esac

id=$(printf '%s' "$out" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
check 'post body is the file, byte for byte' "$(cat "$room/.moot/rooms/board/posts/$id.md")" 'first'
case $id in [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]-bob) ok 'post id follows the filename grammar' ;; *) no 'post id follows the filename grammar' "$id" ;; esac

echo 'from stdin' | "$room/.moot/moot.sh" post --as bob - >/dev/null
printf 'from a file\n' > "$work/msg.md"
"$room/.moot/moot.sh" post --as bob -f "$work/msg.md" >/dev/null
check 'post accepts -m, -, and -f' "$(ls "$room/.moot/rooms/board/posts"/*.md | wc -l | tr -d ' ')" '3'

"$room/.moot/moot.sh" post --as bob -m '' >/dev/null 2>&1 && no 'post refuses an empty message' || ok 'post refuses an empty message'
"$room/.moot/moot.sh" post --as 'bad name' -m 'x' >/dev/null 2>&1 && no 'post refuses an unsafe sender name' || ok 'post refuses an unsafe sender name'

check 'there is no edit verb'   "$("$room/.moot/moot.sh" edit x 2>&1 >/dev/null | tail -1)" 'moot: unknown command: edit'
check 'there is no delete verb' "$("$room/.moot/moot.sh" delete x 2>&1 >/dev/null | tail -1)" 'moot: unknown command: delete'

group 'post is atomic'
room=$(new_room)
"$room/.moot/moot.sh" post --as bob -m 'done' >/dev/null
check 'post leaves no landing file' "$(ls -A "$room/.moot/rooms/board/posts" | grep -c landing)" '0'
# A post mid-compose must be invisible to every reader, tool or human.
: > "$room/.moot/rooms/board/posts/.20260829-120000-tengu.999.landing"
check 'a landing file is not a post' "$("$room/.moot/moot.sh" read | grep -c 'tengu')" '0'
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
"$room/.moot/moot.sh" post --as tengu -m 'one' >/dev/null
"$room/.moot/moot.sh" post --as tengu -m 'two' >/dev/null
"$room/.moot/moot.sh" post --as tengu -m 'three' >/dev/null
thaw_step
check 'a same-second clash re-stamps instead of suffixing' "$(ls "$posts" | tr '\n' ' ')" \
  '20260829-163412-tengu.md 20260829-163413-tengu.md 20260829-163414-tengu.md '
check 'no post was overwritten' "$(cat "$posts/20260829-163412-tengu.md")" 'one'
check 'the re-stamped post kept its own body' "$(cat "$posts/20260829-163414-tengu.md")" 'three'
check 'read shows them in the order written' \
  "$("$room/.moot/moot.sh" read | grep -E '^(one|two|three)$' | tr '\n' ' ')" 'one two three '
check 'read names the sender plainly' "$("$room/.moot/moot.sh" read | grep -c '· tengu ──')" '3'

# A hyphenated sender, the case a -N suffix could not be told apart from.
room=$(new_room)
posts="$room/.moot/rooms/board/posts"
step_date 20260829-163412 20260829-163412 20260829-163413
"$room/.moot/moot.sh" post --as tengu-the-gremlin -m 'a' >/dev/null
"$room/.moot/moot.sh" post --as tengu-the-gremlin -m 'b' >/dev/null
thaw_step
check 'a hyphenated sender re-stamps too' "$(ls "$posts" | tr '\n' ' ')" \
  '20260829-163412-tengu-the-gremlin.md 20260829-163413-tengu-the-gremlin.md '

# A directory post holds the id as surely as a file does.
room=$(new_room)
posts="$room/.moot/rooms/board/posts"
mkdir "$posts/20260829-163412-bob"; printf 'with files\n' > "$posts/20260829-163412-bob/post.md"
step_date 20260829-163412 20260829-163413
"$room/.moot/moot.sh" post --as bob -m 'plain' >/dev/null
thaw_step
[ -f "$posts/20260829-163413-bob.md" ] && ok 'a directory post of the same id counts as taken' \
  || no 'a directory post of the same id counts as taken'

# A clock that never moves gives up rather than spin.
room=$(new_room)
posts="$room/.moot/rooms/board/posts"
step_date 20260829-163412
"$room/.moot/moot.sh" post --as tengu -m 'first' >/dev/null
err=$("$room/.moot/moot.sh" post --as tengu -m 'stuck' 2>&1 >/dev/null); rc=$?
thaw_step
[ "$rc" -ne 0 ] && ok 'a stopped clock fails the post' || no 'a stopped clock fails the post'
check 'and says why' "$(printf '%s' "$err" | grep -c 'clock is not moving')" '1'
check 'and leaves no landing file behind' "$(ls -A "$posts" | grep -c landing)" '0'
check 'and claims nothing' "$(ls "$posts" | wc -l | tr -d ' ')" '1'

# -N posts from before the change still read and catch up in order, once.
room=$(new_room)
posts="$room/.moot/rooms/board/posts"
printf '@bob first\n'  > "$posts/20260829-163412-tengu.md"
printf '@bob second\n' > "$posts/20260829-163412-tengu-2.md"
check 'an old -N post reads after the one without it' \
  "$("$room/.moot/moot.sh" read | grep -E '^@bob' | tr '\n' ' ')" '@bob first @bob second '
first=$("$room/.moot/moot.sh" catchup --json --as bob)
again=$("$room/.moot/moot.sh" catchup --json --as bob)
check 'catchup delivers both old posts once' "$(printf '%s' "$first" | grep -o '"delivered":[0-9]*' | head -n 1)" '"delivered":2'
check 'and not again on the next run' "$(printf '%s' "$again" | grep -o '"delivered":[0-9]*' | head -n 1)" '"delivered":0'

# ---------------------------------------------------------------- ordering

group 'ordering'
room=$(new_room)
for stamp in 20260829-120000 20260829-090000 20260830-010000 20260828-235959; do
  printf 'body %s\n' "$stamp" > "$room/.moot/rooms/board/posts/$stamp-bob.md"
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
printf 'already here\n' > "$room/.moot/rooms/board/posts/20260829-090000-bob.md"
MOOT_FOLLOW_INTERVAL=0.2 "$room/.moot/moot.sh" read --follow > "$work/follow.out" 2>&1 &
follow_pid=$!
sleep 1
printf 'arrived later\n' > "$room/.moot/rooms/board/posts/20260829-100000-tengu.md"
sleep 1
kill "$follow_pid" 2>/dev/null
wait "$follow_pid" 2>/dev/null
check '--follow prints the existing board' "$(grep -c 'already here' "$work/follow.out")" '1'
check '--follow appends a post that arrives' "$(grep -c 'arrived later' "$work/follow.out")" '1'
check '--follow does not repeat a post' "$(grep -c 'already here' "$work/follow.out")" '1'
check '--follow writes nothing back into the moot' "$(ls -A "$room/.moot/rooms/board/posts" | grep -vc gitkeep)" '2'

# ---------------------------------------------------------------- attachments

group 'attachments'
room=$(new_room)
mkdir -p "$room/.moot/rooms/board/posts/20260829-164070-bob"
printf 'see the patch @tengu\n' > "$room/.moot/rooms/board/posts/20260829-164070-bob/post.md"
printf 'diff goes here\n' > "$room/.moot/rooms/board/posts/20260829-164070-bob/diff.patch"
printf 'a plain one\n' > "$room/.moot/rooms/board/posts/20260829-170000-tengu.md"
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
sender_of() { ls "$1/.moot/rooms/board/posts"/*.md | sed -n 's/.*-\([^-]*\)\.md$/\1/p' | tail -1; }

MOOT_NAME=envname USER=username "$room/.moot/moot.sh" post --as flagname -m 'x' >/dev/null
check '--as wins' "$(sender_of "$room")" 'flagname'

room=$(new_room)
MOOT_NAME=envname USER=username "$room/.moot/moot.sh" post -m 'x' >/dev/null
check '$MOOT_NAME comes next' "$(sender_of "$room")" 'envname'

room=$(new_room)
printf 'localname\n' > "$room/.moot/name"
mkdir -p "$room/.gremlin"
printf 'name=tengu\n' > "$room/.gremlin/name"
( cd "$room" && MOOT_NAME= USER=username "$room/.moot/moot.sh" post -m 'x' >/dev/null )
check '.moot/name comes next' "$(sender_of "$room")" 'localname'

# .gremlin/name is a key=value file. Taking the whole line yields "name=tengu",
# which is not a filename-safe sender.
room=$(new_room)
mkdir -p "$room/.gremlin"
printf 'name=tengu\nsource=generated\nvocabulary=1\n' > "$room/.gremlin/name"
( cd "$room" && MOOT_NAME= USER=username "$room/.moot/moot.sh" post -m 'x' >/dev/null )
check '.gremlin/name comes next' "$(sender_of "$room")" 'tengu'

room=$(new_room)
mkdir -p "$room/.gremlin"
printf 'tengu\n' > "$room/.gremlin/name"
( cd "$room" && MOOT_NAME= USER=username "$room/.moot/moot.sh" post -m 'x' >/dev/null )
check 'a bare .gremlin/name still resolves' "$(sender_of "$room")" 'tengu'

room=$(new_room)
printf 'bad=name\n' > "$room/.moot/name"
( cd "$room" && MOOT_NAME= USER=username "$room/.moot/moot.sh" post -m 'x' >/dev/null 2>&1 ) \
  && no 'an unsafe .moot/name is an error' || ok 'an unsafe .moot/name is an error'

room=$(new_room)
"$room/.moot/moot.sh" init --as chosen >/dev/null
check 'init --as writes .moot/name' "$(cat "$room/.moot/name")" 'chosen'
( cd "$work" && MOOT_NAME= USER=username "$room/.moot/moot.sh" post -m 'x' >/dev/null )
check 'and posting picks it up' "$(sender_of "$room")" 'chosen'

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
"$inner/.moot/moot.sh" join board >/dev/null
( cd "$inner" && MOOT_NAME= USER=username "$inner/.moot/moot.sh" post -m 'x' >/dev/null )
check 'an ancestor .gremlin/name is not a sibling' "$(sender_of "$inner")" 'host'

# The wiring line a gremlin host runs is relative, from the host root.
room=$(new_room)
mkdir -p "$room/.gremlin" "$room/.nest/in"
printf 'name=fanta\n' > "$room/.gremlin/name"
printf '@fanta over to you\n' > "$room/.moot/rooms/board/posts/20260829-100000-bob.md"
( cd "$room" && MOOT_NAME= USER=username ./.moot/moot.sh catchup --deliver .nest/in/ >/dev/null )
check 'the relative wiring line delivers' "$(ls "$room/.nest/in" | wc -l | tr -d ' ')" '1'

# The last resort is the folder .moot/ sits in, so a repo needs no name file.
named="$work/bopOS"; mkdir -p "$named"
"$repo/install.sh" "$named" >/dev/null; "$named/.moot/moot.sh" join board >/dev/null
( cd "$work" && MOOT_NAME= USER=username "$named/.moot/moot.sh" post -m 'x' >/dev/null )
check 'the host folder name is the last resort, not $USER' "$(sender_of "$named")" 'bopOS'
( cd / && env -u MOOT_NAME -u USER "$named/.moot/moot.sh" post -m 'y' >/dev/null )
check 'and needs no $USER at all' "$(ls "$named/.moot/rooms/board/posts" | grep -c 'bopOS')" '2'

spaced="$work/Pedal Board"; mkdir -p "$spaced"
"$repo/install.sh" "$spaced" >/dev/null; "$spaced/.moot/moot.sh" join board >/dev/null
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
( cd "$room" && echo 'posted by hand' > ".moot/rooms/board/posts/$(date -u +%Y%m%d-%H%M%S)-bob.md" )
check 'a hand-written post is a post' "$("$room/.moot/moot.sh" read | grep -c 'posted by hand')" '1'
"$room/.moot/moot.sh" post --as tengu -m 'posted by tool' >/dev/null
check 'a tool-written post is readable by hand' "$(cat "$room"/.moot/rooms/board/posts/*-tengu.md)" 'posted by tool'

# ---------------------------------------------------------------- catchup

group 'catchup'
room=$(new_room)
m() { "$room/.moot/moot.sh" "$@"; }
say() { printf '%s\n' "$2" > "$room/.moot/rooms/board/posts/$1.md"; }

say 20260829-100000-bob   'board is up'
say 20260829-100100-bob   'hey @tengu can you look at the thing'
say 20260829-100200-bob   'unrelated announcement'
say 20260829-100300-bob   '@all standup moved'
say 20260829-100400-bob   'nice work @fanta'

out=$(m catchup --as tengu)
check 'catchup delivers a direct mention' "$(printf '%s' "$out" | grep -c 'can you look at')" '1'
check 'catchup delivers @all'             "$(printf '%s' "$out" | grep -c 'standup moved')" '1'
check 'catchup skips an unmentioned post' "$(printf '%s' "$out" | grep -c 'unrelated')" '0'
check 'catchup skips someone else atted'  "$(printf '%s' "$out" | grep -c 'nice work')" '0'
check 'catchup writes the cursor' "$(cat "$room/.moot/seen/board/tengu")" '20260829-100400-bob'

out=$(m catchup --as tengu)
check 'a re-run delivers nothing'  "$(printf '%s' "$out" | grep -c 'can you look at')" '0'
check 'the cursor did not move back' "$(cat "$room/.moot/seen/board/tengu")" '20260829-100400-bob'

say 20260829-100500-bob '@tengu one more'
out=$(m catchup --as tengu)
check 'catchup resumes from the cursor' "$(printf '%s' "$out" | grep -c 'one more')" '1'
check 'catchup does not re-deliver older mentions' "$(printf '%s' "$out" | grep -c 'can you look at')" '0'

check 'the whole board is still readable' "$(m read | grep -c 'unrelated announcement')" '1'
check 'catchup advanced past unmentioned posts' "$(cat "$room/.moot/seen/board/tengu")" '20260829-100500-bob'

group 'catchup and nobody'
room=$(new_room); m() { "$room/.moot/moot.sh" "$@"; }; say() { printf '%s\n' "$2" > "$room/.moot/rooms/board/posts/$1.md"; }
say 20260829-100000-bob 'hello @nobodyatall'
out=$(m catchup --as tengu)
check 'a mention of nobody reaches nobody' "$(printf '%s' "$out" | grep -c 'hello')" '0'
check 'a mention of nobody still advances the cursor' "$(cat "$room/.moot/seen/board/tengu")" '20260829-100000-bob'
check 'the mistyped mention is visible on the board' "$(m read | grep -c '@nobodyatall')" '1'

group 'mention matching'
room=$(new_room); m() { "$room/.moot/moot.sh" "$@"; }; say() { printf '%s\n' "$2" > "$room/.moot/rooms/board/posts/$1.md"; }
say 20260829-100000-bob 'thanks @tengu.'
say 20260829-100100-bob 'ask @tengu, please'
say 20260829-100200-bob 'not @tengulike'
say 20260829-100300-bob 'an email a@tengu is not a mention of a'
out=$(m catchup --as tengu)
check 'a trailing full stop still mentions'   "$(printf '%s' "$out" | grep -c 'thanks')" '1'
check 'a trailing comma still mentions'       "$(printf '%s' "$out" | grep -c 'please')" '1'
check 'a longer name is a different name'     "$(printf '%s' "$out" | grep -c 'not @tengulike')" '0'

group 'catchup --deliver'
room=$(new_room); m() { "$room/.moot/moot.sh" "$@"; }; say() { printf '%s\n' "$2" > "$room/.moot/rooms/board/posts/$1.md"; }
inbox="$work/inbox"; rm -rf "$inbox"
say 20260829-100000-bob 'quiet announcement'
say 20260829-100100-bob '@tengu please handle the thing bob raised earlier'
m catchup --as tengu --deliver "$inbox" >/dev/null
check '--deliver writes one file per mention' "$(ls "$inbox" | wc -l | tr -d ' ')" '1'
delivered=$(ls "$inbox")
case $delivered in *20260829-100100-bob*) ok 'a delivered filename carries the post id' ;; *) no 'a delivered filename carries the post id' "$delivered" ;; esac
case $delivered in moot-board-*) ok 'a delivered filename carries the room' ;; *) no 'a delivered filename carries the room' "$delivered" ;; esac
check '--deliver leaves no landing file' "$(ls -A "$inbox" | grep -c landing)" '0'
body=$(cat "$inbox/$delivered")
case $body in *"please handle the thing"*) ok 'a delivered item carries the body' ;; *) no 'a delivered item carries the body' ;; esac
case $body in *"$room"*) ok 'a delivered item carries the path to the moot' ;; *) no 'a delivered item carries the path to the moot' ;; esac
case $body in *'20260829-100100-bob'*) ok 'a delivered item carries its own post id' ;; *) no 'a delivered item carries its own post id' ;; esac
case $body in *'read --room board --tail'*) ok 'a delivered item says how to read backwards' ;; *) no 'a delivered item says how to read backwards' "$body" ;; esac
case $body in *'- room: `board`'*) ok 'a delivered item names its room' ;; *) no 'a delivered item names its room' "$body" ;; esac
check '--deliver delivers only mentions' "$(grep -rc 'quiet announcement' "$inbox" | grep -c ':1$')" '0'

m catchup --as tengu --deliver "$inbox" >/dev/null
check 'a re-run delivers nothing twice' "$(ls "$inbox" | wc -l | tr -d ' ')" '1'

# Moot does not know what a nest is: gremlin integration is a path.
rm -rf "$work/nest"; mkdir -p "$work/nest/in"
rm -f "$room/.moot/seen/board/tengu"
m catchup --as tengu --deliver "$work/nest/in" >/dev/null
check '--deliver takes any directory the caller names' "$(ls "$work/nest/in" | wc -l | tr -d ' ')" '1'

group 'catchup on a read-only moot'
room=$(new_room); m() { "$room/.moot/moot.sh" "$@"; }; say() { printf '%s\n' "$2" > "$room/.moot/rooms/board/posts/$1.md"; }
say 20260829-100000-bob '@tengu the board is read-only from here'
inbox="$work/ro-inbox"; rm -rf "$inbox"; mkdir -p "$inbox"
chmod -w "$room/.moot/seen/board"
m catchup --as tengu --deliver "$inbox" >/dev/null 2>"$work/ro.err"
check 'a read-only moot still delivers' "$(ls "$inbox" | wc -l | tr -d ' ')" '1'
check 'a read-only moot warns about the cursor' "$(grep -c 'read-only room' "$work/ro.err")" '1'
m catchup --as tengu --deliver "$inbox" >/dev/null 2>&1
check 'a read-only moot still delivers nothing twice' "$(ls "$inbox" | wc -l | tr -d ' ')" '1'
chmod +w "$room/.moot/seen/board"

group 'catchup name resolution and --json'
room=$(new_room); m() { "$room/.moot/moot.sh" "$@"; }; say() { printf '%s\n' "$2" > "$room/.moot/rooms/board/posts/$1.md"; }
mkdir -p "$room/.gremlin"; printf 'name=fanta\n' > "$room/.gremlin/name"
say 20260829-100000-bob '@fanta over to you'
( cd "$room" && MOOT_NAME= USER=username "$room/.moot/moot.sh" catchup >/dev/null )
[ -f "$room/.moot/seen/board/fanta" ] && ok 'catchup uses the same name chain as post' || no 'catchup uses the same name chain as post'

room=$(new_room); m() { "$room/.moot/moot.sh" "$@"; }; say() { printf '%s\n' "$2" > "$room/.moot/rooms/board/posts/$1.md"; }
say 20260829-100000-bob '@tengu hi'
out=$(m catchup --json --as tengu)
case $out in *'"delivered":[{"room":"board","id":"20260829-100000-bob"}]'*) ok 'catchup --json names the room of what it delivered' ;; *) no 'catchup --json names the room of what it delivered' "$out" ;; esac
case $out in *'"since":null'*) ok 'catchup --json reports no prior cursor as null' ;; *) no 'catchup --json reports no prior cursor as null' "$out" ;; esac
case $out in *'"rooms":[{"room":"board"'*) ok 'catchup --json reports one entry per room swept' ;; *) no 'catchup --json reports one entry per room swept' "$out" ;; esac
out=$(m catchup --json --as tengu)
case $out in *'"changed":false'*'"delivered":[]'*) ok 'catchup --json reports an unchanged re-run' ;; *) no 'catchup --json reports an unchanged re-run' "$out" ;; esac

group 'catchup sweeps every room'
host=$(new_host); j() { "$host/.moot/moot.sh" "$@"; }
for r in board release ops; do
  j join "$r" >/dev/null
  printf '@tengu the %s thing\n' "$r" > "$host/.moot/rooms/$r/posts/20260829-100000-bob.md"
done
inbox="$work/sweep-inbox"; rm -rf "$inbox"
out=$(j catchup --as tengu --deliver "$inbox")
check 'one call delivers from every room' "$(ls "$inbox" | wc -l | tr -d ' ')" '3'
check 'and says so on one line' "$(printf '%s' "$out" | wc -l | tr -d ' ')" '0'
check 'the sweep advances every cursor' "$(ls "$host/.moot/seen"/*/tengu | wc -l | tr -d ' ')" '3'
j catchup --as tengu --deliver "$inbox" >/dev/null
check 'a re-run of the sweep delivers nothing twice' "$(ls "$inbox" | wc -l | tr -d ' ')" '3'

# Two rooms can produce the same post id in the same second from the same
# sender. The filename is the whole duplicate-suppression mechanism.
host=$(new_host); j() { "$host/.moot/moot.sh" "$@"; }
j join board >/dev/null; j join release >/dev/null
printf '@tengu same second, board\n' > "$host/.moot/rooms/board/posts/20260829-100000-bob.md"
printf '@tengu same second, release\n' > "$host/.moot/rooms/release/posts/20260829-100000-bob.md"
inbox="$work/clash-inbox"; rm -rf "$inbox"
j catchup --as tengu --deliver "$inbox" >/dev/null
check 'a same-second clash across rooms delivers both' "$(ls "$inbox" | wc -l | tr -d ' ')" '2'
check 'and neither body was lost' "$(cat "$inbox"/* | grep -c 'same second,')" '2'

group 'catchup --room narrows the sweep'
host=$(new_host); j() { "$host/.moot/moot.sh" "$@"; }
j join board >/dev/null; j join release >/dev/null
printf '@tengu board\n' > "$host/.moot/rooms/board/posts/20260829-100000-bob.md"
printf '@tengu release\n' > "$host/.moot/rooms/release/posts/20260829-100000-bob.md"
inbox="$work/narrow-inbox"; rm -rf "$inbox"
j catchup --as tengu --room board --deliver "$inbox" >/dev/null
check '--room delivers from that room only' "$(ls "$inbox" | wc -l | tr -d ' ')" '1'
[ -f "$host/.moot/seen/board/tengu" ] && ok '--room advances that cursor' || no '--room advances that cursor'
[ -e "$host/.moot/seen/release/tengu" ] && no '--room leaves the other cursor alone' || ok '--room leaves the other cursor alone'
j catchup --as tengu --room nosuch >/dev/null 2>&1 && no '--room on an unjoined room is an error' || ok '--room on an unjoined room is an error'

group 'a read-only room does not stop the sweep'
host=$(new_host); j() { "$host/.moot/moot.sh" "$@"; }
for r in aa bb cc; do
  j join "$r" >/dev/null
  printf '@tengu the %s thing\n' "$r" > "$host/.moot/rooms/$r/posts/20260829-100000-bob.md"
done
chmod -w "$host/.moot/seen/bb"
inbox="$work/ro-sweep"; rm -rf "$inbox"
j catchup --as tengu --deliver "$inbox" >/dev/null 2>"$work/ro-sweep.err"
check 'the read-only room still delivered' "$(ls "$inbox" | wc -l | tr -d ' ')" '3'
check 'and warned about its cursor' "$(grep -c 'read-only room' "$work/ro-sweep.err")" '1'
[ -f "$host/.moot/seen/cc/tengu" ] && ok 'the room after it was still swept' || no 'the room after it was still swept'
chmod +w "$host/.moot/seen/bb"

group 'catchup with no rooms at all'
host=$(new_host)
"$host/.moot/moot.sh" catchup --as tengu >/dev/null 2>&1 && ok 'a host with no rooms exits clean' || no 'a host with no rooms exits clean'
check 'and says nothing' "$("$host/.moot/moot.sh" catchup --as tengu 2>&1 | wc -c | tr -d ' ')" '0'
out=$("$host/.moot/moot.sh" catchup --json --as tengu)
case $out in *'"rooms":[]'*'"delivered":[]'*) ok 'and --json reports an empty sweep' ;; *) no 'and --json reports an empty sweep' "$out" ;; esac

group 'catchup on an empty board'
room=$(new_room)
"$room/.moot/moot.sh" catchup --as tengu >/dev/null 2>&1 && ok 'catchup on an empty board succeeds' || no 'catchup on an empty board succeeds'
[ -e "$room/.moot/seen/board/tengu" ] && no 'an empty board writes no cursor' || ok 'an empty board writes no cursor'

group 'catchup and attachments'
room=$(new_room); m() { "$room/.moot/moot.sh" "$@"; }
mkdir -p "$room/.moot/rooms/board/posts/20260829-100000-bob"
printf '@tengu see the patch\n' > "$room/.moot/rooms/board/posts/20260829-100000-bob/post.md"
printf 'diff\n' > "$room/.moot/rooms/board/posts/20260829-100000-bob/diff.patch"
inbox="$work/att-inbox"; rm -rf "$inbox"
m catchup --as tengu --deliver "$inbox" >/dev/null
check 'an attachment post is delivered' "$(ls "$inbox" | wc -l | tr -d ' ')" '1'
case $(cat "$inbox"/*) in *'diff.patch'*) ok 'a delivered attachment post points at its files' ;; *) no 'a delivered attachment post points at its files' ;; esac

# ---------------------------------------------------------------- install

group 'install'
host=$(new_host)
[ -x "$host/.moot/moot.sh" ] && ok 'install deploys an executable moot.sh' || no 'install deploys an executable moot.sh'
[ -f "$host/.moot/README.md" ] && ok 'install deploys the README' || no 'install deploys the README'
[ -f "$host/.moot/SKILL.md" ] && ok 'install deploys the skill as SKILL.md' || no 'install deploys the skill as SKILL.md'
cmp -s "$repo/skills/moot.md" "$host/.moot/SKILL.md" && ok 'SKILL.md is the skill from skills/moot.md' || no 'SKILL.md is the skill from skills/moot.md'
check 'install claims nothing outside .moot/' "$(ls -A "$host")" '.moot'
printf 'stale\n' > "$host/.moot/SKILL.md"
"$repo/install.sh" "$host" >/dev/null
cmp -s "$repo/skills/moot.md" "$host/.moot/SKILL.md" && ok 're-running install refreshes the skill' || no 're-running install refreshes the skill'
check 'install is repeatable' "$(ls -A "$host/.moot" | wc -l | tr -d ' ')" '5'

# The ignore lines are a hint on stdout; install writes no .gitignore itself.
hint=$("$repo/install.sh" "$host")
for line in '.moot/rooms/' '.moot/seen/' '.moot/name'; do
  case $hint in *"  $line"*) ok "install hints at ignoring $line" ;; *) no "install hints at ignoring $line" ;; esac
done
[ ! -e "$host/.gitignore" ] && ok 'install writes no .gitignore' || no 'install writes no .gitignore'

# .moot/ is a dotdir among dotdirs: installing beside the rest of the family
# touches none of it.
host=$(mktemp -d "$work/family.XXXXXX")
mkdir -p "$host/.loom/threads" "$host/.nest/in"
printf 'a thread\n' > "$host/.loom/threads/keep.md"
"$repo/install.sh" "$host" >/dev/null
check 'install leaves .loom/ alone' "$(cat "$host/.loom/threads/keep.md")" 'a thread'
[ -d "$host/.nest/in" ] && ok 'install leaves .nest/ alone' || no 'install leaves .nest/ alone'
check 'and the dotdirs are peers' "$(ls -A "$host" | tr '\n' ' ')" '.loom .moot .nest '

# Each participant keeps a copy of the room, and their state inside it. The
# folder that syncs is posts/, and nothing in it is written by two hands.
group 'two participants'
room=$(new_room); m() { "$room/.moot/moot.sh" "$@"; }
m post --as bob -m '@tengu morning' >/dev/null
twin="$work/twin"; rm -rf "$twin"; cp -r "$room" "$twin"
m catchup --as bob >/dev/null
"$twin/.moot/moot.sh" catchup --as tengu >/dev/null
[ -e "$room/.moot/seen/board/tengu" ] && no 'a cursor never travels to the other copy' || ok 'a cursor never travels to the other copy'
[ -e "$twin/.moot/seen/board/bob" ] && no 'the other copy holds only its own cursor' || ok 'the other copy holds only its own cursor'
"$twin/.moot/moot.sh" post --as tengu -m 'on it' >/dev/null
before=$(cat "$room/.moot/seen/board/bob")
rsync -a "$twin/.moot/rooms/board/posts/" "$room/.moot/rooms/board/posts/"; rsync -a "$room/.moot/rooms/board/posts/" "$twin/.moot/rooms/board/posts/"
check 'the rooms reconcile on posts/ alone' "$(ls "$room/.moot/rooms/board/posts"/*.md | wc -l | tr -d ' ')" '2'
check 'syncing the room leaves the cursor alone' "$(cat "$room/.moot/seen/board/bob")" "$before"

group 'rooms shared by symlink'
# One parent holds the real room; two repos beside it link it in. Each repo
# keeps its own name (its folder) and its own cursor. No path has two writers.
parent=$(mktemp -d "$work/repos.XXXXXX")
"$repo/install.sh" "$parent" >/dev/null
printf 'bob\n' > "$parent/.moot/name"
"$parent/.moot/moot.sh" join dev >/dev/null
for r in bopOS easyhog; do
  mkdir -p "$parent/$r"
  "$repo/install.sh" "$parent/$r" >/dev/null
  ln -s "$parent/.moot/rooms/dev" "$parent/$r/.moot/rooms/dev"
done
b() { ( cd "$work" && MOOT_NAME= "$parent/bopOS/.moot/moot.sh" "$@" ); }
e() { ( cd "$work" && MOOT_NAME= "$parent/easyhog/.moot/moot.sh" "$@" ); }
h() { ( cd "$work" && MOOT_NAME= "$parent/.moot/moot.sh" "$@" ); }

check 'a linked room is a room' "$(b rooms | grep -c dev)" '1'
step_date 20260829-100000 20260829-100000 20260829-100000
b post -m '@easyhog dispatching two workers' >/dev/null
e post -m '@bopOS ok, holding mine' >/dev/null
h post -m '@all usage is fine' >/dev/null
thaw_step
check 'three repos posting in one second get three ids' \
  "$(ls "$parent/.moot/rooms/dev/posts" | tr '\n' ' ')" \
  '20260829-100000-bob.md 20260829-100000-bopOS.md 20260829-100000-easyhog.md '

out_e=$(e catchup --json)
check 'each repo catches up under its folder name' "$(printf '%s' "$out_e" | grep -o '"sender":"[^"]*"')" '"sender":"easyhog"'
check 'and gets what mentions it' "$(printf '%s' "$out_e" | grep -o '"delivered":[0-9]*' | head -n 1)" '"delivered":2'
[ -f "$parent/easyhog/.moot/seen/dev/easyhog" ] && ok 'the cursor lives in the reading repo' || no 'the cursor lives in the reading repo'
[ ! -e "$parent/.moot/seen/dev/easyhog" ] && ok 'and never in the room holder' || no 'and never in the room holder'
[ ! -e "$parent/.moot/rooms/dev/seen" ] && [ "$(ls -A "$parent/.moot/rooms/dev")" = posts ] \
  && ok 'the shared room holds posts/ and nothing else' || no 'the shared room holds posts/ and nothing else'
check "one repo's catchup leaves another's cursor alone" "$(ls -A "$parent/bopOS/.moot/seen/dev" 2>/dev/null | wc -l | tr -d ' ')" '0'
out_b=$(b catchup --json)
check 'the other repo still gets its own mentions' "$(printf '%s' "$out_b" | grep -o '"delivered":[0-9]*' | head -n 1)" '"delivered":2'
check 'and a second sweep delivers nothing twice' "$(b catchup --json | grep -o '"delivered":[0-9]*' | head -n 1)" '"delivered":0'

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
