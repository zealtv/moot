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

# A shared room in the store beside the checkouts (<checkouts>/.moots/<room>)
# is never shadowed by a private one. Each test builds its own store.
group 'a shared room of the same name'
checkouts=$(mktemp -d "$work/checkouts.XXXXXX")
mkdir -p "$checkouts/.moots/runs/posts" "$checkouts/app"
"$repo/install.sh" "$checkouts/app" >/dev/null
a() { "$checkouts/app/.moot/moot.sh" "$@"; }
store=$(cd "$checkouts" && pwd)/.moots/runs
out=$(a join runs 2>&1); rc=$?
check 'join refuses when a shared room of that name exists' "$rc" '1'
check 'and writes no private room' "$(ls -A "$checkouts/app/.moot/rooms" | wc -l | tr -d ' ')" '0'
check 'and prints the ln -s to run' "${out##*Link it instead: }" \
  "mkdir -p $(cd "$checkouts/app" && pwd)/.moot/rooms && ln -s $store $(cd "$checkouts/app" && pwd)/.moot/rooms/runs"
eval "${out##*Link it instead: }"
a post --as alice -m 'hello' 2>"$work/err" >/dev/null
check 'once linked, join works on the shared room' "$(a join runs)" 'joined rooms/runs'
check 'and a post lands in the shared room' "$(ls "$store/posts"/*.md | wc -l | tr -d ' ')" '1'
check 'and a linked room does not warn' "$(cat "$work/err")" ''
a join dev >/dev/null
check 'join still makes a room with no shared namesake' "$(ls -A "$checkouts/app/.moot/rooms/dev")" 'posts'

# In a bare copy of .moot/ there is no rooms/ yet, so the printed command has to
# make it: run it as printed in a fresh copy.
bare=$(mktemp -d "$work/bare.XXXXXX"); mkdir -p "$bare/.moots/runs/posts" "$bare/app"
cp -R "$repo/.moot" "$bare/app/"
rm -rf -- "${bare:?}/app/.moot/rooms" "${bare:?}/app/.moot/seen"
out=$("$bare/app/.moot/moot.sh" join runs 2>&1); rc=$?
check 'join refuses in a bare copy too' "$rc" '1'
[ ! -e "$bare/app/.moot/rooms" ] && ok 'and makes no rooms/ itself' || no 'and makes no rooms/ itself'
bare_cmd=${out##*Link it instead: }
case $bare_cmd in 'mkdir -p '*' && ln -s '*) ok 'and prints mkdir -p before ln -s' ;; *) no 'and prints mkdir -p before ln -s' "$bare_cmd" ;; esac
(eval "$bare_cmd") && ok 'the printed command runs in a bare copy' || no 'the printed command runs in a bare copy'
check 'and joining then works' "$("$bare/app/.moot/moot.sh" join runs)" 'joined rooms/runs'
[ "$bare/.moots/runs" -ef "$bare/app/.moot/rooms/runs" ] && ok 'and the link leads to the shared room' || no 'and the link leads to the shared room'

# A private room that predates the shared one still posts, with a warning.
mkdir -p "$checkouts/.moots/dev/posts"
a post --room dev --as alice -m 'shadowed' 2>"$work/err" >/dev/null; rc=$?
check 'post to a shadowing private room still succeeds' "$rc" '0'
check 'and the post is in the private room' "$(ls "$checkouts/app/.moot/rooms/dev/posts"/*.md | wc -l | tr -d ' ')" '1'
check 'and warns on stderr that a shared room exists' "$(grep -c "shared room of that name exists at $checkouts/.moots/dev" "$work/err")" '1'
check 'post to a room with no shared namesake says nothing' \
  "$(a join mine >/dev/null; a post --room mine --as alice -m x 2>&1 >/dev/null)" ''

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

# -N posts from before the change still read and catch up in order, once.
room=$(new_room)
posts="$room/.moot/rooms/board/posts"
printf '@bob first\n'  > "$posts/20260829-163412-alice.md"
printf '@bob second\n' > "$posts/20260829-163412-alice-2.md"
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
case $(TZ=UTC0 "$room/.moot/moot.sh" read | grep -m1 '──') in *'2026-08-28 23:59:59 +0000 · bob'*) ok 'the heading is built from the filename' ;; *) no 'the heading is built from the filename' ;; esac

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
printf 'arrived later\n' > "$room/.moot/rooms/board/posts/20260829-100000-alice.md"
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
printf 'see the patch @alice\n' > "$room/.moot/rooms/board/posts/20260829-164070-bob/post.md"
printf 'diff goes here\n' > "$room/.moot/rooms/board/posts/20260829-164070-bob/diff.patch"
printf 'a plain one\n' > "$room/.moot/rooms/board/posts/20260829-170000-alice.md"
out=$("$room/.moot/moot.sh" read)
case $out in *'see the patch @alice'*) ok 'an attachment post renders post.md' ;; *) no 'an attachment post renders post.md' ;; esac
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
named="$work/myApp"; mkdir -p "$named"
"$repo/install.sh" "$named" >/dev/null; "$named/.moot/moot.sh" join board >/dev/null
( cd "$work" && MOOT_NAME= USER=username "$named/.moot/moot.sh" post -m 'x' >/dev/null )
check 'the host folder name is the last resort, not $USER' "$(sender_of "$named")" 'myApp'
( cd / && env -u MOOT_NAME -u USER "$named/.moot/moot.sh" post -m 'y' >/dev/null )
check 'and needs no $USER at all' "$(ls "$named/.moot/rooms/board/posts" | grep -c 'myApp')" '2'

