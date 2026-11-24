# Arch Updates

Shows how many updates are waiting, right in the bar. A package icon when you are up to date, the icon plus a number when updates are waiting.

## Install

```bash
hexciri plugin add https://github.com/Deoxizn/Arch-Updates --branch nyx --enable --yes
hexciri restart shell
```

Update it later with:

```bash
hexciri plugin update pizza.dirty.arch-updates --yes
hexciri restart shell
```

If the icon does not show up, place it on the bar:

```bash
hexciri bar put pizza.dirty.arch-updates --section right
```

## Use it

- Hover: see every pending update, grouped by source.
- Left click: open the list. Each source has its own Update button.
- Middle click: check again right now.
- Right click: open settings.
- In the list: `R` checks again, `S` opens settings, `Esc` closes it.

System and Arch updates run together with `hexciri update`. The other sources use their own safe command: AUR (`yay -Sua` / `paru -Sua`), Flatpak (`flatpak update`), Plugins & Themes (`hexciri plugin update --yes; hexciri theme update`), mise (`mise up`).

`checkupdates` (pacman-contrib) is already installed by the Hexciri installer, so there is nothing else to install.

## Settings

Two ways in: right-click the badge to open the standalone settings window, or open the bar settings window and use its System Updater tab. Both edit the same settings.

| Setting | What it does | Default |
|---|---|---|
| `refreshIntervalSec` | How often it checks, in seconds (300 to 7200) | 1800 |
| `alwaysShow` | Keep the icon showing even with no updates | on |
| `autoRefresh` | Check on its own, on a timer and once at startup | on |
| `checkAur` | Check AUR updates | on |
| `checkFlatpak` | Check Flatpak updates | on |
| `checkMise` | Check mise tools | on |
| `checkPlugins` | Check plugins and themes | on |
