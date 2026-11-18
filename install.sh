#!/usr/bin/env bash
#
# Install moot into a directory, making it a moot participant.
#
#   ./install.sh /path/to/dir
#
# Copies what this repo's .moot/ ships (moot.sh, README.md, SKILL.md and
# .gitignore) into <dir>/.moot/, then runs init. Everything moot needs lives
# under .moot/ — the rooms it holds and this participant's read state — so
# .moot/ sits beside .loom/ and .gremlin/ and claims nothing of the directory
# it is in. Re-running refreshes all four files.
#
# Copying the repo's .moot/ by hand does the same job without this script.
#
# The skill ships in every .moot/ so that a repo with a .moot/ knows how to use
# it, and no other repo needs to.
#
# This creates no room: init no longer knows which one. Join a room after
# installing:
#
#   <dir>/.moot/moot.sh join board
#
# The .gitignore it installs is .moot/.gitignore, which ignores this
# participant's seen/, name and room and never touches the host's own. It
# prints the line a git repo wants for each linked room, as a hint.

set -euo pipefail

# Where this script really lives, so a symlink to it (~/bin/moot-install, say)
# still finds .moot/ beside the real file. A relative
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
for f in .moot/moot.sh .moot/SKILL.md .moot/.gitignore .moot/README.md; do
  [ -r "$source_dir/$f" ] || { printf 'install: cannot find %s beside install.sh (looked in %s)\n' "$f" "$source_dir" >&2; exit 1; }
done

mkdir -p -- "$host/.moot"
cp -- "$source_dir/.moot/moot.sh" "$host/.moot/moot.sh"
cp -- "$source_dir/.moot/README.md" "$host/.moot/README.md"
cp -- "$source_dir/.moot/SKILL.md" "$host/.moot/SKILL.md"
cp -- "$source_dir/.moot/.gitignore" "$host/.moot/.gitignore"
chmod +x "$host/.moot/moot.sh"

"$host/.moot/moot.sh" init >/dev/null
printf 'installed moot into %s/.moot\n' "$host"
printf 'join a room with: %s/.moot/moot.sh join <room>\n' "$host"
printf "a linked room is this machine's, so a git repo ignores it by name, with no\n"
printf 'trailing slash (.moot/.gitignore already ignores seen/, name and room):\n'
printf '  .moot/rooms/<name>\n'
printf 'a room that is a real directory may be committed.\n'