spaced="$work/My Project"; mkdir -p "$spaced"
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
"$room/.moot/moot.sh" post --as alice -m 'posted by tool' >/dev/null
check 'a tool-written post is readable by hand' "$(cat "$room"/.moot/rooms/board/posts/*-alice.md)" 'posted by tool'

# ---------------------------------------------------------------- catchup

group 'catchup'
room=$(new_room)
m() { "$room/.moot/moot.sh" "$@"; }
say() { printf '%s\n' "$2" > "$room/.moot/rooms/board/posts/$1.md"; }

say 20260829-100000-bob   'board is up'
say 20260829-100100-bob   'hey @alice can you look at the thing'
say 20260829-100200-bob   'unrelated announcement'
say 20260829-100300-bob   '@all standup moved'
say 20260829-100400-bob   'nice work @fanta'

out=$(m catchup --as alice)
check 'catchup delivers a direct mention' "$(printf '%s' "$out" | grep -c 'can you look at')" '1'
check 'catchup delivers @all'             "$(printf '%s' "$out" | grep -c 'standup moved')" '1'
check 'catchup skips an unmentioned post' "$(printf '%s' "$out" | grep -c 'unrelated')" '0'
check 'catchup skips someone else atted'  "$(printf '%s' "$out" | grep -c 'nice work')" '0'
check 'catchup writes the cursor' "$(cat "$room/.moot/seen/board/alice")" '20260829-100400-bob'

out=$(m catchup --as alice)
check 'a re-run delivers nothing'  "$(printf '%s' "$out" | grep -c 'can you look at')" '0'
check 'the cursor did not move back' "$(cat "$room/.moot/seen/board/alice")" '20260829-100400-bob'

say 20260829-100500-bob '@alice one more'
out=$(m catchup --as alice)
check 'catchup resumes from the cursor' "$(printf '%s' "$out" | grep -c 'one more')" '1'
check 'catchup does not re-deliver older mentions' "$(printf '%s' "$out" | grep -c 'can you look at')" '0'

check 'the whole board is still readable' "$(m read | grep -c 'unrelated announcement')" '1'
check 'catchup advanced past unmentioned posts' "$(cat "$room/.moot/seen/board/alice")" '20260829-100500-bob'

group 'mentions in code'
room=$(new_room)
say 20260829-100000-bob 'the flag waits for an `@alice` or `@all`'
printf 'example:\n\n```sh\nmoot.sh post -m "@all standup"\n```\n' > "$room/.moot/rooms/board/posts/20260829-100100-bob.md"
say 20260829-100200-bob 'use `watch --mentions`, @alice please try it'
say 20260829-100300-bob 'an unclosed ` @alice still counts'
out=$(m catchup --as alice)
check 'an @ in an inline code span is not a mention' "$(printf '%s' "$out" | grep -c 'the flag waits')" '0'
check 'an @ in a fenced block is not a mention' "$(printf '%s' "$out" | grep -c 'standup')" '0'
check 'an @ beside a code span still is' "$(printf '%s' "$out" | grep -c 'please try it')" '1'
check 'an unclosed backtick hides nothing' "$(printf '%s' "$out" | grep -c 'still counts')" '1'

group 'catchup and nobody'
room=$(new_room); m() { "$room/.moot/moot.sh" "$@"; }; say() { printf '%s\n' "$2" > "$room/.moot/rooms/board/posts/$1.md"; }
say 20260829-100000-bob 'hello @nobodyatall'
out=$(m catchup --as alice)
check 'a mention of nobody reaches nobody' "$(printf '%s' "$out" | grep -c 'hello')" '0'
check 'a mention of nobody still advances the cursor' "$(cat "$room/.moot/seen/board/alice")" '20260829-100000-bob'
check 'the mistyped mention is visible on the board' "$(m read | grep -c '@nobodyatall')" '1'

group 'mention matching'
room=$(new_room); m() { "$room/.moot/moot.sh" "$@"; }; say() { printf '%s\n' "$2" > "$room/.moot/rooms/board/posts/$1.md"; }
say 20260829-100000-bob 'thanks @alice.'
say 20260829-100100-bob 'ask @alice, please'
say 20260829-100200-bob 'not @alicelike'
say 20260829-100300-bob 'an email a@alice is not a mention of a'
out=$(m catchup --as alice)
check 'a trailing full stop still mentions'   "$(printf '%s' "$out" | grep -c 'thanks')" '1'
check 'a trailing comma still mentions'       "$(printf '%s' "$out" | grep -c 'please')" '1'
check 'a longer name is a different name'     "$(printf '%s' "$out" | grep -c 'not @alicelike')" '0'

group 'catchup --deliver'
room=$(new_room); m() { "$room/.moot/moot.sh" "$@"; }; say() { printf '%s\n' "$2" > "$room/.moot/rooms/board/posts/$1.md"; }
inbox="$work/inbox"; rm -rf "$inbox"
say 20260829-100000-bob 'quiet announcement'
say 20260829-100100-bob '@alice please handle the thing bob raised earlier'
m catchup --as alice --deliver "$inbox" >/dev/null
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

m catchup --as alice --deliver "$inbox" >/dev/null
check 'a re-run delivers nothing twice' "$(ls "$inbox" | wc -l | tr -d ' ')" '1'

