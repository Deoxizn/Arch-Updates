# Arch Updates

System-update indicator for the Omarchy bar, in the
[dizziee.system-updates](https://github.com/JJDizz1L/dizziee.system-updates)
model. Package icon when clean (dimmed), package-variant icon plus `N`
when N updates are pending. Hover the pill and the tooltip lists every
pending update vertically, per category, Noctalia-style, instead of just
a number. Left click opens a panel listing the pending packages per
source, with an update button each.

## The combined Omarchy + Arch section

There is one section for Omarchy and Arch together, and one update
action for it: `omarchy update`, the full managed pipeline (transcript,
snapshot, keyrings, migrations, post-update hooks). A bare arch update
is never an update action here, not even with
`OMARCHY_ALLOW_DIRECT_PACMAN=1`: it bypasses Omarchy's guard and skips
the managed pipeline, and as the dizziee README says, running just an
arch update is useless and can be harmful. The section's count is the
Arch repo count, and it notes when an Omarchy update itself is available
(the omarchy package in the repo list, or a dev checkout behind its
upstream).

The other sources keep their own safe updater:

- AUR: `yay -Sua` / `paru -Sua`
- Flatpak: `flatpak update`
- Plugins & Themes: `omarchy plugin update --yes; omarchy theme update`
- mise: `MISE_MINIMUM_RELEASE_AGE=0 mise up`

Each update opens a terminal and runs the command, then waits for a
keypress, so the terminal stays open after a clean run instead of
closing the second the update exits. After an update starts, the widget
rescans on a fast poll until the numbers settle.

## What it shows

- Bar pill: package icon (nf-oct-package, U+F487) when up to date
  (dimmed), package-variant icon (nf-md-package_variant, U+F03D6) plus
  `N` when N updates are pending.
- Tooltip (hover): all five sections, in order, listing each pending
  item vertically with its version change:
  - Omarchy + Arch / AUR / Flatpak / mise: `name old-version → new-version`.
  - Plugins & Themes: `name (N commits behind)` (a git checkout has no
    version to show).
  - Categories with nothing pending still show their header, e.g.
    `AUR (0)`, with no rows under it.
  - Each category lists at most 20 rows, then `…and N more`, so a huge
    update list does not run the tooltip off the bottom of the screen.
  - Left-aligned: the bar centers tooltip lines, so every line is padded
    to the longest line's length, which makes the centered lines share
    one left edge. That only lines up because the bar font is monospace.
    Padding is U+00A0 no-break space: plain spaces did not work (v1.7.2),
    Qt trims trailing spaces when measuring centered lines, so every line
    centered on its visible width and only the last line sat left.
- Panel (left click): one card per installed source, click a card to
  expand it and list the pending packages with their version change
  (or commits behind for plugins/themes). Each card has its own Update
  button. `R` refreshes, `S` opens settings, Escape closes. So do the X
  in the upper right, the Close button at the bottom, and clicking outside
  the panel; it reopens on the next click either way.
- Left click: opens the panel. Middle click: forces an immediate
  recheck. Right click: opens the standalone settings window.

v1.7.0 tried a click-to-open panel (Panel.qml) for the list; the panel
window never mapped under the Nyxiri bar, and the hover list is what was
asked for, so the panel is gone as of v1.7.1. 2.0.0 brings the panel back
on the clock widget's proven pattern (a Panel.qml loaded through a
Loader, with a KeyboardPanel anchored to the badge).

## How it checks

`scripts/check_updates.py` (Python stdlib only) counts pending updates
and prints one JSON document:

```json
{"repos": [{"id", "name", "count", "installed", "packages", "..."}], "total": N}
```

- Repo: `checkupdates` (from pacman-contrib).
- AUR: `yay -Qua` (falls back to `paru -Qua`).
- Flatpak: `flatpak remote-ls --updates`.
- Mise: `mise outdated --json` (with `MISE_MINIMUM_RELEASE_AGE=0`, so the
  count matches what an update installs; falls back to plain
  `mise outdated` when the override is rejected).
- Shell plugins: git checkouts in `~/.config/omarchy/plugins` whose
  tracked branch is behind after a fetch (same approach as
  techspawn.updates).
- Themes: git themes from `omarchy-theme-extras` whose upstream branch is
  behind after a fetch.
- Omarchy: the omarchy/omarchy-dev package in the repo list, or a dev
  checkout (OMARCHY_PATH) behind its upstream.

Checking only counts; nothing here installs anything. The widget caches
the last scan to `~/.cache/omarchy/pizza.dirty.arch-updates.json` so the
bar renders it instantly at shell start with zero spawns.

Mise, plugin, and theme counting was inspired by
[techspawn.updates](https://github.com/RajShimpi/omarchy-updates) (MIT),
and the panel model by
[dizziee.system-updates](https://github.com/JJDizz1L/dizziee.system-updates)
(MIT).

## Install

```bash
omarchy plugin add https://github.com/Deoxizn/Arch-Updates.git --enable
command -v checkupdates || omarchy-pkg-add pacman-contrib
omarchy restart shell
```

If you installed the tarball manually first, remove
`~/.config/omarchy/plugins/pizza.dirty.arch-updates/` before the `plugin add`
so the clone lands clean. If the pill doesn't appear on the right,
place it with `omarchy bar put pizza.dirty.arch-updates --section right`.

## Update from 1.x

```bash
omarchy plugin update pizza.dirty.arch-updates --yes
omarchy restart shell
```

A shell restart is required: a plugin update alone does not reload QML,
so the old widget stays in memory until restart. The scanner is run via
`python3`, so there is no executable-bit problem on a plugin update.

2.0.0 replaces `check-updates.sh` with `scripts/check_updates.py` and
renames the check interval setting from `intervalMinutes` (minutes,
default 60) to `refreshIntervalSec` (seconds, default 1800). An old
`intervalMinutes` value is ignored; set the interval in the System Updater tab
or the standalone settings window.

## Settings

All settings live in the widget's bar layout entry and are edited from
the Nyxiri bar's settings window (System Updater tab) or the standalone settings
window (right-click the badge). Both write the same entry, so they stay
in sync.

| Key | Type | Default | Description |
|---|---|---|---|
| `refreshIntervalSec` | integer (300–7200) | 1800 | How often to check for updates (seconds) |
| `alwaysShow` | boolean | true | Keep icon visible even when no updates are available |
| `autoRefresh` | boolean | true | Check on the interval and once after startup. Off means checks run only when the panel is opened. |
| `checkAur` | boolean | true | Check AUR updates |
| `checkFlatpak` | boolean | true | Check Flatpak updates |
| `checkMise` | boolean | true | Check mise dev tools |
| `checkPlugins` | boolean | true | Check git shell plugins and themes |

## Notes

- First check can take a while: `checkupdates` syncs the package
  databases, the AUR query takes a moment, and plugin/theme checks fetch
  each git remote.
- If you renamed the plugin directory, update the script path in
  `BarWidget.qml` (`scriptPath`) to match.
- Designed for a horizontal (top/bottom) bar. The pill follows the bar
  font like any other widget, and the icons are Nerd Font glyphs, so the
  bar monospace font needs to be a Nerd Fonts v3 font. The package-variant
  icon lives in the supplementary plane (U+F03D6), so an older v2 Nerd
  Font will show the clean icon and a box for the pending icon.
- If your bar hides non-workspace widgets on a secondary monitor, this
  badge only appears on the monitors that show the full bar.
- The tooltip is a plain newline-separated string, so it only works
  because the bar renders tooltip text as multiline. If your bar shows
  it as one long line, the bar's tooltip is the problem, not this widget.
