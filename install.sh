#!/usr/bin/env bash
#
# Install moot into a directory, making it a moot participant.
#
#   ./install.sh /path/to/dir
#
# Copies moot.sh and README.md into <dir>/.moot/, then runs init. Everything
# moot needs lives under .moot/ — the rooms it holds and this participant's
# read state — so .moot/ sits beside .loom/ and .gremlin/ and claims nothing
# of the directory it is in.
#
# This creates no room: init no longer knows which one. Join a room after
# installing:
#
#   <dir>/.moot/moot.sh join board

set -euo pipefail

source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
host=${1:-$PWD}

[ -d "$host" ] || { printf 'install: no such directory: %s\n' "$host" >&2; exit 1; }
host=$(cd -- "$host" && pwd)

mkdir -p -- "$host/.moot"
cp -- "$source_dir/moot.sh" "$host/.moot/moot.sh"
cp -- "$source_dir/README.md" "$host/.moot/README.md"
chmod +x "$host/.moot/moot.sh"

"$host/.moot/moot.sh" init >/dev/null
printf 'installed moot into %s/.moot\n' "$host"
printf 'join a room with: %s/.moot/moot.sh join <room>\n' "$host"