# Moot does not know what a nest is: gremlin integration is a path.
rm -rf "$work/nest"; mkdir -p "$work/nest/in"
rm -f "$room/.moot/seen/board/alice"
m catchup --as alice --deliver "$work/nest/in" >/dev/null
check '--deliver takes any directory the caller names' "$(ls "$work/nest/in" | wc -l | tr -d ' ')" '1'

group 'catchup on a read-only moot'
room=$(new_room); m() { "$room/.moot/moot.sh" "$@"; }; say() { printf '%s\n' "$2" > "$room/.moot/rooms/board/posts/$1.md"; }
say 20260829-100000-bob '@alice the board is read-only from here'
inbox="$work/ro-inbox"; rm -rf "$inbox"; mkdir -p "$inbox"
chmod -w "$room/.moot/seen/board"
m catchup --as alice --deliver "$inbox" >/dev/null 2>"$work/ro.err"
check 'a read-only moot still delivers' "$(ls "$inbox" | wc -l | tr -d ' ')" '1'
check 'a read-only moot warns about the cursor' "$(grep -c 'read-only room' "$work/ro.err")" '1'
m catchup --as alice --deliver "$inbox" >/dev/null 2>&1
check 'a read-only moot still delivers nothing twice' "$(ls "$inbox" | wc -l | tr -d ' ')" '1'
chmod +w "$room/.moot/seen/board"

group 'catchup name resolution and --json'
room=$(new_room); m() { "$room/.moot/moot.sh" "$@"; }; say() { printf '%s\n' "$2" > "$room/.moot/rooms/board/posts/$1.md"; }
mkdir -p "$room/.gremlin"; printf 'name=fanta\n' > "$room/.gremlin/name"
say 20260829-100000-bob '@fanta over to you'
( cd "$room" && MOOT_NAME= USER=username "$room/.moot/moot.sh" catchup >/dev/null )
[ -f "$room/.moot/seen/board/fanta" ] && ok 'catchup uses the same name chain as post' || no 'catchup uses the same name chain as post'

room=$(new_room); m() { "$room/.moot/moot.sh" "$@"; }; say() { printf '%s\n' "$2" > "$room/.moot/rooms/board/posts/$1.md"; }
say 20260829-100000-bob '@alice hi'
out=$(m catchup --json --as alice)
case $out in *'"delivered":[{"room":"board","id":"20260829-100000-bob"}]'*) ok 'catchup --json names the room of what it delivered' ;; *) no 'catchup --json names the room of what it delivered' "$out" ;; esac
case $out in *'"since":null'*) ok 'catchup --json reports no prior cursor as null' ;; *) no 'catchup --json reports no prior cursor as null' "$out" ;; esac
case $out in *'"rooms":[{"room":"board"'*) ok 'catchup --json reports one entry per room swept' ;; *) no 'catchup --json reports one entry per room swept' "$out" ;; esac
out=$(m catchup --json --as alice)
case $out in *'"changed":false'*'"delivered":[]'*) ok 'catchup --json reports an unchanged re-run' ;; *) no 'catchup --json reports an unchanged re-run' "$out" ;; esac

group 'catchup sweeps every room'
host=$(new_host); j() { "$host/.moot/moot.sh" "$@"; }
for r in board release ops; do
  j join "$r" >/dev/null
  printf '@alice the %s thing\n' "$r" > "$host/.moot/rooms/$r/posts/20260829-100000-bob.md"
done
inbox="$work/sweep-inbox"; rm -rf "$inbox"
out=$(j catchup --as alice --deliver "$inbox")
check 'one call delivers from every room' "$(ls "$inbox" | wc -l | tr -d ' ')" '3'
check 'and says so on one line' "$(printf '%s' "$out" | wc -l | tr -d ' ')" '0'
check 'the sweep advances every cursor' "$(ls "$host/.moot/seen"/*/alice | wc -l | tr -d ' ')" '3'
j catchup --as alice --deliver "$inbox" >/dev/null
check 'a re-run of the sweep delivers nothing twice' "$(ls "$inbox" | wc -l | tr -d ' ')" '3'

# Two rooms can produce the same post id in the same second from the same
# sender. The filename is the whole duplicate-suppression mechanism.
host=$(new_host); j() { "$host/.moot/moot.sh" "$@"; }
j join board >/dev/null; j join release >/dev/null
printf '@alice same second, board\n' > "$host/.moot/rooms/board/posts/20260829-100000-bob.md"
printf '@alice same second, release\n' > "$host/.moot/rooms/release/posts/20260829-100000-bob.md"
inbox="$work/clash-inbox"; rm -rf "$inbox"
j catchup --as alice --deliver "$inbox" >/dev/null
check 'a same-second clash across rooms delivers both' "$(ls "$inbox" | wc -l | tr -d ' ')" '2'
check 'and neither body was lost' "$(cat "$inbox"/* | grep -c 'same second,')" '2'

