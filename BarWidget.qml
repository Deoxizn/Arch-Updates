import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

// Arch Updates: count badge for pending Arch repo + AUR updates.
// Stellarchy-style: dim when clean, count badge when updates are waiting.
//
// How it works: check-updates.sh runs checkupdates (repo) and yay/paru -Qua
// (AUR) and prints "<total> <repo> <aur>". This widget polls it on a timer,
// shows the total as a badge, and puts the breakdown in the tooltip.
// Left click opens the updater, middle click forces a refresh.
//
// Settings: edit intervalMinutes below (minutes between checks). Default 60.
// If you rename this plugin, update the script path in checkProc.command.

BarWidget {
  id: root
  moduleName: "devi.arch-updates"

  // Command run on left click. Change it if you prefer another terminal.
  property string updateCommand: "kitty omarchy update"

  // Minutes between update checks. Change this number to suit.
  property int intervalMinutes: 60

  property int totalCount: 0
  property int repoCount: 0
  property int aurCount: 0
  property bool checked: false

  readonly property bool hasUpdates: root.totalCount > 0

  implicitWidth: badge.implicitWidth
  implicitHeight: badge.implicitHeight

  function runCheck() {
    if (!checkProc.running) checkProc.running = true
  }

  Process {
    id: checkProc
    command: [Quickshell.env("HOME") + "/.config/omarchy/plugins/devi.arch-updates/check-updates.sh"]
    stdout: StdioCollector {
      onStreamFinished: {
        var parts = String(text || "").trim().split(/\s+/)
        if (parts.length !== 3) return
        var total = parseInt(parts[0], 10)
        var repo = parseInt(parts[1], 10)
        var aur = parseInt(parts[2], 10)
        if (isNaN(total) || isNaN(repo) || isNaN(aur)) return
        root.totalCount = total
        root.repoCount = repo
        root.aurCount = aur
        root.checked = true
      }
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
    text: root.hasUpdates ? "↓ " + root.totalCount : "↓"
    opacity: root.hasUpdates ? 1 : 0.45
    horizontalMargin: 8
    verticalPadding: 6
    fixedHeight: root.barSize
    tooltipText: !root.checked ? "Checking for updates…"
      : root.hasUpdates ? "Repo: " + root.repoCount + " · AUR: " + root.aurCount + " · Click to update"
      : "No updates pending · Click to update"
    onPressed: function(button) {
      if (button === Qt.LeftButton) {
        if (root.bar) root.bar.run(root.updateCommand)
      } else if (button === Qt.MiddleButton) {
        root.runCheck()
      }
    }
  }
}
