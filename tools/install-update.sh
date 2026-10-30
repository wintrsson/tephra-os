#!/usr/bin/env bash
# Tephra updater v2
#   1. Saves the current state in git (so any update can be undone)
#   2. Installs the files from ~/Downloads (keeps the newest copy of each)
#   3. Commits them as a new version, tags it, and pushes to GitHub
#   4. Restarts Tephra so the update is running (skip with TEPHRA_NO_RESTART=1)
#
# Usage:  ~/tephra/tools/install-update.sh v0.3.0 "UI revamp"
# Undo:   cd ~/tephra && git log --oneline   then   git checkout <commit> -- shell
set -euo pipefail

REPO="$HOME/tephra"
DEST="$REPO/shell/tephra-shell"
DL="$HOME/Downloads"
VERSION="${1:-}"
MSG="${2:-Update}"

cd "$REPO"

# ---------- One-time git setup ----------
if [ ! -d .git ]; then
  git init -q -b main
  echo "Started a git history in $REPO"
fi
if [ ! -f .gitignore ]; then
  printf '%s\n' '# Godot cache (rebuilt automatically)' '.godot/' '# Never commit secrets' '*.cfg' > .gitignore
fi

# Refuses to continue if your Steam API key ended up inside the repo.
check_secrets() {
  local key
  key=$(sed -n 's/^api_key=//p' "$HOME/.config/tephra/steam.cfg" 2>/dev/null | tr -d '[:space:]' || true)
  if [ -n "$key" ] && git grep --cached -qF "$key" 2>/dev/null; then
    echo "STOP: your Steam API key is inside a file in ~/tephra. Remove it, then run this again."
    git reset -q
    exit 1
  fi
}

# ---------- 1. Safety snapshot ----------
git add -A
check_secrets
if ! git diff --cached --quiet; then
  git commit -qm "Snapshot before ${VERSION:-update}"
  echo "Saved the current state."
fi

PREV=$(git rev-parse -q --verify HEAD 2>/dev/null || true)   # what the launcher goes back to if the new version won't start

# ---------- 2. Install downloads ----------
cd "$DL"
# A full Tephra tarball (or the folder "Extract here" makes from it, like tephra-v0.37.0-full/) is copied
# over the whole shell folder, assets and fonts included. Once installed, the download is deleted (the repo
# keeps every version, so nothing is lost). Leftovers named installed-tephra-... from older installers go too.
rm -rf -- installed-tephra-* 2>/dev/null || true
installed=0
tarball=$(ls -t -- tephra-*.tar.gz 2>/dev/null | head -n 1 || true)   # the newest download wins
if [ -n "$tarball" ]; then
  mkdir -p "$DL/tephra-unpacked"
  if tar xzf "$tarball" -C "$DL/tephra-unpacked"; then
    rm -f -- tephra-*.tar.gz   # older ones too, so they never come back
  fi
  echo "Unpacked $tarball"