group 'catchup --room narrows the sweep'
host=$(new_host); j() { "$host/.moot/moot.sh" "$@"; }
j join board >/dev/null; j join release >/dev/null
printf '@alice board\n' > "$host/.moot/rooms/board/posts/20260829-100000-bob.md"
printf '@alice release\n' > "$host/.moot/rooms/release/posts/20260829-100000-bob.md"
inbox="$work/narrow-inbox"; rm -rf "$inbox"
j catchup --as alice --room board --deliver "$inbox" >/dev/null
check '--room delivers from that room only' "$(ls "$inbox" | wc -l | tr -d ' ')" '1'
[ -f "$host/.moot/seen/board/alice" ] && ok '--room advances that cursor' || no '--room advances that cursor'
[ -e "$host/.moot/seen/release/alice" ] && no '--room leaves the other cursor alone' || ok '--room leaves the other cursor alone'
j catchup --as alice --room nosuch >/dev/null 2>&1 && no '--room on an unjoined room is an error' || ok '--room on an unjoined room is an error'

group 'a read-only room does not stop the sweep'
host=$(new_host); j() { "$host/.moot/moot.sh" "$@"; }
for r in aa bb cc; do
  j join "$r" >/dev/null
  printf '@alice the %s thing\n' "$r" > "$host/.moot/rooms/$r/posts/20260829-100000-bob.md"
done
chmod -w "$host/.moot/seen/bb"
inbox="$work/ro-sweep"; rm -rf "$inbox"
j catchup --as alice --deliver "$inbox" >/dev/null 2>"$work/ro-sweep.err"
check 'the read-only room still delivered' "$(ls "$inbox" | wc -l | tr -d ' ')" '3'
check 'and warned about its cursor' "$(grep -c 'read-only room' "$work/ro-sweep.err")" '1'
[ -f "$host/.moot/seen/cc/alice" ] && ok 'the room after it was still swept' || no 'the room after it was still swept'
chmod +w "$host/.moot/seen/bb"

group 'catchup with no rooms at all'
host=$(new_host)
"$host/.moot/moot.sh" catchup --as alice >/dev/null 2>&1 && ok 'a host with no rooms exits clean' || no 'a host with no rooms exits clean'
check 'and says nothing' "$("$host/.moot/moot.sh" catchup --as alice 2>&1 | wc -c | tr -d ' ')" '0'
out=$("$host/.moot/moot.sh" catchup --json --as alice)
case $out in *'"rooms":[]'*'"delivered":[]'*) ok 'and --json reports an empty sweep' ;; *) no 'and --json reports an empty sweep' "$out" ;; esac

group 'catchup on an empty board'
room=$(new_room)
"$room/.moot/moot.sh" catchup --as alice >/dev/null 2>&1 && ok 'catchup on an empty board succeeds' || no 'catchup on an empty board succeeds'
[ -e "$room/.moot/seen/board/alice" ] && no 'an empty board writes no cursor' || ok 'an empty board writes no cursor'

