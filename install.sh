#!/usr/bin/env bash
#
# Install moot into a directory, making it a moot participant.
#
#   ./install.sh /path/to/dir
#
# Copies moot.sh, README.md and the skill (skills/moot.md, installed as
# SKILL.md) into <dir>/.moot/, then runs init. Everything moot needs lives
# under .moot/ — the rooms it holds and this participant's read state — so
# .moot/ sits beside .loom/ and .gremlin/ and claims nothing of the directory
# it is in. Re-running refreshes all three files.
#
# The skill ships in every .moot/ so that a repo with a .moot/ knows how to use
# it, and no other repo needs to.
#
# This creates no room: init no longer knows which one. Join a room after
# installing:
#
#   <dir>/.moot/moot.sh join board
#
# It writes no .gitignore (moot writes none). It prints the lines a git repo
# wants, as a hint, and the repo decides.

set -euo pipefail

# Where this script really lives, so a symlink to it (~/bin/moot-install, say)
# still finds moot.sh, README.md and skills/ beside the real file. A relative
# link target is relative to the folder holding the link.
src=${BASH_SOURCE[0]}
while [ -L "$src" ]; do
  link_dir=$(cd -P -- "$(dirname -- "$src")" && pwd)
  src=$(readlink -- "$src")
  case $src in /*) ;; *) src=$link_dir/$src ;; esac
done
source_dir=$(cd -P -- "$(dirname -- "$src")" && pwd)
host=${1:-$PWD}

[ -d "$host" ] || { printf 'install: no such directory: %s\n' "$host" >&2; exit 1; }
host=$(cd -- "$host" && pwd)

# Look before making anything: a missing source file used to fail at cp and
# leave an empty .moot/ behind.
for f in moot.sh README.md skills/moot.md; do
  [ -r "$source_dir/$f" ] || { printf 'install: cannot find %s beside install.sh (looked in %s)\n' "$f" "$source_dir" >&2; exit 1; }
done

mkdir -p -- "$host/.moot"
cp -- "$source_dir/moot.sh" "$host/.moot/moot.sh"
cp -- "$source_dir/README.md" "$host/.moot/README.md"
cp -- "$source_dir/skills/moot.md" "$host/.moot/SKILL.md"
chmod +x "$host/.moot/moot.sh"

"$host/.moot/moot.sh" init >/dev/null
printf 'installed moot into %s/.moot\n' "$host"
printf 'join a room with: %s/.moot/moot.sh join <room>\n' "$host"
printf 'if that is a git repo, add these to its .gitignore (they are one participant'"'"'s state):\n'
printf '  .moot/seen/\n  .moot/name\n  .moot/room\n'
printf 'a room that is a real directory may be committed; a room that is a symlink is this\n'
printf "machine's, so ignore it by name, with no trailing slash:\n"
printf '  .moot/rooms/<name>\n'
