#!/usr/bin/env bash
#
# Install moot into a directory, making you a participant in it.
#
#   ./install.sh /path/to/room
#
# Copies moot.sh and README.md into <room>/.moot/, then runs init. The room is
# the folder itself and holds only posts/; .moot/ is this participant's own
# state, and the deployed moot.sh operates on the .moot/ it lives in.
#
# Into an empty folder this creates the room, because init creates posts/.

set -euo pipefail

source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
room=${1:-$PWD}

[ -d "$room" ] || { printf 'install: no such directory: %s\n' "$room" >&2; exit 1; }
room=$(cd -- "$room" && pwd)

mkdir -p -- "$room/.moot"
cp -- "$source_dir/moot.sh" "$room/.moot/moot.sh"
cp -- "$source_dir/README.md" "$room/.moot/README.md"
chmod +x "$room/.moot/moot.sh"

"$room/.moot/moot.sh" init
printf 'installed moot into %s/.moot\n' "$room"
