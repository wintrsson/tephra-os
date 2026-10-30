#!/bin/bash
# Runs the real Tephra under a virtual screen (Xvfb, software rendering) on a fresh, empty data folder, follows a plan of
# key presses and screenshots (see ui_shot.gd), and prints the settings file it ended with. Look at the PNGs afterwards.
# Usage: tools/ui-test.sh <plan.json> <output dir>        (uses $GODOT, else `godot` on PATH)
#   PRESEED='{"setup_done":true}'  puts that settings.json in place first (a PC that already has Tephra)
#   HOMESEED=dir                   copies that folder's contents into the test's home folder (Pictures/Tephra, ...)
# Tephra's intro takes about 10 s: start the plan at 12 s or later. No audio, no controller, no Steam.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="$(readlink -f "${GODOT:-$(command -v godot || true)}")"
PLAN="$(readlink -f "${1:?plan.json}")"
OUT="$(mkdir -p "${2:?output dir}" && readlink -f "$2")"
[ -x "$GODOT" ] || { echo "ui-test: Godot not found (set GODOT)" >&2; exit 2; }
command -v xvfb-run >/dev/null || { echo "ui-test: xvfb-run not found" >&2; exit 2; }

W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/home" "$W/data"
[ -n "${HOMESEED:-}" ] && cp -r "$HOMESEED"/. "$W/home"/
cp -r "$ROOT/shell/tephra-shell" "$W/p"
cp "$ROOT/tools/ui_shot.gd" "$W/p/ui_shot.gd"
sed -i 's|^BootOverlay=.*|&\nUiShot="*res://ui_shot.gd"|' "$W/p/project.godot"
if [ -n "${PRESEED:-}" ]; then
  mkdir -p "$W/data/godot/app_userdata/Tephra Shell"
  printf '%s' "$PRESEED" > "$W/data/godot/app_userdata/Tephra Shell/settings.json"
fi
HOME="$W/home" XDG_DATA_HOME="$W/data" XDG_CONFIG_HOME="$W/home/.config" SHOT_DIR="$OUT" SHOT_PLAN="$PLAN" \
  timeout 240 xvfb-run -a -s "-screen 0 1920x1080x24" "$GODOT" --rendering-method gl_compatibility --rendering-driver opengl3 --path "$W/p" 2>&1 \
  | grep -E 'SCRIPT ERROR|Parse Error' -A2 | head -40
echo "settings.json: $(cat "$W"/data/godot/app_userdata/*/settings.json 2>/dev/null | head -c 800)"
ls "$OUT"
