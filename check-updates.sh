#!/bin/bash
# Count pending Arch repo + AUR updates for the devi.arch-updates bar widget.
# Prints one line: "<total> <repo> <aur>"
# Check-only: nothing here installs anything. Installs go through omarchy update.

repo=0
aur=0

if command -v checkupdates >/dev/null 2>&1; then
  repo=$(checkupdates 2>/dev/null | wc -l)
fi

if command -v yay >/dev/null 2>&1; then
  aur=$(yay -Qua 2>/dev/null | wc -l)
elif command -v paru >/dev/null 2>&1; then
  aur=$(paru -Qua 2>/dev/null | wc -l)
fi

repo=$(echo "$repo" | tr -d ' ')
aur=$(echo "$aur" | tr -d ' ')

echo "$((repo + aur)) $repo $aur"
