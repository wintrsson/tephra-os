#!/usr/bin/env bash
# The `tephra` terminal command. Tephra links ~/.local/bin/tephra to this file by itself.
#   tephra clear     delete old Tephra update downloads from ~/Downloads
#   tephra update    install a Tephra tarball sitting in ~/Downloads (same as tools/install-update.sh)
#   tephra open      open Tephra (does nothing if it is already open)
#   tephra start     open Tephra fresh (closes the open one first)
#   tephra close     close Tephra and every game
#   tephra log       show the end of Tephra's log
#   tephra panel     bring KDE's taskbar back
set -u
REPO="$HOME/tephra"
DL="$HOME/Downloads"

case "${1:-}" in
  clear)
    shopt -s nullglob
    found=("$DL"/tephra-*.tar.gz "$DL"/tephra-v*/ "$DL"/installed-tephra-* "$DL"/tephra-unpacked)
    if [ ${#found[@]} -eq 0 ]; then
      echo "Nothing to clear: no old Tephra updates in ~/Downloads."
      exit 0
    fi
    for f in "${found[@]}"; do
      [ -e "$f" ] || continue
      rm -rf -- "$f" && echo "Deleted ${f#"$HOME"/}"
    done
    ;;
  update)
    shift
    exec "$REPO/tools/install-update.sh" "$@"
    ;;
  start)
    RUN="${XDG_RUNTIME_DIR:-/tmp}"
    L="$REPO/shell/tephra-shell/tephra-run.sh"
    LOG="$HOME/.config/tephra/launcher.log"
    if [ ! -f "$L" ]; then
      echo "Can't find Tephra's launcher at $L (Tephra is expected in ~/tephra)."
      exit 1
    fi
    command -v godot >/dev/null || { echo "Godot isn't installed: the 'godot' command wasn't found."; exit 1; }
    chmod +x "$L"
    mkdir -p "$(dirname "$LOG")"
    # Games, Steam and everything Tephra started close first, the same as a restart from inside Tephra.
    [ -f "$REPO/shell/tephra-shell/close-all.sh" ] && bash "$REPO/shell/tephra-shell/close-all.sh"
    if pgrep -f "[t]ephra-run.sh" >/dev/null && ! pgrep -f "[g]odot.*tephra-shell" >/dev/null; then
      # A launcher with no Tephra under it is stuck (it would never open anything): it goes, and a fresh one starts.
      pkill -f "[t]ephra-run.sh" 2>/dev/null
      sleep 0.7
    fi
    if pgrep -f "[t]ephra-run.sh" >/dev/null; then
      # The launcher is running: close this Tephra and it opens a fresh one by itself.
      touch "$RUN/tephra-restart"
      pkill -f "[g]odot.*tephra-shell" 2>/dev/null
      echo "Restarting Tephra."
    else
      if pgrep -f "[g]odot.*tephra-shell" >/dev/null; then
        pkill -f "[g]odot.*tephra-shell"
        sleep 1.5
      fi
      setsid nohup "$L" >"$LOG" 2>&1 < /dev/null &
      echo "Starting Tephra..."
      for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
        sleep 0.5
        pgrep -f "[g]odot.*tephra-shell" >/dev/null && break
      done
      if pgrep -f "[g]odot.*tephra-shell" >/dev/null; then
        echo "Tephra is starting."
      else
        echo "Tephra didn't start. The launcher said:"
        tail -n 15 "$LOG"
        echo "(more: tephra log, and ~/.config/tephra/launcher.log)"
        exit 1
      fi
    fi
    ;;
  open)
    if pgrep -f "[g]odot.*tephra-shell" >/dev/null; then
      echo "Tephra is already open. (tephra start opens it fresh.)"
    else
      exec "$0" start
    fi
    ;;
  close|stop)
    [ -f "$REPO/shell/tephra-shell/close-all.sh" ] && bash "$REPO/shell/tephra-shell/close-all.sh"
    # No restart note: the launcher sees Tephra end and ends too, so nothing brings it back until tephra open.
    pkill -f "[g]odot.*tephra-shell" 2>/dev/null && echo "Closed Tephra." || echo "Tephra isn't open."
    ;;
  panel)
    busctl --user call org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell evaluateScript s \
      "panels().forEach(function (p) { var w = p.readConfig('tephraWas', ''); p.hiding = (w == '' ? 'none' : w); p.writeConfig('tephraWas', ''); });" >/dev/null \
      && echo "Taskbar is back."
    ;;
  log)
    tail -n 60 "$HOME/.local/share/godot/app_userdata/Tephra Shell/logs/godot.log"
    ;;
  *)
    [ -n "${1:-}" ] && echo "Unknown command: $1"
    echo "tephra open      open Tephra (does nothing if it is already open)"
    echo "tephra close     close Tephra and every game"
    echo "tephra clear     delete old Tephra update downloads from ~/Downloads"
    echo "tephra update    install a Tephra tarball from ~/Downloads (give a version and message)"
    echo "tephra start     open Tephra fresh (closes the open one first)"
    echo "tephra log       show the end of Tephra's log"
    echo "tephra panel     bring KDE's taskbar back (Tephra hides it while it runs)"
    ;;
esac
