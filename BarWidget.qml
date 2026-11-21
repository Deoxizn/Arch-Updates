import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import "Model.js" as Model

// Arch Updates 2.0.0: system-update indicator in the dizziee model, with
// the Omarchy and Arch updates combined into one section. Hover the pill
// and the tooltip lists every pending package vertically, per category,
// with its old -> new version, Noctalia-style. Left click opens a panel
// listing the pending packages per source with an update button each.
// Right click opens the standalone settings window. Middle click forces
// a refresh.
//
// The combined "Omarchy + Arch" section is the whole point of 2.0.0: the
// Arch update button in dizziee runs a bare pacman system upgrade (with
// the direct-pacman override env var set to get past Omarchy's guard),
// which bypasses the managed pipeline and, as its README says, a bare
// arch update is useless and can be harmful. There is one update action
// for the combined section and it runs `omarchy update`, the full managed
// pipeline (transcript, snapshot, keyrings, migrations, post-update
// hooks). A bare pacman system upgrade is never an update action here,
// not even with the override env var set. The other sources keep their
// own safe updater (AUR helper, flatpak update, mise up, omarchy plugin
// update).
//
// Nerd Font icons as QML escapes (ASCII, so they survive every transport
// layer): no updates nf-oct-package U+F487, updates nf-md-package_variant
// U+F03D6 (surrogate pair \udb80\udfd6). The second glyph lives in the
// supplementary plane, U+F03D6, so it needs a Nerd Fonts v3 font. An
// older v2 Nerd Font will show the first icon and tofu on the second.
// (Literal UTF-8 glyphs were tried first; the write path dropped them,
// so the escapes are what ships.)
//
// How it works: scripts/check_updates.py counts repo, AUR, Flatpak, mise,
// git shell plugins and git themes, and prints one JSON document:
//   {"repos": [{"id", "name", "count", "installed", "packages", ...}], "total": N}
// A package is {"name", "from", "to"} for a versioned update, or
// {"name", "behind"} for a git checkout. The widget polls it on a timer,
// shows the icon plus total as a badge, builds the hover tooltip from the
// detail lists (buildTooltip), and hands the repos to Panel.qml for the
// click-to-open list. The scanner is check-only: nothing there installs
// anything. Run via python3, so there is no executable-bit problem on a
// plugin update (git does not always preserve it).
//
// Settings live in the widget's bar layout entry (refreshIntervalSec,
// alwaysShow, autoRefresh, checkAur, checkFlatpak, checkMise,
// checkPlugins) and are edited from the bar's settings window System tab
// or the standalone SystemSettings window (right-click). Both write
// through setSystem(), which is the same updateEntryInline the bar's
// window uses, so the two stay in sync.
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
// was asked for, so the panel is gone as of v1.7.1. 2.0.0 brings the panel
// back on the clock widget's proven pattern: a Panel.qml loaded through
// a Loader, with a KeyboardPanel anchored to the badge.

