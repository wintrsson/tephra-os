# Tephra

A console-style shell for Linux: boot straight into a controller-driven home screen, launch your Steam (and PS2) games, and never see a desktop. Built with Godot 4 (GDScript) for Arch Linux with KDE Plasma on Wayland. Steam runs hidden behind it.

## What it does
- Home row of your games, a Library of everything you own, game pages with storage, achievements and info.
- Control center on the system button: sound, downloads, notifications, album, Files (with Trash and a Notepad), browser, themes, power, brightness.
- Settings, Bluetooth and Wi-Fi menus, on-screen keyboards in DualSense, Xbox and Switch layouts.
- Twelve themes, each with its own look, sounds and music (Tephra, Volcanic, Sleek, Channels, PS2, Frutiger, Wave, Gun metal, Neon Coast, Mold, Wood, Retro).
- Self-updating from this repository, a supervising launcher that restarts it after updates, screenshots and recording from the touchpad.

## Layout
- `shell/tephra-shell/` — the Godot project (`home.gd` is the main shell). `VERSION` is bumped every release.
- `tools/` — `install-update.sh` (apply a release tarball), `panel-toggle.sh`.
- `configs/` — autostart entries, KWin rules, SDDM, udev rules, and system files (`configs/system`).
- `branding/` — Plymouth boot splash and logo.
- `packages-official.txt`, `packages-aur.txt` — what the install needs.

## Running
`shell/tephra-shell/tephra-run.sh` starts Tephra and restarts it after an update or crash (`tephra-cli.sh start` / `stop`). The controller touchpad is the screenshot / record button; `touchpad-off.sh` turns off its mouse behaviour.

## Status
Personal project in active development; a public gaming-OS release (USB installer) is planned. See `TODO.md` and `CHANGELOG.md`.

Fonts are free to share, see `shell/tephra-shell/assets/fonts/LICENSE.txt`. All art and sound are original.
