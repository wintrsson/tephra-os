#!/usr/bin/env bash
# Tephra's launcher. It starts Tephra and stays in the background only to bring it back after an update or
# "Restart Tephra" (Tephra leaves a note, quits, and this starts it again). Any other way Tephra ends (Close Tephra,
# closing its window, a crash, being killed) ends this too: Tephra never reopens by itself.
# The one exception is a new version that doesn't start: an update leaves ~/.config/tephra/update-pending (the commit
# it came from and the new version), and Tephra deletes it once it has been running fine for a few seconds. If Tephra
# crashes or hangs before that, this goes back to the commit it came from and starts that version again.
# The autostart entry and `tephra start` both run this file.
DIR="$(cd "$(dirname "$0")" && pwd)"
RUN="${XDG_RUNTIME_DIR:-/tmp}"
FLAG="$RUN/tephra-restart"
CFG="$HOME/.config/tephra"
PENDING="$CFG/update-pending"   # line 1: the commit to go back to, line 2: the version being tried
FAILED="$CFG/update-failed"     # line 1: a version that didn't start, line 2: "new" until Tephra has said so
GRACE="${TEPHRA_GRACE:-60}"     # seconds a new version gets to show it is running
export TEPHRA_SUPERVISED=1

# Only one launcher at a time. The lock is the open file 9, which every program started from here would inherit and keep
# (Steam, a game that outlives Tephra): so Tephra and everything it starts get 9 closed (9>&- below), and only this script
# holds the lock.
if command -v flock >/dev/null; then
  exec 9>"$RUN/tephra-run.lock"
  flock -n 9 || { echo "Tephra is already running."; exit 0; }
fi
echo "launcher: started $(date '+%F %T'), godot is $(command -v godot || echo 'NOT FOUND')"

panel_back() {
  busctl --user call org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell evaluateScript s \
    "panels().forEach(function (p) { var w = p.readConfig('tephraWas', ''); p.hiding = (w == '' ? 'none' : w); p.writeConfig('tephraWas', ''); });" >/dev/null 2>&1
}

# Puts the files of the version before the update back (and removes the ones the new version added), records that the
# new version failed, and commits that. Returns 1 if it can't, and then nothing is changed.
rollback() {
  local prev ver repo f
  prev=$(sed -n 1p "$PENDING" 2>/dev/null)
  ver=$(sed -n 2p "$PENDING" 2>/dev/null)
  command -v git >/dev/null || return 1
  repo=$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null) || return 1
  [ -n "$prev" ] && git -C "$repo" cat-file -e "$prev^{commit}" 2>/dev/null || return 1
  git -C "$repo" checkout -q "$prev" -- shell/tephra-shell tools/install-update.sh || return 1
  while IFS= read -r f; do
    [ -n "$f" ] && rm -f -- "$repo/$f"
  done < <(git -C "$repo" diff --name-only --diff-filter=A "$prev" HEAD -- shell/tephra-shell tools 2>/dev/null)
  git -C "$repo" add -A shell tools >/dev/null 2>&1
  git -C "$repo" commit -qm "Rolled back v$ver: it did not start" >/dev/null 2>&1
  printf '%s\nnew\n' "$ver" > "$FAILED"
  rm -f "$PENDING"
  return 0
}

while true; do
  rm -f "$FLAG" "$RUN/tephra-unhealthy"
  if [ -f "$PENDING" ]; then
    # A version that was just installed: watch it. Tephra deletes $PENDING when it has been running fine for a few
    # seconds; if that hasn't happened after $GRACE seconds it is hung, and gets stopped.
    godot --path "$DIR" --fullscreen 9>&- &
    pid=$!
    (
      n=0
      while [ "$n" -lt "$GRACE" ]; do
        sleep 1; n=$((n + 1))
        [ -f "$PENDING" ] || exit 0
        kill -0 "$pid" 2>/dev/null || exit 0
      done
      touch "$RUN/tephra-unhealthy"
      kill "$pid" 2>/dev/null
    ) 9>&- &
    watchdog=$!
    wait "$pid"
    code=$?
    kill "$watchdog" 2>/dev/null
    wait "$watchdog" 2>/dev/null
  else
    godot --path "$DIR" --fullscreen 9>&-
    code=$?
  fi
  if [ -f "$FLAG" ]; then
    rm -f "$FLAG"
    sleep 0.5
    continue  # asked to restart (an update): start the new version
  fi
  if [ -f "$PENDING" ] && { [ "$code" -ne 0 ] || [ -f "$RUN/tephra-unhealthy" ]; }; then
    echo "The new version of Tephra did not start (exit code $code). Going back to the version before the update."
    if rollback; then
      sleep 0.5
      continue
    fi
    echo "Couldn't go back automatically. Undo it by hand: cd ~/tephra && git log --oneline"
    rm -f "$PENDING"  # never loop on this
  fi
  if [ "$code" -ne 0 ]; then
    echo "Tephra stopped (exit code $code). Start it again with: tephra start   (details: tephra log)"
    panel_back  # the taskbar comes back for the desktop
  fi
  break
done
