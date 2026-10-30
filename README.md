# Arch Updates
Number based count badge for the Omarchy quattro bar. Dim when clean,
count badge when updates are waiting.

## What it shows

- Bar pill: `↓` when up to date (dimmed), `↓ N` when N updates are pending.
- Tooltip: the repo/AUR breakdown, e.g. `Repo: 8 · AUR: 4 · Click to update`.
- Left click: opens `omarchy update` in kitty.
- Middle click: forces an immediate recheck.

## How it checks

`check-updates.sh` runs `checkupdates` (repo, from pacman-contrib) and
`yay -Qua` (AUR, falls back to `paru -Qua`), and prints
`<total> <repo> <aur>`. The widget polls it on a timer. Checking only
counts; nothing here installs anything, installs go through
`omarchy update` as Omarchy intends.

## Install

```bash
tar xzf arch-updates-plugin.tar.gz -C ~/.config/omarchy/plugins/
chmod +x ~/.config/omarchy/plugins/devi.arch-updates/check-updates.sh
command -v checkupdates || omarchy-pkg-add pacman-contrib
omarchy-shell shell rescanPlugins
omarchy bar put devi.arch-updates --section right
omarchy restart shell
```

## Settings

Check interval: edit `intervalMinutes` at the top of `BarWidget.qml`
(minutes between checks, default 60), then restart the shell if it does
not pick it up live.

Update command: edit `updateCommand` at the top of `BarWidget.qml`
if you prefer another terminal.

## Notes

- First check can take a few seconds: `checkupdates` syncs the package
  databases, and the AUR query takes a moment.
- If you renamed the plugin directory, update the script path in
  `BarWidget.qml` (`checkProc.command`) to match.
- Designed for a horizontal (top/bottom) bar. The pill follows the bar
  font like any other widget.
- If your bar hides non-workspace widgets on a secondary monitor, this
  badge only appears on the monitors that show the full bar.
