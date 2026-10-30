#!/usr/bin/env bash
# Shows the KDE taskbar if it's gone, removes it if it's there.
qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript '
if (panels().length > 0) {
  panels().forEach(p => p.remove());
} else {
  loadTemplate("org.kde.plasma.desktop.defaultPanel");
}'
