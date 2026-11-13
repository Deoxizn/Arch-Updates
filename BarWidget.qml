import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

// Arch Updates: icon badge for pending updates. Hover the pill and the
// tooltip lists every pending package vertically, per category, with
// its old -> new version, Noctalia-style. No updates: nf-oct-package.
// Updates: nf-md-package_variant + count.
//
// Why this failed on Caelestia and should work on Omarchy:
// Caelestia draws bar icons with Material Symbols Rounded and bar text
// with Rubik, neither of which contains Nerd Font private-use glyphs, so
// a Nerd glyph pasted into a Caelestia module had no font to fall back
// to. Omarchy's bar text uses the system monospace font, and upstream
// Omarchy's monospace is a Nerd Font, so the same glyphs have a font
// to resolve against. The second glyph is the catch: it lives in the
// supplementary plane, U+F03D6, so it needs a Nerd Fonts v3 font. An
// older v2 Nerd Font will show the first icon and tofu on the second.
// Test on the live bar before pushing: if the second icon is a box,
// the font is the problem, not the codes.
//
// Glyphs are written literally here on purpose. Writing the second one
// as "\udb80\udfd6" is also correct QML, but that escape has been
// mangled by JSON/shell layers before, while a literal UTF-8 glyph
// survives a plain file copy. Codes, for reference:
//   no updates: nf-oct-package, U+F487, \uf487
//   updates:    nf-md-package_variant, U+F03D6, \udb80\udfd6
//
// How it works: check-updates.sh counts repo (checkupdates), AUR
// (yay/paru -Qua), mise dev tools (mise outdated), git shell plugins
// (tracked branch behind) and git themes (upstream behind), prints
// "<total> <repo> <aur> <mise> <plugins> <themes>" on line 1, then one
// tab-separated detail line per pending item:
//   repo/aur/mise: "<cat>\t<name>\t<old>\t<new>"
//   plugin/theme:  "<cat>\t<name>\t<commits-behind>"
// This widget polls it on a timer, shows the icon plus total as a badge,
// and builds the hover tooltip from the detail lists (buildTooltip).
// Left click opens the updater, middle click forces a refresh.
//
// Tooltip note: the bubble is rendered by the bar, not this widget, and
// the bar centers every line (AlignHCenter, monospace bar font). A plain
// \n-separated string is all the widget can hand it. buildTooltip works
// around the centering by padding every line to the longest line's
// length: equal-length lines center to the same left edge, which reads
// as left-aligned. That only holds because the bar font is monospace;
// in a proportional font the padding would not line up.
// Padding is U+00A0 no-break space, written as the "\u00A0" escape so it
// stays visible in source. Plain spaces did NOT work (v1.7.2): Qt's text
// layout trims trailing spaces when measuring centered lines, so every
// line centered on its visible width and only the last line sat left.
// A no-break space is not a breakable space, so it should survive the
// width measurement. If it does not, the next thing to try is U+2800
// braille blank, which is not whitespace at all.
// v1.7.0 tried a click-to-open panel (Panel.qml) instead; the panel
// window never mapped under the Nyxiri bar, and the hover list is what
// was asked for, so the panel is gone as of v1.7.1.
//
// Settings: edit intervalMinutes below (minutes between checks). Default 60.
// If you rename this plugin, update the script path in checkProc.command.

