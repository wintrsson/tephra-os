#!/usr/bin/env bash
# Removes what install.sh set up. Packages (Steam, Godot...) stay installed; your games and Steam are not touched.
set -uo pipefail

DEST="$HOME/tephra"
ask() {
  local a=""
  (: </dev/tty) 2>/dev/null && read -r -p "$1 [y/N] " a < /dev/tty
  [[ "$a" =~ ^[Yy] ]]
}

echo "This removes Tephra's autostart, auto-login, udev rules and the 'tephra' command."
ask "Continue?" || exit 0

[ -x "$DEST/shell/tephra-shell/tephra-cli.sh" ] && "$DEST/shell/tephra-shell/tephra-cli.sh" close >/dev/null 2>&1 || true
rm -f "$HOME/.config/autostart/tephra.desktop" "$HOME/.config/autostart/steam-silent.desktop" "$HOME/.local/bin/tephra"
sudo rm -f /etc/sddm.conf.d/tephra-autologin.conf /etc/udev/rules.d/70-tephra-*.rules /etc/modules-load.d/tephra-uinput.conf
sudo udevadm control --reload 2>/dev/null || true

if ask "Also delete Tephra's settings (~/.config/tephra)?"; then
  rm -rf "$HOME/.config/tephra" "$HOME/.local/share/godot/app_userdata/Tephra Shell"
fi
if ask "Also delete Tephra itself ($DEST)?"; then
  rm -rf "$DEST"
fi
echo "Tephra is removed. Log out and in to get the normal desktop back."
