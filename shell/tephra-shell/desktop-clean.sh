#!/bin/bash
# Tephra is the whole screen: no icons on the desktop behind it. Anything that lands in the Desktop folder
# (Steam's "create shortcut", installers) is moved to ~/.local/share/tephra/desktop-backup, so nothing is lost.
# Safe to run again and again.
dir=$(xdg-user-dir DESKTOP 2>/dev/null)
[ -z "$dir" ] && dir="$HOME/Desktop"
[ "$dir" = "$HOME" ] && exit 0
[ -d "$dir" ] || exit 0
backup="$HOME/.local/share/tephra/desktop-backup"
for f in "$dir"/* "$dir"/.[!.]*; do
	[ -e "$f" ] || [ -L "$f" ] || continue
	mkdir -p "$backup"
	mv -n "$f" "$backup/" 2>/dev/null
done