BarWidget {
  id: root
  moduleName: "pizza.dirty.arch-updates"

  // Command run on left click. Uses Omarchy's presentation wrapper, same
  // as the stock SystemUpdate widget: it shows the Omarchy logo, runs the
  // update, then waits for a keypress on Done/Failed, so the terminal
  // stays open after a clean run instead of closing the second the
  // update exits. Plain xdg-terminal-exec closed instantly on success,
  // which looked like a crash at the AUR stage (the last step).
  // Note: omarchy update covers system, AUR and mise. Shell plugins and
  // themes are counted here but updated separately (omarchy plugin update,
  // theme git pull), so the badge can still show those after an update.
  property string updateCommand: "omarchy-launch-floating-terminal-with-presentation omarchy update"

  // Minutes between update checks. Change this number to suit.
  property int intervalMinutes: 60

  // Rows shown per category in the tooltip before an "...and N more" line.
  // A 50-package tooltip would run off the bottom of the screen.
  property int tooltipRowsPerCategory: 20

  // Nerd Font icons, literal UTF-8 glyphs, see header comment.
  property string noUpdatesIcon: ""
  property string updatesIcon: "󰏖"

  property int totalCount: 0
  property int repoCount: 0
  property int aurCount: 0
  property int miseCount: 0
  property int pluginsCount: 0
  property int themesCount: 0
  property bool checked: false
  property string checkedAt: ""
  property string detailText: ""

  // Detail lists, one entry per pending item. Versioned entries are
  // { name, oldVersion, newVersion }; plugin/theme entries are
  // { name, behind } (no version exists for a git checkout).
  property var repoList: []
  property var aurList: []
  property var miseList: []
  property var pluginsList: []
  property var themesList: []

  readonly property bool hasUpdates: root.totalCount > 0

  implicitWidth: badge.implicitWidth
  implicitHeight: badge.implicitHeight

  function runCheck() {
    if (!checkProc.running) checkProc.running = true
  }

  // Build the hover tooltip from the detail lists. All five sections are
  // always shown, even at (0), rows "  name old → new" under the ones
  // that have items (plugins/themes show "  name (N commits behind)"
  // instead). An old script that prints counts only leaves every list
  // empty, so that just shows the five headers with counts and no rows.
  // Lines are padded with no-break spaces to the longest line's length
  // so the bar's centered tooltip reads as left-aligned (see header
  // comment for why plain spaces failed).
  // Stored in detailText, not computed in the binding, so it only
  // changes when a check lands.
  function buildTooltip() {
    if (!root.hasUpdates) return "No updates pending · Click to update"
    var lines = [root.totalCount + " updates pending"]
    var sections = [
      { title: "Repo", count: root.repoCount, list: root.repoList, versioned: true },
      { title: "AUR", count: root.aurCount, list: root.aurList, versioned: true },
      { title: "Mise", count: root.miseCount, list: root.miseList, versioned: true },
      { title: "Plugins", count: root.pluginsCount, list: root.pluginsList, versioned: false },
      { title: "Themes", count: root.themesCount, list: root.themesList, versioned: false }
    ]
    for (var s = 0; s < sections.length; s++) {
      var section = sections[s]
      lines.push(section.title + " (" + section.count + ")")
      var shown = Math.min(section.list.length, root.tooltipRowsPerCategory)
      for (var i = 0; i < shown; i++) {
        var entry = section.list[i]
        if (section.versioned) lines.push("  " + entry.name + " " + entry.oldVersion + " → " + entry.newVersion)
        else lines.push("  " + entry.name + " (" + entry.behind + " commits behind)")
      }
      if (section.list.length > shown) lines.push("  …and " + (section.list.length - shown) + " more")
    }
    lines.push("Click to update")
    var maxLen = 0
    for (var p = 0; p < lines.length; p++) if (lines[p].length > maxLen) maxLen = lines[p].length
    for (var q = 0; q < lines.length; q++) {
      while (lines[q].length < maxLen) lines[q] += "\u00A0"
    }
    return lines.join("\n")
  }

  // Parse the script output: line 1 is the counts, the rest are
  // tab-separated detail lines.
  function parseCheck(text) {
    var lines = String(text || "").trim().split("\n")
    if (lines.length === 0 || lines[0] === "") return
    var parts = lines[0].trim().split(/\s+/)
    if (parts.length !== 3 && parts.length !== 6) return
    var total = parseInt(parts[0], 10)
    var repo = parseInt(parts[1], 10)
    var aur = parseInt(parts[2], 10)
    var mise = parts.length === 6 ? parseInt(parts[3], 10) : 0
    var plugins = parts.length === 6 ? parseInt(parts[4], 10) : 0
    var themes = parts.length === 6 ? parseInt(parts[5], 10) : 0
    if (isNaN(total) || isNaN(repo) || isNaN(aur) || isNaN(mise) || isNaN(plugins) || isNaN(themes)) return
    var repoList = []
    var aurList = []
    var miseList = []
    var pluginsList = []
    var themesList = []
    for (var i = 1; i < lines.length; i++) {
      var fields = lines[i].split("\t")
      if (fields.length < 3) continue
      var cat = fields[0]
      if ((cat === "repo" || cat === "aur" || cat === "mise") && fields.length >= 4) {
        var entry = { name: fields[1], oldVersion: fields[2], newVersion: fields[3] }
        if (cat === "repo") repoList.push(entry)
        else if (cat === "aur") aurList.push(entry)
        else miseList.push(entry)
      } else if ((cat === "plugin" || cat === "theme") && fields.length >= 3) {
        var behind = parseInt(fields[2], 10)
        var gitEntry = { name: fields[1], behind: isNaN(behind) ? 0 : behind }
        if (cat === "plugin") pluginsList.push(gitEntry)
        else themesList.push(gitEntry)
      }
    }
    root.totalCount = total
    root.repoCount = repo
    root.aurCount = aur
    root.miseCount = mise
    root.pluginsCount = plugins
    root.themesCount = themes
    root.repoList = repoList
    root.aurList = aurList
    root.miseList = miseList
    root.pluginsList = pluginsList
    root.themesList = themesList
    root.checkedAt = new Date().toLocaleTimeString()
    root.checked = true
    root.detailText = root.buildTooltip()
  }

  Process {
    id: checkProc
    // Run via bash so the check works even if the script loses its
    // executable bit on a plugin update (git does not always preserve it).
    command: ["bash", Quickshell.env("HOME") + "/.config/omarchy/plugins/pizza.dirty.arch-updates/check-updates.sh"]
    stdout: StdioCollector {
      onStreamFinished: root.parseCheck(text)
    }
  }

  Timer {
    id: checkTimer
    interval: root.intervalMinutes * 60000
    running: true
    repeat: true
    onTriggered: root.runCheck()
  }

  Component.onCompleted: root.runCheck()

  WidgetButton {
    id: badge
    bar: root.bar
    text: root.hasUpdates ? root.updatesIcon + " " + root.totalCount : root.noUpdatesIcon
    opacity: root.hasUpdates ? 1 : 0.45
    horizontalMargin: 8
    verticalPadding: 6
    fixedHeight: root.barSize
    tooltipText: !root.checked ? "Checking for updates…" : root.detailText
    onPressed: function(button) {
      if (button === Qt.LeftButton) {
        if (root.bar) root.bar.run(root.updateCommand)
      } else if (button === Qt.MiddleButton) {
        root.runCheck()
      }
    }
  }
}
