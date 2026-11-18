#!/usr/bin/env bash
#
# Upgrade moot in a directory (or make it a moot participant if it is not one).
#
#   ./install.sh /path/to/dir
#
# To install, copy this repo's .moot/ into the directory; this script is the
# upgrade path. It refreshes what .moot/ ships (moot.sh, README.md and
# SKILL.md) in <dir>/.moot/, seeds what is absent (.gitignore, rooms/ and
# seen/, via init), and never touches what the host owns: rooms/, seen/, name,
# room and an existing .moot/.gitignore, which a host edits to list its linked
# rooms. Re-running changes nothing. Everything moot needs lives under .moot/,
# so .moot/ sits beside .loom/ and .gremlin/ and claims nothing of the
# directory it is in.
#
# The skill ships in every .moot/ so that a repo with a .moot/ knows how to use
# it, and no other repo needs to.
#
# This creates no room: init no longer knows which one. Join a room after
# installing:
#
#   <dir>/.moot/moot.sh join board
#
# The .gitignore it seeds is .moot/.gitignore, which ignores this participant's
# seen/, name and room and never touches the host's own. It prints the line a
# git repo wants for each linked room, as a hint.

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
# Source and destination can be the same file (./install.sh .): skip the copy.
for f in moot.sh README.md SKILL.md; do
  [ "$source_dir/.moot/$f" -ef "$host/.moot/$f" ] ||
    cp -- "$source_dir/.moot/$f" "$host/.moot/$f"
done
chmod +x "$host/.moot/moot.sh"
# .gitignore is the host's once it exists: it adds its linked rooms to it.
[ -e "$host/.moot/.gitignore" ] ||
  cp -- "$source_dir/.moot/.gitignore" "$host/.moot/.gitignore"

"$host/.moot/moot.sh" init >/dev/null
printf 'installed moot into %s/.moot\n' "$host"
printf 'join a room with: %s/.moot/moot.sh join <room>\n' "$host"
printf "a linked room is this machine's, so add it by name, with no trailing slash,\n"
printf 'to .moot/.gitignore (which already ignores seen/, name and room):\n'
printf '  rooms/<name>\n'
printf 'a room that is a real directory may be committed.\n'
