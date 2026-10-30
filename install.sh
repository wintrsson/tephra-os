#!/usr/bin/env bash
# Tephra installer for Arch Linux (and Arch-based distros) with KDE Plasma.
#
#   curl -fsSL https://raw.githubusercontent.com/wintrsson/tephra-os/main/install.sh | bash
#
# or, from a downloaded copy:  ./install.sh
#
# What it does (asks before anything optional):
#   1. installs the packages Tephra uses (pacman, with sudo)
#   2. puts Tephra in ~/tephra (a git copy, so it can update itself)
#   3. lets Tephra drive the DualSense lights and a virtual keyboard (two udev rules)
#   4. starts Tephra and Steam (hidden) when you log in
#   5. optional: log in automatically, so the PC boots straight into Tephra
#   6. optional: PS2 emulator (PCSX2 from Flathub)
# Run ./uninstall.sh (in ~/tephra) to undo it.
set -euo pipefail

REPO_URL="${TEPHRA_REPO:-https://github.com/wintrsson/tephra-os}"
DEST="$HOME/tephra"

say()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m  %s\n' "$*"; }
die()  { printf '\033[1;31mxx\033[0m  %s\n' "$*" >&2; exit 1; }
# Questions read from the terminal, so they work under `curl ... | bash` too. No terminal: the default answer.
ask() {
  local q="$1" def="$2" a=""
  if (: </dev/tty) 2>/dev/null; then
    read -r -p "$q $( [ "$def" = y ] && echo '[Y/n]' || echo '[y/N]' ) " a < /dev/tty || true
  fi
  a="${a:-$def}"
  [[ "$a" =~ ^[Yy] ]]
}

[ "$(id -u)" -ne 0 ] || die "Run this as your normal user, not root. It uses sudo when it needs to."
command -v pacman >/dev/null || die "Tephra needs Arch Linux or an Arch-based distro (pacman was not found)."
command -v sudo >/dev/null || die "sudo is needed."

echo
echo "  Tephra: a console-style, controller-only shell for Linux"
echo "  This installs it for $USER in $DEST."
echo
ask "Continue?" y || exit 0

# ---------- 1. Packages ----------
if ! grep -qE '^\[multilib\]' /etc/pacman.conf; then
  die "Steam needs the multilib repository. Uncomment the [multilib] lines in /etc/pacman.conf, run 'sudo pacman -Syu', then run this again."
fi
PKGS=(
  git godot python curl unzip 7zip libarchive ffmpeg mpv pciutils libnotify
  steam flatpak firefox
  networkmanager bluez bluez-utils pipewire pipewire-pulse wireplumber libpulse
  kscreen spectacle kio xdotool xorg-xprop brightnessctl ddcutil
)
say "Installing packages (sudo may ask for your password)"
sudo pacman -Syu --needed --noconfirm "${PKGS[@]}"
sudo systemctl enable --now NetworkManager bluetooth >/dev/null 2>&1 || true

# Godot 4.7 or newer is needed.
gv="$(godot --version 2>/dev/null | cut -d. -f1-2 || true)"
if [ -n "$gv" ] && [ "$(printf '%s\n4.7\n' "$gv" | sort -V | head -n1)" != "4.7" ]; then
  warn "Your Godot is $gv; Tephra is made for 4.7 or newer. It may not start until Arch updates Godot."
fi

if lspci 2>/dev/null | grep -qiE 'vga.*nvidia|3d.*nvidia'; then
  if ! lsmod 2>/dev/null | grep -q '^nvidia'; then
    warn "NVIDIA graphics found without the NVIDIA driver. Games run much better with it:"
    warn "see https://wiki.archlinux.org/title/NVIDIA (Tephra doesn't install drivers for you)."
  fi
fi

# ---------- 2. Tephra itself ----------
if [ -d "$DEST/.git" ]; then
  say "Tephra is already in $DEST: bringing it up to date"
  git -C "$DEST" pull --ff-only -q || warn "Couldn't update $DEST (local changes?). Leaving it as it is."
elif [ -e "$DEST" ]; then
  die "$DEST already exists and isn't Tephra. Move it away, then run this again."
else
  say "Downloading Tephra to $DEST"
  git clone -q --depth 1 "$REPO_URL" "$DEST"
fi
# Tephra records each update as a git commit on this PC (so a bad one can be undone): it needs a name to sign them with.
git -C "$DEST" config user.name >/dev/null || git -C "$DEST" config user.name "Tephra"
git -C "$DEST" config user.email >/dev/null || git -C "$DEST" config user.email "tephra@localhost"
SHELL_DIR="$DEST/shell/tephra-shell"
chmod +x "$SHELL_DIR"/*.sh "$DEST"/tools/*.sh "$DEST"/*.sh 2>/dev/null || true

# ---------- 3. Controller lights and the virtual keyboard ----------
say "Letting Tephra use the controller lights and a virtual keyboard"
sudo install -m 644 "$DEST"/configs/udev/70-tephra-*.rules /etc/udev/rules.d/
echo uinput | sudo tee /etc/modules-load.d/tephra-uinput.conf >/dev/null
sudo modprobe uinput 2>/dev/null || true
sudo udevadm control --reload
sudo udevadm trigger --name-match=uinput 2>/dev/null || true

# ---------- 4. Start with the session ----------
say "Starting Tephra and Steam (hidden) when you log in"
mkdir -p "$HOME/.config/autostart" "$HOME/.local/bin"
cat > "$HOME/.config/autostart/tephra.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Tephra
Exec=$SHELL_DIR/tephra-run.sh
X-KDE-AutostartPhase=2
EOF
cp "$DEST/configs/autostart/steam-silent.desktop" "$HOME/.config/autostart/"
ln -sf "$SHELL_DIR/tephra-cli.sh" "$HOME/.local/bin/tephra"

# ---------- 5. Optional: boot straight into Tephra ----------
if ask "Log in automatically, so the PC boots straight into Tephra?" y; then
  sudo mkdir -p /etc/sddm.conf.d
  printf '[Autologin]\nUser=%s\nSession=plasma.desktop\nRelogin=false\n' "$USER" | sudo tee /etc/sddm.conf.d/tephra-autologin.conf >/dev/null
  sudo systemctl enable sddm >/dev/null 2>&1 || true
fi

# ---------- 6. Optional: PS2 ----------
if ask "Install the PS2 emulator (PCSX2)? You add your own BIOS and games later." n; then
  flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  flatpak install --user -y flathub net.pcsx2.PCSX2
  mkdir -p "$HOME/Games/PS2"
fi

echo
say "Done. Restart your PC (or log out and in) and Tephra starts by itself."
echo "    Start it now:  tephra start      Undo everything:  $DEST/uninstall.sh"
echo "    The first start walks you through Wi-Fi, Steam, your controller and a theme."