fi
for d in tephra-unpacked/ tephra-v*/; do   # never older working folders like tephra-new/
  d="${d%/}"
  [ -f "$d/home.gd" ] || continue
  cp -rf -- "$d"/. "$DEST"/
  if [ -f "$d/install-update.sh" ]; then
    cp -f -- "$d/install-update.sh" "$REPO/tools/install-update.sh.new" && mv -f -- "$REPO/tools/install-update.sh.new" "$REPO/tools/install-update.sh"
    chmod +x "$REPO/tools/install-update.sh"; rm -f -- "$DEST/install-update.sh"
  fi
  installed=$((installed + $(ls -- "$d"/*.gd | wc -l)))
  rm -rf -- "$d"
  echo "Installed the full shell from $d"
done
declare -A seen
while IFS= read -r f; do
  # "home (1).gd" -> "home.gd"; the newest download of each name wins.
  base=$(sed -E 's/ ?\([0-9]+\)(\.[A-Za-z]+)$/\1/' <<<"$f")
  if [ -n "${seen[$base]:-}" ]; then
    rm -f -- "$f"   # an older duplicate
    continue
  fi
  seen[$base]=1
  case "$base" in
    *.gd)              target="$DEST/$base" ;;
    CHANGELOG.md|TODO.md) target="$REPO/$base" ;;
    *.rules)           target="$REPO/configs/udev/$base" ;;
    install-update.sh) target="$REPO/tools/install-update.sh" ;;
    *) continue ;;
  esac
  mkdir -p "$(dirname "$target")"
  # Copy then rename, so replacing this script while it runs is safe.
  cp -f -- "$f" "$target.new" && mv -f -- "$target.new" "$target"
  [[ "$base" == *.sh ]] && chmod +x "$target"
  rm -f -- "$f"
  echo "Updated ${target#"$REPO"/}"
  installed=$((installed + 1))
done < <([ "$installed" -gt 0 ] || ls -t -- *.gd CHANGELOG*.md TODO*.md *.rules install-update*.sh 2>/dev/null || true)

if [ "$installed" -eq 0 ]; then
  echo "Nothing new in ~/Downloads."
fi

# ---------- 3. Record the version ----------
cd "$REPO"
git add -A
check_secrets
if git diff --cached --quiet; then
  echo "No changes to record."
else
  git commit -qm "${VERSION:+$VERSION: }$MSG"
  echo "Recorded: ${VERSION:+$VERSION: }$MSG"
fi
if [ -n "$VERSION" ] && ! git rev-parse -q --verify "refs/tags/$VERSION" >/dev/null; then
  git tag -a "$VERSION" -m "$MSG"
  echo "Tagged $VERSION"
fi

if git remote get-url origin >/dev/null 2>&1; then
  # Never a password window (KDE Wallet): with no saved GitHub login the push just fails quietly.
  if env -u SSH_ASKPASS GIT_ASKPASS=true GIT_TERMINAL_PROMPT=0 git push -q --follow-tags origin HEAD 2>/dev/null; then
    echo "Pushed to GitHub."
  else
    echo "Couldn't push to GitHub (offline, or no saved GitHub login). Saved locally; it'll go up next time."
  fi
else
  echo "No GitHub repo linked yet, so this was saved locally only."
fi

# ---------- 4. Restart Tephra ----------
# Closes the running Tephra (and any Godot editor on it) and starts it again, the same way
# the autostart entry does, detached so it keeps running after this terminal closes.
if [ "$installed" -gt 0 ] && [ -z "${TEPHRA_NO_RESTART:-}" ] && command -v godot >/dev/null 2>&1; then
  echo "Closing games, PCSX2 and Steam..."
  # Everything Tephra and Steam started (paused games are woken first, or they could never close).
  [ -f "$DEST/close-all.sh" ] && bash "$DEST/close-all.sh" || true
  # Everything Steam started for a game (non-Steam shortcuts too) has SteamGameId in its environment.
  game_pids() {
    for e in /proc/[0-9]*/environ; do
      p=${e#/proc/}; p=${p%/environ}
      [ "$p" = "$$" ] && continue
      grep -qzE '^(SteamGameId|STEAM_COMPAT_APP_ID)=' "$e" 2>/dev/null && echo "$p"
    done
    return 0  # the loop's last test usually fails (not a game), and set -e would end the whole update there
  }
  pids=$(game_pids); [ -n "$pids" ] && kill $pids 2>/dev/null || true
  pkill -f '[S]teamLaunch AppId=' 2>/dev/null || true
  pkill -f '[s]teamapps/common/' 2>/dev/null || true   # Proton / Wine programs, non-Steam games started through Steam
  pkill -x gamescope 2>/dev/null || true
  flatpak kill net.pcsx2.PCSX2 2>/dev/null || true
  pkill -f '[p]csx2' 2>/dev/null || true
  if pgrep -x steam >/dev/null; then
    steam -shutdown >/dev/null 2>&1 &
    for i in $(seq 1 20); do pgrep -x steam >/dev/null || break; sleep 0.5; done
    pkill -x steam 2>/dev/null || true
    pkill -f steamwebhelper 2>/dev/null || true
  fi
  pkill -f 'Xvfb :99' 2>/dev/null || true
  if [ -n "$(game_pids)" ] || pgrep -f '[s]teamapps/common/|[S]teamLaunch AppId=' >/dev/null; then   # anything that ignored the polite ask
    sleep 1
    pids=$(game_pids); [ -n "$pids" ] && kill -9 $pids 2>/dev/null || true
    pkill -9 -f '[s]teamapps/common/' 2>/dev/null || true
    pkill -9 -f '[S]teamLaunch AppId=' 2>/dev/null || true
  fi
  # tephra-run.sh watches the new version: if it crashes or hangs before it has run fine for a few seconds, it puts
  # PREV's files back and starts the old version. Tephra deletes this note once it is running fine.
  if [ -n "$PREV" ]; then
    mkdir -p "$HOME/.config/tephra"
    printf '%s\n%s\n' "$PREV" "$(tr -d '[:space:]' < "$DEST/VERSION" 2>/dev/null)" > "$HOME/.config/tephra/update-pending"
  fi
  echo "Restarting Tephra..."
  if pgrep -f "[t]ephra-run.sh" >/dev/null; then
    # Tephra's launcher is running: leave it a note, close Tephra, and the launcher starts the new version.
    touch "${XDG_RUNTIME_DIR:-/tmp}/tephra-restart"
    pkill -f "godot.*tephra-shell" 2>/dev/null || true
  else
    pkill -f "godot.*tephra-shell" 2>/dev/null || true
    sleep 1.5
    cd "$DEST"
    chmod +x "$DEST/tephra-run.sh" 2>/dev/null || true
    if [ -x "$DEST/tephra-run.sh" ]; then
      setsid nohup "$DEST/tephra-run.sh" >/dev/null 2>&1 < /dev/null &
    else
      setsid nohup godot --path "$DEST" --fullscreen >/dev/null 2>&1 < /dev/null &
    fi
    disown 2>/dev/null || true
  fi
fi
