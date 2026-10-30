#!/bin/sh
# Tephra: every web link another program opens (a game's Discord button, "visit our website", a Steam link) arrives here
# instead of in the desktop browser. Tephra is told, and decides: during a game it only says what was asked for, and
# afterwards the link can be opened in Tephra's own browser. If Tephra is not running, the browser that was the
# default before Tephra took over opens it as usual.
url="$1"
[ -n "$url" ] || exit 0
RUN="${XDG_RUNTIME_DIR:-/tmp}"
if pgrep -f 'godot.*tephra-shell' >/dev/null 2>&1; then
  printf '%s\n' "$url" | tr -d '\r' | head -n 1 >> "$RUN/tephra-links"
  exit 0
fi
prev=$(cat "$HOME/.config/tephra/previous-browser" 2>/dev/null)
if [ -n "$prev" ] && [ "$prev" != "tephra-link.desktop" ]; then
  for d in "$HOME/.local/share/applications" /usr/share/applications /var/lib/flatpak/exports/share/applications "$HOME/.local/share/flatpak/exports/share/applications"; do
    if [ -f "$d/$prev" ]; then exec gio launch "$d/$prev" "$url"; fi
  done
fi
for b in firefox chromium google-chrome-stable librewolf; do
  command -v "$b" >/dev/null 2>&1 && exec "$b" "$url"
done
exit 0
