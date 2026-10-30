#!/bin/bash
# Cloud sessions only: install headless Godot (for tools/check.sh) and bring the session's branch up to the
# newest release on the update branch Tephra installs from.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

GODOT_VERSION="4.7-stable"
BIN="$HOME/.local/bin"
GODOT="$BIN/godot"
mkdir -p "$BIN"
if [ ! -x "$GODOT" ] || ! "$GODOT" --version 2>/dev/null | grep -q "^${GODOT_VERSION%-stable}\."; then
  TMP="$(mktemp -d)"
  curl -sSL -o "$TMP/godot.zip" \
    "https://github.com/godotengine/godot/releases/download/$GODOT_VERSION/Godot_v${GODOT_VERSION}_linux.x86_64.zip"
  unzip -oq "$TMP/godot.zip" -d "$TMP"
  mv "$TMP/Godot_v${GODOT_VERSION}_linux.x86_64" "$GODOT"
  chmod +x "$GODOT"
  rm -rf "$TMP"
fi
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export PATH=\"$BIN:\$PATH\"" >> "$CLAUDE_ENV_FILE"
  echo "export GODOT=\"$GODOT\"" >> "$CLAUDE_ENV_FILE"
fi

# Stay on the newest release: fast-forward to the update branch when that's clean and safe. Never fails the session.
cd "${CLAUDE_PROJECT_DIR:-$(pwd)}"
UPDATE_BRANCH="$(sed -n 's/^const BRANCH := "\(.*\)"/\1/p' shell/tephra-shell/self_update.gd)"
if [ -n "$UPDATE_BRANCH" ] && git fetch -q origin "$UPDATE_BRANCH" 2>/dev/null; then
  if [ -z "$(git status --porcelain)" ] && git merge-base --is-ancestor HEAD FETCH_HEAD; then
    git merge -q --ff-only FETCH_HEAD && echo "Synced to $UPDATE_BRANCH: v$(cat shell/tephra-shell/VERSION)"
  else
    echo "Not synced to $UPDATE_BRANCH (local changes or diverged history); now on v$(cat shell/tephra-shell/VERSION)"
  fi
fi
