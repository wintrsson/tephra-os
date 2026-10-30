#!/bin/bash
# Parse-checks every GDScript file in the shell with headless Godot, the way Tephra loads them.
# Works on a temporary copy so Godot's generated .uid/.import files never land in the repo.
# Usage: tools/check.sh   (uses $GODOT, else `godot` on PATH). Exit 1 if any script fails to compile.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-$(command -v godot || true)}"
if [ -z "$GODOT" ]; then
  echo "check: Godot not found (set GODOT or put godot on PATH)" >&2
  exit 2
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp -r "$ROOT/shell/tephra-shell" "$WORK/"

OUT="$(timeout 300 "$GODOT" --headless --path "$WORK/tephra-shell" --import 2>&1)"
ERRORS="$(printf '%s\n' "$OUT" | grep -E 'SCRIPT ERROR|Failed to load script' -A1)"
if [ -n "$ERRORS" ]; then
  printf '%s\n' "$ERRORS"
  echo "check: FAILED" >&2
  exit 1
fi
echo "check: all scripts compile"
