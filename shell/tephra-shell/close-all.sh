#!/usr/bin/env bash
# Tephra: close everything Tephra and Steam started, before Tephra closes, restarts or updates.
#
# Closed: every game (Steam and non-Steam), Proton, Wine and anything running a Windows .exe, Steam itself and
# everything it started, gamescope, PCSX2, Tephra's browser and recorder, Tephra's hidden screen for Steam (Xvfb :99),
# and anything else Tephra itself started.
# Kept: Tephra, its launcher, whatever runs this script (a terminal, say), Spectacle, and the desktop itself (KDE,
# sound, the session, portals, keyrings, ssh).
#
# Games paused behind a Tephra menu are stopped processes: they are woken first, or they could never close.
# Order: wake -> ask the games to close -> ask Steam to shut down -> ask the rest -> force whatever is left.

me=$$
LOG="$HOME/.config/tephra/close-all.log"
mkdir -p "$HOME/.config/tephra"

# Never touched, whatever started them.
KEEP_COMM='^(systemd|systemd-.*|\(sd-pam\)|dbus-daemon|dbus-broker.*|pipewire.*|wireplumber|pulseaudio|kwin_wayland|kwin_x11|kwin_wayland_wr.*|plasmashell|ksmserver|kded5|kded6|kglobalaccel.*|Xwayland|Xorg|sddm.*|startplasma.*|plasma_session|ssh-agent|sshd.*|gpg-agent|xdg-.*|kwalletd.*|ksecretd|polkit.*|at-spi.*|gvfs.*|baloo.*|kactivitymanage.*|powerdevil.*|org_kde_powerde.*|spectacle|konsole|login|agetty|sudo|tmux.*|screen)$'
# Programs that are closed wherever they came from.
KILL_COMM='^(steam|steamwebhelper|reaper|pressure-vessel.*|srt-bwrap|gamescope.*|wineserver|wine.*|pcsx2.*|gpu-screen-rec.*|Xvfb|steam-runtime.*|fossilize.*)$'
KILL_ARGS='\.exe( |$)|[Ww]ine|[Pp]roton|steamapps/|tephra/browser|SteamLaunch|Xvfb :99'
KILL_ENV='^(SteamGameId|SteamAppId|STEAM_COMPAT_APP_ID|STEAM_COMPAT_DATA_PATH|WINEPREFIX)='

declare -A PP COMM KEEP
targets=()

scan() {
  PP=(); COMM=(); KEEP=(); targets=()
  local d p line rest c
  for d in /proc/[0-9]*; do
    [ -O "$d" ] || continue   # this user's own processes only
    p=${d#/proc/}
    read -r line < "$d/stat" 2>/dev/null || continue
    c=${line#*(}; c=${c%)*}
    rest=${line##*) }
    COMM[$p]=$c
    PP[$p]=$(cut -d' ' -f2 <<<"$rest")
  done
  # This script and everything above it (the terminal that ran an update, Tephra running a restart) stay.
  p=$me
  while [ -n "$p" ] && [ "$p" != 0 ] && [ "$p" != 1 ]; do KEEP[$p]=1; p=${PP[$p]}; done
  # Tephra itself and its launcher stay.
  local tephra=()
  for p in "${!COMM[@]}"; do
    local args
    args=$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null)
    if [[ "$args" == *godot*tephra-shell* || "$args" == *tephra-run.sh* ]]; then
      KEEP[$p]=1
      [[ "$args" == *godot* ]] && tephra+=("$p")
    fi
  done
  for p in "${!COMM[@]}"; do
    [ "$p" = "$me" ] && continue
    [ -n "${KEEP[$p]}" ] && continue
    [[ "${COMM[$p]}" =~ $KEEP_COMM ]] && continue
    local hit=""
    if [[ "${COMM[$p]}" =~ $KILL_COMM ]]; then hit=1
    elif grep -qzE "$KILL_ENV" "/proc/$p/environ" 2>/dev/null; then hit=1
    elif [[ "$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null)" =~ $KILL_ARGS ]]; then hit=1
    else
      # Started (directly or further down) by Steam or by Tephra.
      local a=${PP[$p]} n=0
      while [ -n "$a" ] && [ "$a" != 1 ] && [ $n -lt 64 ]; do
        [ "$a" = "$me" ] && break   # this script's own helpers
        if [[ "${COMM[$a]}" =~ ^(steam|reaper)$ ]]; then hit=1; break; fi
        for t in "${tephra[@]}"; do [ "$a" = "$t" ] && hit=1; done
        [ -n "$hit" ] && break
        a=${PP[$a]}; n=$((n + 1))
      done
    fi
    [ -n "$hit" ] && targets+=("$p")
  done
}

names() { for p in "$@"; do printf '%s(%s) ' "${COMM[$p]}" "$p"; done; }

{
echo "---- $(date '+%F %T') close-all"
scan
echo "found: $(names "${targets[@]}")"
[ ${#targets[@]} -gt 0 ] && kill -CONT "${targets[@]}" 2>/dev/null   # paused games wake up, or they never close
flatpak kill net.pcsx2.PCSX2 2>/dev/null
pkill -INT -f '[g]pu-screen-recorder' 2>/dev/null   # a recording is finished properly, not cut off

# The games first (everything except Steam's own client).
games=()
for p in "${targets[@]}"; do [[ "${COMM[$p]}" =~ ^(steam|steamwebhelper)$ ]] || games+=("$p"); done
[ ${#games[@]} -gt 0 ] && kill -TERM "${games[@]}" 2>/dev/null

# Steam, politely: it saves its settings and cloud saves on the way out.
if pgrep -x steam >/dev/null && command -v steam >/dev/null; then
  steam -shutdown >/dev/null 2>&1 &
  for i in $(seq 1 16); do pgrep -x steam >/dev/null || break; sleep 0.5; done
fi

scan
[ ${#targets[@]} -gt 0 ] && { echo "still running, asked to close: $(names "${targets[@]}")"; kill -CONT "${targets[@]}" 2>/dev/null; kill -TERM "${targets[@]}" 2>/dev/null; }
for i in 1 2 3; do
  sleep 0.5
  scan
  [ ${#targets[@]} -eq 0 ] && break
done
if [ ${#targets[@]} -gt 0 ]; then
  echo "forced closed: $(names "${targets[@]}")"
  kill -KILL "${targets[@]}" 2>/dev/null
fi
echo "done"
} >>"$LOG" 2>&1

# The log only keeps the last few runs.
tail -n 200 "$LOG" > "$LOG.tmp" 2>/dev/null && mv -f "$LOG.tmp" "$LOG"
exit 0
