# Arch Updates

Icon badge for the Omarchy quattro bar, with a Noctalia-style panel
listing every pending update. Package icon when clean (dimmed),
package-variant icon plus `N` when N updates are pending.

## What it shows

- Bar pill: package icon (nf-oct-package, U+F487) when up to date (dimmed), package-variant icon (nf-md-package_variant, U+F03D6) plus `N` when N updates are pending.
- Tooltip: the counts breakdown, e.g. `Repo: 8 · AUR: 4 · Mise: 2 · Plugins: 1 · Themes: 0 · Click for list, right-click to update`.
- Panel (left click): one collapsible section per category, listing each
  pending item vertically with its version change:
  - Repo / AUR / Mise: `name` on the left, `old-version → new-version` on the right.
  - Plugins / Themes: `name` on the left, `N commits behind` on the right
    (a git checkout has no version to show).
  - Click a section header to collapse/expand it. Long lists scroll;
    the panel caps at about 430px tall.
  - Header shows the total, the counts, and the checked time. Buttons:
    `Update all`, `Refresh`, `Close`.
- Left click: opens/closes the panel.
- Middle click: forces an immediate recheck.
- Right click: runs `omarchy update` straight away (the old left-click
  behaviour, kept as an escape hatch).

## How it checks

`check-updates.sh` counts pending updates and prints
`<total> <repo> <aur> <mise> <plugins> <themes>` on line 1, then one
tab-separated detail line per pending item:

```
repo<TAB><name><TAB><old-version><TAB><new-version>
aur<TAB><name><TAB><old-version><TAB><new-version>
mise<TAB><name><TAB><current><TAB><latest>
plugin<TAB><name><TAB><commits-behind>
theme<TAB><name><TAB><commits-behind>
```

- Repo: `checkupdates` (from pacman-contrib).
- AUR: `yay -Qua` (falls back to `paru -Qua`).
- Mise: `mise outdated --json` (with `MISE_MINIMUM_RELEASE_AGE=0`, so the
  count matches what an update installs; falls back to plain `mise outdated`
  when `jq` is not installed).
- Shell plugins: git checkouts in `~/.config/omarchy/plugins` whose tracked
  branch is behind after a fetch (same approach as techspawn.updates).
- Themes: git themes from `omarchy-theme-extras` whose upstream branch is
  behind after a fetch.

Checking only counts; nothing here installs anything. `Update all` runs
`omarchy update` via `omarchy-launch-floating-terminal-with-presentation`,
which covers system, AUR, and mise. Shell plugins and themes are counted
here but updated separately (`omarchy plugin update`, theme git pull), so
the badge can still show those after an `omarchy update` until they are
updated.

Mise, plugin, and theme counting was inspired by
[techspawn.updates](https://github.com/RajShimpi/omarchy-updates) (MIT).

## Install

```bash
omarchy plugin add https://github.com/Deoxizn/Arch-Updates.git --enable
command -v checkupdates || omarchy-pkg-add pacman-contrib
omarchy restart shell
```

If you installed the tarball manually first, remove
`~/.config/omarchy/plugins/devi.arch-updates/` before the `plugin add`
so the clone lands clean. If the pill doesn't appear on the right,
place it with `omarchy bar put devi.arch-updates --section right`.

## Update from 1.6.x

```bash
omarchy plugin update devi.arch-updates --yes
omarchy restart shell
```

A shell restart is required: a plugin update alone does not reload QML,
so the old widget (no panel, left-click updates) stays in memory until
restart. The script is run via `bash`, so do not `chmod +x` it, a
mode-only change blocks the plugin update fast-forward.

## Settings

Check interval: edit `intervalMinutes` at the top of `BarWidget.qml`
(minutes between checks, default 60), then restart the shell if it does
not pick it up live.

Update command: `updateCommand` at the top of `BarWidget.qml` runs
`omarchy update` via Omarchy's floating-terminal presentation wrapper;
edit it to pin a specific terminal (e.g. `kitty omarchy update`).

## Notes

- First check can take a while: `checkupdates` syncs the package
  databases, the AUR query takes a moment, and plugin/theme checks fetch
  each git remote.
- If you renamed the plugin directory, update the script path in
  `BarWidget.qml` (`checkProc.command`) to match.
- Designed for a horizontal (top/bottom) bar. The pill follows the bar
  font like any other widget, and the icons are Nerd Font glyphs, so the
  bar monospace font needs to be a Nerd Fonts v3 font. The package-variant
  icon lives in the supplementary plane (U+F03D6), so an older v2 Nerd
  Font will show the clean icon and a box for the pending icon.
- If your bar hides non-workspace widgets on a secondary monitor, this
  badge only appears on the monitors that show the full bar.
- Panel plumbing follows the stock Omarchy weather/clock pattern
  (`BarWidget.qml` + `Panel.qml`, Loader, `injectPanel`, open/close/toggle
  forwarded). The panel is not a second manifest kind.
