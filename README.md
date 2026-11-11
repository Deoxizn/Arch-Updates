# Arch Updates

Icon badge for the Omarchy quattro bar. Package icon when clean (dimmed),
package-variant icon plus `N` when N updates are pending. Hover the pill
and the tooltip lists every pending update vertically, per category,
Noctalia-style, instead of just a number.

## What it shows

- Bar pill: package icon (nf-oct-package, U+F487) when up to date (dimmed), package-variant icon (nf-md-package_variant, U+F03D6) plus `N` when N updates are pending.
- Tooltip (hover): one section per category with pending items, listing
  each vertically with its version change:
  - Repo / AUR / Mise: `name old-version → new-version`.
  - Plugins / Themes: `name (N commits behind)` (a git checkout has no
    version to show).
  - Categories with nothing pending are skipped. Each category lists at
    most 20 rows, then `…and N more`, so a huge update list does not run
    the tooltip off the bottom of the screen.
  - The tooltip bubble is rendered by the bar, so its lines are centered,
    not left-aligned. That is the bar's doing, not this widget's.
- Left click: runs `omarchy update` (the terminal lists what it is about
  to install, same as before).
- Middle click: forces an immediate recheck.

v1.7.0 tried a click-to-open panel (Panel.qml) for the list; the panel
window never mapped under the Nyxiri bar, and the hover list is what was
asked for, so the panel is gone as of v1.7.1.

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

Checking only counts; nothing here installs anything. Left click runs
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

## Update from 1.6.x / 1.7.0

```bash
omarchy plugin update devi.arch-updates --yes
omarchy restart shell
```

A shell restart is required: a plugin update alone does not reload QML,
so the old widget stays in memory until restart. The script is run via
`bash`, so do not `chmod +x` it, a mode-only change blocks the plugin
update fast-forward.

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
- The tooltip is a plain newline-separated string, so it only works
  because the bar renders tooltip text as multiline. If your bar shows
  it as one long line, the bar's tooltip is the problem, not this widget.
