#!/bin/bash
# The controller's touchpad is Tephra's screenshot / record button, not a mouse: turn off the pointer device the
# kernel makes from it (KDE Plasma on Wayland, through KWin's own D-Bus). Safe to run again and again.
for path in $(busctl --user tree org.kde.KWin 2>/dev/null | grep -o '/org/kde/KWin/InputDevice/event[0-9]*'); do
	name=$(busctl --user get-property org.kde.KWin "$path" org.kde.KWin.InputDevice name 2>/dev/null)
	case "$name" in
	*Touchpad*)
		case "$name" in
		*Wireless*Controller*|*DualSense*|*DualShock*|*Sony*|*PS4*|*PS5*)
			if busctl --user get-property org.kde.KWin "$path" org.kde.KWin.InputDevice enabled 2>/dev/null | grep -q true; then
				busctl --user set-property org.kde.KWin "$path" org.kde.KWin.InputDevice enabled b false 2>/dev/null
			fi
			;;
		esac
		;;
	esac
done
