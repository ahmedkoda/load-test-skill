#!/usr/bin/env bash
# install.sh — copy the load-test skill into a Claude Code skills directory.
# Usage:
#   ./install.sh                       # installs to ~/.claude/skills (personal, all projects)
#   ./install.sh /path/.claude/skills  # installs into a specific directory (e.g. a project)
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)/load-test"
DEST="${1:-$HOME/.claude/skills}"

[ -d "$SRC" ] || { echo "ERROR: skill source not found at $SRC" >&2; exit 1; }
mkdir -p "$DEST"
cp -R "$SRC" "$DEST/"
chmod +x "$DEST/load-test/scripts/run_load.sh" 2>/dev/null || true

echo "✅ Installed 'load-test' to $DEST/load-test"
echo "   Re-open Claude Code, then invoke it with /load-test"
