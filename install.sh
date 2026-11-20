#!/usr/bin/env bash
#
# Upgrade moot in a directory (or make it a moot participant if it is not one).
#
#   ./install.sh /path/to/dir
#
# To install, copy this repo's .moot/ into the directory; this script is the
# upgrade path. It refreshes what .moot/ ships (moot.sh, README.md and
# SKILL.md) in <dir>/.moot/, seeds a missing .gitignore, and never touches what
# the host owns: rooms/, seen/, name and an existing .moot/.gitignore. Re-running
# changes nothing. Everything moot needs lives under .moot/, so .moot/ sits
# beside .loom/ and .gremlin/ and claims nothing of the directory it is in.
#
# The skill ships in every .moot/ so that a repo with a .moot/ knows how to use
# it, and no other repo needs to.
#
# This creates no room. Keep one with mkdir -p .moot/rooms/<room>/posts, or hear
# one someone else keeps with .moot/moot.sh join <path-to-room>.

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
# Copy beside and rename over, never write in place: bash reads a script as it
# runs it, so a moot.sh watch still running would go on reading the new bytes
# at its old offset. A rename leaves the running copy its own file.
for f in moot.sh README.md SKILL.md; do
  [ "$source_dir/.moot/$f" -ef "$host/.moot/$f" ] && continue
  cp -- "$source_dir/.moot/$f" "$host/.moot/.$f.installing"
  [ "$f" = moot.sh ] && chmod +x "$host/.moot/.$f.installing"
  mv -f -- "$host/.moot/.$f.installing" "$host/.moot/$f"
done
chmod +x "$host/.moot/moot.sh"
# .gitignore is the host's once it exists: leave it alone.
[ -e "$host/.moot/.gitignore" ] ||
  cp -- "$source_dir/.moot/.gitignore" "$host/.moot/.gitignore"

printf 'installed moot into %s/.moot\n' "$host"
printf 'keep a room: mkdir -p %s/.moot/rooms/<room>/posts\n' "$host"
printf 'hear a room someone keeps: %s/.moot/moot.sh join <path-to-room>\n' "$host"
