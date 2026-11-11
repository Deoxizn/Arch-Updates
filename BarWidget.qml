import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

// Arch Updates: icon badge for pending updates, plus a Noctalia-style
// panel listing every pending package vertically, per category, with
// its old -> new version. No updates: nf-oct-package. Updates:
// nf-md-package_variant + count.
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
// keeps the counts in the tooltip, and hands the detail lists to Panel.qml.
//
// Clicks: left toggles the panel, middle forces a refresh, right runs
// the updater straight away (the old left-click behaviour, kept as an
// escape hatch). The panel's Update button runs the same command.
//
// Panel plumbing follows the stock Omarchy weather/clock pattern
// (BarWidget + Panel.qml, Loader, injectPanel, open/close/toggle/opened
// forwarded so the bar's popout routing and Nyxiri's findPanelWidget
// both see it). The panel is NOT a second manifest kind.
//
// Settings: edit intervalMinutes below (minutes between checks). Default 60.
// If you rename this plugin, update the script path in checkProc.command.

BarWidget {
  id: root
  moduleName: "devi.arch-updates"

  // Command run by the panel's Update button and by right-click. Uses
  // Omarchy's presentation wrapper, same as the stock SystemUpdate widget:
  // it shows the Omarchy logo, runs the update, then waits for a keypress
  // on Done/Failed, so the terminal stays open after a clean run instead
  // of closing the second the update exits. Plain xdg-terminal-exec closed
  // instantly on success, which looked like a crash at the AUR stage
  // (the last step).
  // Note: omarchy update covers system, AUR and mise. Shell plugins and
  // themes are counted here but updated separately (omarchy plugin update,
  // theme git pull), so the badge can still show those after an update.
  property string updateCommand: "omarchy-launch-floating-terminal-with-presentation omarchy update"

  // Minutes between update checks. Change this number to suit.
  property int intervalMinutes: 60

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

  // Detail lists, one entry per pending item. Versioned entries are
  // { name, oldVersion, newVersion }; plugin/theme entries are
  // { name, behind } (no version exists for a git checkout).
  property var repoList: []
  property var aurList: []
  property var miseList: []
  property var pluginsList: []
  property var themesList: []

  readonly property bool hasUpdates: root.totalCount > 0

  // Panel lifecycle, forwarded so the bar routes popouts through the
  // widget in its slot, not the nested panel item.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = badge
    if ("hostWidget" in target) target.hostWidget = root
  }

  function runUpdate() {
    root.close()
    if (root.bar) root.bar.run(root.updateCommand)
  }

  implicitWidth: badge.implicitWidth
  implicitHeight: badge.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  function runCheck() {
    if (!checkProc.running) checkProc.running = true
  }

  // Parse the script output: line 1 is the counts, the rest are
  // tab-separated detail lines. An old script that prints counts only
  // still parses (lists stay empty, the panel shows counts only).
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
  }

  Process {
    id: checkProc
    // Run via bash so the check works even if the script loses its
    // executable bit on a plugin update (git does not always preserve it).
    command: ["bash", Quickshell.env("HOME") + "/.config/omarchy/plugins/devi.arch-updates/check-updates.sh"]
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

  Loader {
    id: panelLoader
    active: true
    visible: false
    source: Qt.resolvedUrl("Panel.qml")
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
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
    tooltipText: !root.checked ? "Checking for updates…"
      : root.hasUpdates ? "Repo: " + root.repoCount + " · AUR: " + root.aurCount + " · Mise: " + root.miseCount + " · Plugins: " + root.pluginsCount + " · Themes: " + root.themesCount + " · Click for list, right-click to update"
      : "No updates pending · Click for list"
    onPressed: function(button) {
      if (button === Qt.LeftButton) {
        root.toggle()
      } else if (button === Qt.MiddleButton) {
        root.runCheck()
      } else if (button === Qt.RightButton) {
        root.runUpdate()
      }
    }
  }
}