group 'catchup and attachments'
room=$(new_room); m() { "$room/.moot/moot.sh" "$@"; }
mkdir -p "$room/.moot/rooms/board/posts/20260829-100000-bob"
printf '@alice see the patch\n' > "$room/.moot/rooms/board/posts/20260829-100000-bob/post.md"
printf 'diff\n' > "$room/.moot/rooms/board/posts/20260829-100000-bob/diff.patch"
inbox="$work/att-inbox"; rm -rf "$inbox"
m catchup --as alice --deliver "$inbox" >/dev/null
check 'an attachment post is delivered' "$(ls "$inbox" | wc -l | tr -d ' ')" '1'
case $(cat "$inbox"/*) in *'diff.patch'*) ok 'a delivered attachment post points at its files' ;; *) no 'a delivered attachment post points at its files' ;; esac

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
check 'install is repeatable' "$(ls -A "$host/.moot" | wc -l | tr -d ' ')" '6'

# The tracked .moot/ ships its own .gitignore for this participant's state, and
# install copies it. The hint on stdout covers what a .gitignore cannot know:
# the linked rooms by name. Install writes no .gitignore in the host.
for line in /seen/ /name /room; do
  grep -qx "$line" "$host/.moot/.gitignore" && ok "the installed .moot/.gitignore ignores $line" || no "the installed .moot/.gitignore ignores $line"
done
# Anchored patterns: a real-directory room may be named seen, name or room.
gi=$(mktemp -d); git -C "$gi" init -q; mkdir -p "$gi/.moot/rooms/room/posts" "$gi/.moot/seen"
cp "$repo/.moot/.gitignore" "$gi/.moot/.gitignore"; : > "$gi/.moot/rooms/room/posts/x.md"; : > "$gi/.moot/name"
git -C "$gi" check-ignore -q .moot/rooms/room/posts/x.md && no 'a room named room is not ignored' || ok 'a room named room is not ignored'
git -C "$gi" check-ignore -q .moot/name && ok 'and .moot/name still is' || no 'and .moot/name still is'
rm -rf "${gi:?}"
hint=$("$repo/install.sh" "$host")
case $hint in *"  rooms/<name>"*) ok 'install hints at ignoring a linked room by name' ;; *) no 'install hints at ignoring a linked room by name' ;; esac
# One rule on rooms: a real directory may be committed, so rooms/ is not ignored
# wholesale, in the shipped file or in the hint.
grep -qE '^/?rooms/?\*?$' "$host/.moot/.gitignore" && no 'the shipped .gitignore does not ignore all of rooms/' || ok 'the shipped .gitignore does not ignore all of rooms/'
case $hint in *"  .moot/rooms/"$'\n'*) no 'install does not hint at ignoring all of rooms/' ;; *) ok 'install does not hint at ignoring all of rooms/' ;; esac
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
check 'a bare copy lists no rooms' "$("$plain/.moot/moot.sh" rooms)" "no rooms here yet: $plain/.moot/moot.sh join <room>"
"$plain/.moot/moot.sh" catchup --as alice >/dev/null && ok 'catchup works before any room' || no 'catchup works before any room'
"$plain/.moot/moot.sh" join board >/dev/null && ok 'a bare copy joins a room with no init' || no 'a bare copy joins a room with no init'
"$plain/.moot/moot.sh" post --as alice -m 'hello' >/dev/null && ok 'a bare copy posts' || no 'a bare copy posts'
out=$("$plain/.moot/moot.sh" read)
case $out in *hello*) ok 'a bare copy reads the post back' ;; *) no 'a bare copy reads the post back' "$out" ;; esac
# catchup leaves the current second for the next sweep, so give it an older post.
printf '@bob hello\n' > "$plain/.moot/rooms/board/posts/20260829-090000-alice.md"
"$plain/.moot/moot.sh" catchup --as bob >/dev/null && ok 'a bare copy catches up' || no 'a bare copy catches up'
[ -f "$plain/.moot/seen/board/bob" ] && ok 'and keeps the cursor in its own seen/' || no 'and keeps the cursor in its own seen/'
check 'the copy touches nothing outside .moot/' "$(ls -A "$plain")" '.moot'
# The tracked .moot/ carries no instance state: nothing git tracks there is
# per-participant.
if git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
  tracked=$(git -C "$repo" ls-files .moot | grep -E '^\.moot/(seen|rooms)/|^\.moot/(name|room)$' || true)
  check 'the repo tracks no instance state in .moot/' "$tracked" ''
fi

# Each participant keeps a copy of the room, and their state inside it. The
# folder that syncs is posts/, and nothing in it is written by two hands.
group 'two participants'
room=$(new_room); m() { "$room/.moot/moot.sh" "$@"; }
printf '@alice morning\n' > "$room/.moot/rooms/board/posts/20260829-090000-bob.md"
twin="$work/twin"; rm -rf "$twin"; cp -r "$room" "$twin"
m catchup --as bob >/dev/null
"$twin/.moot/moot.sh" catchup --as alice >/dev/null
[ -e "$room/.moot/seen/board/alice" ] && no 'a cursor never travels to the other copy' || ok 'a cursor never travels to the other copy'
[ -e "$twin/.moot/seen/board/bob" ] && no 'the other copy holds only its own cursor' || ok 'the other copy holds only its own cursor'
"$twin/.moot/moot.sh" post --as alice -m 'on it' >/dev/null
before=$(cat "$room/.moot/seen/board/bob")
check 'the first catchup did write a cursor to compare against' "$before" '20260829-090000-bob'
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
for r in myApp carol; do
  mkdir -p "$parent/$r"
  "$repo/install.sh" "$parent/$r" >/dev/null
  ln -s "$parent/.moot/rooms/dev" "$parent/$r/.moot/rooms/dev"
done
b() { ( cd "$work" && MOOT_NAME= "$parent/myApp/.moot/moot.sh" "$@" ); }
e() { ( cd "$work" && MOOT_NAME= "$parent/carol/.moot/moot.sh" "$@" ); }
h() { ( cd "$work" && MOOT_NAME= "$parent/.moot/moot.sh" "$@" ); }

check 'a linked room is a room' "$(b rooms | grep -c dev)" '1'
step_date 20260829-100000 20260829-100000 20260829-100000
b post -m '@carol dispatching two workers' >/dev/null
e post -m '@myApp ok, holding mine' >/dev/null
h post -m '@all usage is fine' >/dev/null
thaw_step
check 'three repos posting in one second get three ids' \
  "$(ls "$parent/.moot/rooms/dev/posts" | tr '\n' ' ')" \
  '20260829-100000-bob.md 20260829-100000-carol.md 20260829-100000-myApp.md '

out_e=$(e catchup --json)
check 'each repo catches up under its folder name' "$(printf '%s' "$out_e" | grep -o '"sender":"[^"]*"')" '"sender":"carol"'
check 'and gets what mentions it' "$(printf '%s' "$out_e" | grep -o '"delivered":[0-9]*' | head -n 1)" '"delivered":2'
[ -f "$parent/carol/.moot/seen/dev/carol" ] && ok 'the cursor lives in the reading repo' || no 'the cursor lives in the reading repo'
[ ! -e "$parent/.moot/seen/dev/carol" ] && ok 'and never in the room holder' || no 'and never in the room holder'
[ ! -e "$parent/.moot/rooms/dev/seen" ] && [ "$(ls -A "$parent/.moot/rooms/dev")" = posts ] \
  && ok 'the shared room holds posts/ and nothing else' || no 'the shared room holds posts/ and nothing else'
check "one repo's catchup leaves another's cursor alone" "$(ls -A "$parent/myApp/.moot/seen/dev" 2>/dev/null | wc -l | tr -d ' ')" '0'
out_b=$(b catchup --json)
check 'the other repo still gets its own mentions' "$(printf '%s' "$out_b" | grep -o '"delivered":[0-9]*' | head -n 1)" '"delivered":2'
check 'and a second sweep delivers nothing twice' "$(b catchup --json | grep -o '"delivered":[0-9]*' | head -n 1)" '"delivered":0'

group 'a sweep leaves the current second for the next'
# A post can land in the second a sweep reads, under a name that sorts below the
# cursor's (bob after carol). If the cursor moved onto that second, the late
# post would be skipped for good. The stubbed clock stands at the second
# being swept; a sweep leaves that second alone.
room=$(new_room); m() { "$room/.moot/moot.sh" "$@"; }; say() { printf '%s\n' "$2" > "$room/.moot/rooms/board/posts/$1.md"; }
say 20260829-095959-carol 'settled earlier'
say 20260829-100000-carol '@alice same second, sorts last'
freeze_date 20260829-100000
out=$(m catchup --json --as alice)
check 'catchup scans only what is settled' "$(printf '%s' "$out" | grep -o '"scanned":[0-9]*')" '"scanned":1'
check 'and parks the cursor on the last settled post' "$(cat "$room/.moot/seen/board/alice")" '20260829-095959-carol'
check 'and reports that cursor' "$(printf '%s' "$out" | grep -o '"cursor":"[^"]*"')" '"cursor":"20260829-095959-carol"'
say 20260829-100000-bob '@alice same second, sorts first'
thaw_date; freeze_date 20260829-100001
out=$(m catchup --json --as alice)
check 'the next sweep delivers both same-second posts' "$(printf '%s' "$out" | grep -o '"delivered":\[[^]]*\]')" \
  '"delivered":[{"room":"board","id":"20260829-100000-bob"},{"room":"board","id":"20260829-100000-carol"}]'
check 'and moves the cursor onto them' "$(cat "$room/.moot/seen/board/alice")" '20260829-100000-carol'
check 'and a third sweep finds nothing' "$(m catchup --json --as alice | grep -o '"scanned":[0-9]*')" '"scanned":0'
thaw_date

room=$(new_room); m() { "$room/.moot/moot.sh" "$@"; }; say() { printf '%s\n' "$2" > "$room/.moot/rooms/board/posts/$1.md"; }
say 20260829-100000-carol 'first, same second'
freeze_date 20260829-100000
check 'read --new shows nothing from the current second' "$(m read --new --as alice)" 'nothing new for alice'
[ -e "$room/.moot/seen/board/alice" ] && no 'and writes no cursor' || ok 'and writes no cursor'
say 20260829-100000-bob 'second, sorts first'
thaw_date; freeze_date 20260829-100001
out=$(m read --new --as alice)
check 'the next read --new shows both' "$(printf '%s' "$out" | grep -c -e 'first, same second' -e 'second, sorts first')" '2'
check 'in post-id order' "$(printf '%s' "$out" | grep -e 'first, same' -e 'second, sorts' | tr '\n' '|')" 'second, sorts first|first, same second|'
check 'and the heading counts them' "$(printf '%s' "$out" | grep -c '══ board · 2 new ══')" '1'
thaw_date

# Each sweep reads the clock once, so a sweep that finds everything settled
# terminates with the usual report; stamps from a clock ahead of mine wait too.
room=$(new_room); m() { "$room/.moot/moot.sh" "$@"; }; say() { printf '%s\n' "$2" > "$room/.moot/rooms/board/posts/$1.md"; }
say 20260829-100000-bob 'now'
say 20260829-100500-bob 'five minutes ahead of my clock'
freeze_date 20260829-100000
check 'a post stamped later than my clock is not swept yet' "$(m catchup --json --as alice | grep -o '"scanned":[0-9]*')" '"scanned":0'
thaw_date
out=$(m catchup --json --as alice)
check 'and is swept once the clock has passed it' "$(printf '%s' "$out" | grep -o '"scanned":[0-9]*')" '"scanned":2'
# A stray file that is not a stamp never moves the cursor (it would sort after
# every stamp, and park the cursor beyond every later post).
say README 'not a post'
say 20260829-100600-bob 'real post'
out=$(m read --new --as alice)
check 'a non-stamp file is not swept' "$(printf '%s' "$out" | grep -c 'not a post')" '0'
check 'and does not hide the post after it' "$(printf '%s' "$out" | grep -c 'real post')" '1'
check 'because the cursor stays on the last stamp' "$(cat "$room/.moot/seen/board/alice")" '20260829-100600-bob'

# read --new through a linked room: each repo's cursor stays in its own seen/.
rp_dev() { printf '%s\n' "$2" > "$parent/.moot/rooms/dev/posts/$1.md"; }
rp_dev 20260829-110000-bob '@all a late note'
out=$(b read --new)
check 'read --new reads a linked room' "$(printf '%s' "$out" | grep -c 'a late note')" '1'
[ -f "$parent/myApp/.moot/seen/dev/myApp" ] && ok 'and its cursor is in the reading repo' || no 'and its cursor is in the reading repo'
[ ! -e "$parent/.moot/seen/dev/myApp" ] && ok 'and not in the room holder' || no 'and not in the room holder'
check "so another repo's --new still shows the post" "$(e read --new | grep -c 'a late note')" '1'
check 'and a second --new in the first repo shows nothing' "$(b read --new)" 'nothing new for myApp'

# A room link whose relative target leads back to itself loops. join says so.
loop=$(new_host)
ln -s ../../.moot/rooms/dev "$loop/.moot/rooms/dev"
err=$("$loop/.moot/moot.sh" join dev 2>&1 >/dev/null); rc=$?
[ "$rc" -ne 0 ] && ok 'join on a looping room link fails' || no 'join on a looping room link fails'
check 'and names the link, not mkdir' "$(printf '%s' "$err" | grep -c 'rooms/dev is a link that does not lead to a folder')" '1'
check 'and does not say "Too many levels"' "$(printf '%s' "$err" | grep -c 'Too many levels')" '0'
dangling=$(new_host)
ln -s "$work/nowhere-at-all" "$dangling/.moot/rooms/dev"
"$dangling/.moot/moot.sh" join dev >/dev/null 2>&1 && no 'join on a dangling room link fails' || ok 'join on a dangling room link fails'

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
mkdir -p "$parent/bob"
"$repo/install.sh" "$parent/bob" >/dev/null
m() { ( cd "$work" && MOOT_NAME= TZ=XXX-11 "$parent/bob/.moot/moot.sh" "$@" ); }
m join runs >/dev/null; m join dev >/dev/null
rp() { printf '%s\n' "$2" > "$parent/bob/.moot/rooms/$1/posts/$3.md"; }
rp runs 'run one done' 20260829-100000-alice
rp runs '@bob please look' 20260829-110000-alice
rp dev  'dev note' 20260829-103000-carol

out=$(m read --new)
check 'read --new with several rooms and no --room needs no choice' "$(printf '%s' "$out" | grep -c 'run one done')" '1'
check 'it shows every post, not just mentions' "$(printf '%s' "$out" | grep -c -e 'run one done' -e 'dev note' -e 'please look')" '3'
check 'each room gets a heading with its count' "$(printf '%s' "$out" | grep -c -e '══ dev · 1 new ══' -e '══ runs · 2 new ══')" '2'
check 'rooms stay separate: dev comes before runs, not interleaved by time' \
  "$(printf '%s' "$out" | grep -e 'dev note' -e 'run one' -e 'please look' | tr '\n' '|')" 'dev note|run one done|@bob please look|'
case $out in *'2026-08-29 21:00:00 +1100 · alice'*) ok 'headings are in local time' ;; *) no 'headings are in local time' ;; esac
check 'the cursors moved to the newest post in each room' \
  "$(cat "$parent/bob/.moot/seen/runs/bob") $(cat "$parent/bob/.moot/seen/dev/bob")" \
  '20260829-110000-alice 20260829-103000-carol'
check 'a second call shows nothing new' "$(m read --new)" 'nothing new for bob'

rp runs 'run two done' 20260829-120000-alice
out=$(m read --new)
check 'a later call shows only what arrived since' "$(printf '%s' "$out" | grep -c -e 'run two done' -e 'run one done' -e 'dev note')" '1'
check 'and only the room that changed gets a heading' "$(printf '%s' "$out" | grep -c '══')" '1'

# Plain read never touches the cursor.
rp runs 'run three done' 20260829-130000-alice
m read --room runs >/dev/null
check 'plain read leaves the cursor alone' "$(cat "$parent/bob/.moot/seen/runs/bob")" '20260829-120000-alice'
check 'so --new still shows what read showed' "$(m read --new | grep -c 'run three done')" '1'

# --room narrows; the other room's cursor stays put.
rp runs 'run four done' 20260829-140000-alice
rp dev  'dev two' 20260829-141000-carol
out=$(m read --new --room dev)
check '--new --room shows that room only' "$(printf '%s' "$out" | grep -c -e 'dev two' -e 'run four')" '1'
check "and leaves the other room's cursor" "$(cat "$parent/bob/.moot/seen/runs/bob")" '20260829-130000-alice'

# The cursor is shared with catchup, in both directions.
check 'catchup starts from the cursor --new left: it scans only what --new did not show' \
  "$(m catchup --json | grep -o '"scanned":[0-9]*' | tr '\n' ' ')" '"scanned":0 "scanned":1 '
rp runs '@bob after catchup' 20260829-150000-alice
rp runs 'plain after catchup' 20260829-151000-alice
m catchup >/dev/null
check 'catchup moves the cursor --new reads' "$(cat "$parent/bob/.moot/seen/runs/bob")" '20260829-151000-alice'
check 'so --new shows nothing catchup already passed' "$(m read --new)" 'nothing new for bob'
rp runs '@bob before new' 20260829-160000-alice
m read --new >/dev/null
check "and --new moves the cursor catchup reads: it finds nothing" "$(m catchup --json | grep -o '"delivered":[0-9]*' | head -n 1)" '"delivered":0'

# Names: --as picks the cursor; another name has its own.
check 'another name starts from the top' "$(m read --new --as alice | grep -c '══')" '2'
check 'and keeps its own cursor' "$(m read --new --as alice)" 'nothing new for alice'

# Options that fight the cursor are refused, not ignored.
for opt in '--since x' '--tail 1' '--follow'; do
  # shellcheck disable=SC2086
  m read --new $opt >/dev/null 2>&1; rc=$?
  [ "$rc" -ne 0 ] && ok "--new refuses $opt" || no "--new refuses $opt"
done
m read --room runs --as bob >/dev/null 2>&1 && no '--as without --new is refused' || ok '--as without --new is refused'
m read --new --room nonesuch >/dev/null 2>&1 && no '--new --room of an unknown room fails' || ok '--new --room of an unknown room fails'

# A room that cannot take a cursor still reads, and says so.
ro=$(new_room)
printf 'hello\n' > "$ro/.moot/rooms/board/posts/20260829-100000-alice.md"
chmod a-w "$ro/.moot/seen/board" 2>/dev/null
if [ -w "$ro/.moot/seen/board" ]; then
  ok '(skipped: running as a user who can write anywhere)'
else
  err=$("$ro/.moot/moot.sh" read --new --as bob 2>&1 >/dev/null)
  check 'a read-only cursor still shows the post' "$("$ro/.moot/moot.sh" read --new --as bob 2>/dev/null | grep -c hello)" '1'
  check 'and warns that it will show again' "$(printf '%s' "$err" | grep -c 'read-only room')" '1'
fi
chmod u+w "$ro/.moot/seen/board" 2>/dev/null

# No rooms at all is not an error.
bare=$(new_host)
check 'read --new with no rooms says nothing new and succeeds' "$("$bare/.moot/moot.sh" read --new --as bob)" 'nothing new for bob'

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
start_watch "$room/.moot/moot.sh" watch --as bob
check 'watch does not fire on history' "$(kill -0 "$watch_pid" 2>/dev/null && echo waiting)" 'waiting'
[ -e "$room/.moot/watching" ] && ok 'watch holds .moot/watching' || no 'watch holds .moot/watching'
check 'watching names the watcher' "$(sed -n 's/^name=//p' "$room/.moot/watching")" 'bob'
printf 'mine\n' > "$(posts_of "$room")/20260829-091000-bob.md"
sleep 0.6
check 'watch ignores my own post' "$(kill -0 "$watch_pid" 2>/dev/null && echo waiting)" 'waiting'
printf 'new\n' > "$(posts_of "$room")/20260829-092000-alice.md"
wait_watch
check 'watch exits 0 on a new post' "$rc" '0'
check 'watch prints room/id' "$(cat "$work/watch.out")" 'board/20260829-092000-alice'
[ ! -e "$room/.moot/watching" ] && ok 'watch releases .moot/watching on exit' || no 'watch releases .moot/watching on exit'
[ ! -e "$room/.moot/seen/board/bob" ] && ok 'watch never writes the cursor' || no 'watch never writes the cursor'

group 'watch from the cursor'
room=$(new_room)
printf 'a\n' > "$(posts_of "$room")/20260829-090000-alice.md"
"$room/.moot/moot.sh" catchup --as bob >/dev/null
printf 'b\n' > "$(posts_of "$room")/20260829-093000-alice.md"
start_watch "$room/.moot/moot.sh" watch --as bob
wait_watch
check 'a post since the cursor fires at once' "$rc:$(cat "$work/watch.out")" '0:board/20260829-093000-alice'
check 'and the cursor stays where catchup put it' "$(cat "$room/.moot/seen/board/bob")" '20260829-090000-alice'

group 'watch --mentions'
room=$(new_room)
start_watch "$room/.moot/moot.sh" watch --as bob --mentions --json
printf 'just news\n' > "$(posts_of "$room")/20260829-090000-alice.md"
sleep 0.6
check '--mentions ignores a post without @bob' "$(kill -0 "$watch_pid" 2>/dev/null && echo waiting)" 'waiting'
printf 'see `@bob`\n' > "$(posts_of "$room")/20260829-090050-alice.md"
sleep 0.6
check '--mentions ignores an @ in code' "$(kill -0 "$watch_pid" 2>/dev/null && echo waiting)" 'waiting'
printf '@bob please look\n' > "$(posts_of "$room")/20260829-090100-alice.md"
wait_watch
check '--mentions fires on @bob' "$rc" '0'
check '--json names room and post' "$(cat "$work/watch.out")" \
  '{"schema_version":2,"command":"watch","ok":true,"sender":"bob","posts":[{"room":"board","id":"20260829-090100-alice"}]}'

group 'watch paused'
room=$(new_room)
touch "$room/.moot/watch.paused"
start_watch "$room/.moot/moot.sh" watch --as bob
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
start_watch "$room/.moot/moot.sh" watch --as bob
first=$watch_pid
MOOT_WATCH_INTERVAL=0.2 "$room/.moot/moot.sh" watch --as bob >/dev/null 2>"$work/err2"; rc=$?
check 'a second watch is refused with exit 3' "$rc" '3'
check 'and says who holds it' "$(grep -c "pid $first" "$work/err2")" '1'
check 'the refusal leaves the first watch its file' "$(sed -n 's/^pid=//p' "$room/.moot/watching")" "$first"
kill "$first" 2>/dev/null; wait "$first" 2>/dev/null
[ ! -e "$room/.moot/watching" ] && ok 'a killed watch releases its file' || no 'a killed watch releases its file'
printf 'pid=999999\nname=bob\n' > "$room/.moot/watching"
start_watch "$room/.moot/moot.sh" watch --as bob
check 'a stale watching file is taken over' "$(sed -n 's/^pid=//p' "$room/.moot/watching")" "$watch_pid"
kill "$watch_pid" 2>/dev/null; wait "$watch_pid" 2>/dev/null

group 'install beside a running watch'
room=$(new_room)
start_watch "$room/.moot/moot.sh" watch --as bob
before=$(ls -i "$room/.moot/moot.sh" | awk '{print $1}')
"$repo/install.sh" "$room" >/dev/null
after=$(ls -i "$room/.moot/moot.sh" | awk '{print $1}')
[ "$before" != "$after" ] && ok 'install renames moot.sh into place, not over the running file' \
  || no 'install renames moot.sh into place, not over the running file'
check 'install leaves no temporary file' "$(ls -A "$room/.moot" | grep -c installing)" '0'
printf 'after install\n' > "$(posts_of "$room")/20260829-090000-alice.md"
wait_watch
check 'the running watch still fires after an install' "$rc:$(cat "$work/watch.out")" '0:board/20260829-090000-alice'

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