BarWidget {
  id: root
  moduleName: "pizza.dirty.arch-updates"

  // Nerd Font icons as QML escapes (ASCII, so they survive every
  // transport layer): no updates nf-oct-package U+F487, updates
  // nf-md-package_variant U+F03D6 (surrogate pair \udb80\udfd6).
  property string noUpdatesIcon: "\uf487"
  property string updatesIcon: "\udb80\udfd6"

  // Rows shown per category in the tooltip before an "...and N more" line.
  // A 50-package tooltip would run off the bottom of the screen.
  property int tooltipRowsPerCategory: 20

  property var repos: []
  property int totalCount: 0
  property bool checked: false
  property string checkedAt: ""
  property string detailText: ""
  property string lastCacheText: ""

  // The combined Omarchy + Arch repo, for the tooltip and the panel.
  readonly property var systemRepo: {
    for (var i = 0; i < root.repos.length; i++) {
      if (root.repos[i].id === "system") return root.repos[i]
    }
    return null
  }

  readonly property bool hasUpdates: root.totalCount > 0

  // `omarchy bar set` stores a bare value as a JSON string unless --json
  // is used, so a boolean read back from shell.json can be "false".
  // Coerce it instead of treating every non-false value as true.
  function boolValue(value, fallback) {
    if (value === undefined || value === null) return fallback
    if (typeof value === "string") return value !== "false" && value !== "0" && value !== ""
    return value !== false
  }

  function boolSetting(name, fallback) {
    return root.boolValue(setting(name, fallback), fallback)
  }

  readonly property int refreshIntervalSec: {
    var value = Number(setting("refreshIntervalSec", 1800))
    if (!isFinite(value)) value = 1800
    return Math.round(Math.max(300, Math.min(7200, value)))
  }
  readonly property bool alwaysShow: root.boolSetting("alwaysShow", true)
  readonly property bool autoRefresh: root.boolSetting("autoRefresh", true)

  // Per-source toggles, passed to the scanner as --no-* flags. A source
  // that is off is skipped entirely and reported installed=false.
  function scannerArgs() {
    var args = []
    if (!root.boolSetting("checkAur", true)) args.push("--no-aur")
    if (!root.boolSetting("checkFlatpak", true)) args.push("--no-flatpak")
    if (!root.boolSetting("checkMise", true)) args.push("--no-mise")
    if (!root.boolSetting("checkPlugins", true)) args.push("--no-plugins")
    return args
  }

  // Last-good scan result on disk: the bar renders it instantly at shell
  // start with zero spawns, and the first live scan replaces it. The file
  // lives in ~/.cache/omarchy, which already exists.
  readonly property string cachePath: {
    var base = Quickshell.env("XDG_CACHE_HOME")
    if (!base) base = Quickshell.env("HOME") + "/.cache"
    return base + "/omarchy/pizza.dirty.arch-updates.json"
  }

  readonly property string scriptPath: (Quickshell.env("HOME") || "") + "/.config/omarchy/plugins/pizza.dirty.arch-updates/scripts/check_updates.py"

  function runCheck() {
    if (checkProc.running) return
    checkProc.command = ["python3", root.scriptPath].concat(root.scannerArgs())
    checkProc.running = true
  }

  function updateRepos(raw) {
    var text = String(raw || "")
    var parsed = Model.parseRepoList(text)
    root.repos = parsed.repos
    root.totalCount = parsed.total
    root.checkedAt = new Date().toLocaleTimeString()
    root.checked = true
    root.detailText = root.buildTooltip()
    // One small disk write per changed result, not per poll; the
    // text !== lastCacheText guard also makes a write->load echo a no-op.
    if (text !== "" && text !== root.lastCacheText) {
      root.lastCacheText = text
      try { cacheFile.setText(text) } catch (e) {}
    }
  }

  // Build the hover tooltip from the repos. All five sections are always
  // shown, even at (0), rows "  name old → new" under the ones that have
  // items (plugins/themes show "  name (N commits behind)" instead). Lines
  // are padded with no-break spaces to the longest line's length so the
  // bar's centered tooltip reads as left-aligned (see header comment for
  // why plain spaces failed). Stored in detailText, not computed in the
  // binding, so it only changes when a check lands.
  function buildTooltip() {
    if (!root.hasUpdates) return "No updates pending · Click for details"
    var lines = [root.totalCount + " updates pending"]
    var sections = [
      { id: "system", title: "Omarchy + Arch", versioned: true },
      { id: "aur", title: "AUR", versioned: true },
      { id: "flatpak", title: "Flatpak", versioned: true },
      { id: "plugins", title: "Plugins & Themes", versioned: false },
      { id: "mise", title: "mise", versioned: true }
    ]
    for (var s = 0; s < sections.length; s++) {
      var section = sections[s]
      var repo = null
      for (var r = 0; r < root.repos.length; r++) {
        if (root.repos[r].id === section.id) { repo = root.repos[r]; break }
      }
      if (!repo || repo.installed !== true) continue
      lines.push(section.title + " (" + repo.count + ")")
      var list = repo.packages || []
      var shown = Math.min(list.length, root.tooltipRowsPerCategory)
      for (var i = 0; i < shown; i++) {
        var entry = list[i]
        if (section.versioned) lines.push("  " + entry.name + " " + entry.from + " → " + entry.to)
        else lines.push("  " + entry.name + " (" + entry.behind + " commits behind)")
      }
      if (list.length > shown) lines.push("  …and " + (list.length - shown) + " more")
    }
    lines.push("Click for details")
    var maxLen = 0
    for (var p = 0; p < lines.length; p++) if (lines[p].length > maxLen) maxLen = lines[p].length
    for (var q = 0; q < lines.length; q++) {
      while (lines[q].length < maxLen) lines[q] += "\u00A0"
    }
    return lines.join("\n")
  }

  // Update commands are owned by this widget, not by the scan output.
  // The scanner is user-writable output, so a command read back from it
  // must never reach a shell. Model.updateCommandFor rebuilds the command
  // from the repo id (and, for AUR, the helper as a fixed enum).
  function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'"
  }

  function updateRepo(id) {
    var repo = null
    for (var i = 0; i < root.repos.length; i++) {
      if (root.repos[i].id === id) { repo = root.repos[i]; break }
    }
    var cmd = Model.updateCommandFor(repo)
    if (!cmd) return
    // After an update starts, rescan on a fast poll until the updater
    // terminal is done: the numbers go stale the moment packages land.
    root.pendingRepo = id
    root.fastPollCount = 0
    root.fastPollActive = true
    root.fastPollTimer.interval = 10000
    root.fastPollTimer.restart()
    if (root.bar) root.bar.run("omarchy-launch-terminal bash -c " + root.shellQuote(cmd))
  }

  property string pendingRepo: ""
  property bool fastPollActive: false
  property int fastPollCount: 0
  readonly property int maxFastPolls: 30

  function stopFastPoll() {
    root.pendingRepo = ""
    root.fastPollActive = false
    root.fastPollTimer.stop()
    root.fastPollTimer.interval = 10000
    root.runCheck()
  }

  // Write the system settings the same way the bar's settings window
  // does: updateEntryInline replaces rather than merges, so the existing
  // settings are copied first and the patch applied on top. The shell.json
  // write comes back through the bar as the same values, so the bar's
  // window and the standalone popup stay in sync: both write to the same
  // layout entry.
  function setSystem(patch) {
    if (!root.bar || !root.bar.shell || typeof root.bar.shell.updateEntryInline !== "function") return false
    var entry = { id: root.moduleName }
    var current = root.settings || {}
    for (var key in current) if (key !== "id") entry[key] = current[key]
    for (var patchName in patch) entry[patchName] = patch[patchName]
    root.settings = entry
    return root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // Standalone settings: right-click the badge opens the SystemSettings
  // window. It is the same controls as the bar's settings window System
  // tab, so the plugin is usable on its own (stock bar, no Nyxiri bar),
  // where there is no bar settings window.
  property bool settingsOpen: false

  function toggleSettings() {
    root.settingsOpen = !root.settingsOpen
  }

  // The update-list panel, on the clock widget's proven pattern: a
  // Panel.qml loaded through a Loader, with a KeyboardPanel anchored to
  // the badge. The bar tracks this widget, not the nested panel.
  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = badge
    if ("hostWidget" in target) target.hostWidget = root
  }

  readonly property bool panelOpened: panelLoader.item ? panelLoader.item.opened === true : false

  function openPanel() {
    if (panelLoader.item) panelLoader.item.open()
    root.runCheck()
  }

  function closePanel() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (!panelLoader.item) return
    if (panelLoader.item.opened) panelLoader.item.close()
    else { panelLoader.item.open(); root.runCheck() }
  }

  implicitWidth: badge.implicitWidth
  implicitHeight: badge.implicitHeight
  visible: root.totalCount > 0 || root.alwaysShow

  Process {
    id: checkProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateRepos(text)
    }
    stderr: StdioCollector {
      id: checkErr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        var detail = String(checkErr.text || "").replace(/\s+/g, " ").trim()
        console.warn("arch-updates: scanner exited with code " + exitCode
          + (detail !== "" ? ": " + detail : ""))
      }
    }
  }

  FileView {
    id: cacheFile
    path: root.cachePath
    watchChanges: false
    printErrors: false
    onLoaded: {
      root.lastCacheText = String(text() || "")
      root.updateRepos(text())
    }
  }

  Timer {
    id: checkTimer
    interval: root.refreshIntervalSec * 1000
    running: root.autoRefresh
    repeat: true
    onTriggered: root.runCheck()
  }

  Timer {
    id: fastPollTimer
    interval: 10000
    running: false
    repeat: true
    onTriggered: {
      root.runCheck()
      root.fastPollCount++
      // Back off while the updater terminal stays open: early polls catch
      // a quick update, later ones just keep the numbers from going stale.
      if (root.fastPollCount >= 5) fastPollTimer.interval = 30000
      if (root.fastPollCount >= root.maxFastPolls) root.stopFastPoll()
    }
  }

  Component.onCompleted: root.runCheck()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  // The standalone settings window, one per bar surface. It opens on
  // right-click and closes from its own Close button or Escape.
  SystemSettings {
    bar: root.bar
    hostWidget: root
    visible: root.settingsOpen
    screen: {
      var window = root.QsWindow.window
      return window ? window.screen : null
    }
  }

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
      if (button === Qt.RightButton) { root.toggleSettings(); return }
      if (button === Qt.MiddleButton) { root.runCheck(); return }
      root.togglePanel()
    }
  }
}
