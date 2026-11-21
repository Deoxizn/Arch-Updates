import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// The update-list panel: the pending packages per source, with an update
// button each, opened by left-clicking the badge. BarWidget.qml owns the
// scan results and hands this panel the badge to anchor against.
//
// The combined "Omarchy + Arch" section has one update action and it runs
// `omarchy update`, the full managed pipeline. A bare `pacman -Syu` is
// never an update action here, not even with OMARCHY_ALLOW_DIRECT_PACMAN=1.
// The other sources keep their own safe updater (AUR helper, flatpak
// update, mise up, omarchy plugin update). Update commands are rebuilt
// here from the repo id (Model.updateCommandFor), never read back from
// the scan output, which is user-writable.
//
// BarWidget.qml owns the bar label and hands this panel the button to
// anchor against, on the clock widget's proven pattern: a Loader in
// BarWidget.qml loads this file, and injectPanel() sets anchorItem and
// hostWidget. The bar tracks the widget mounted in its slot, not this
// nested panel, so barIdentity is the host widget.
Panel {
  id: root
  moduleName: "pizza.dirty.arch-updates"
  ipcTarget: "pizza.dirty.arch-updates"
  manageIpc: false

  property var anchorItem: null

  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // Rows the user has expanded to reveal their pending packages, keyed by
  // repo id. A plain object keeps multiple rows open at once.
  property var expandedRepos: ({})

  function isRepoExpanded(id) {
    return expandedRepos[id] === true
  }

  function toggleRepo(id) {
    var next = {}
    for (var key in expandedRepos) next[key] = expandedRepos[key]
    next[id] = !next[id]
    expandedRepos = next
  }

  // Only sources that are actually installed. A source the scanner
  // reported installed=false (missing tool, or turned off in settings)
  // has no row.
  readonly property var installedRepos: {
    var filtered = []
    var repos = hostWidget ? hostWidget.repos : []
    for (var i = 0; i < repos.length; i++) {
      if (repos[i].installed === true) filtered.push(repos[i])
    }
    return filtered
  }

  readonly property color fg: root.bar ? root.bar.foreground : Commons.Color.foreground
  readonly property color dim: Qt.darker(fg, 1.45)
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : "JetBrainsMono Nerd Font"

  function fmtInt(value) {
    return Commons.I18n.formatNumber(Math.floor(Number(value) || 0))
  }

  function repoCount(repo) {
    var count = Number(repo && repo.count)
    return isFinite(count) && count > 0 ? Math.floor(count) : 0
  }

  function repoHasUpdateCommand(repo) {
    return Model.updateCommandFor(repo) !== ""
  }

  function updateRepo(id) {
    if (hostWidget) hostWidget.updateRepo(id)
    root.close()
  }

  function openSettings() {
    root.close()
    if (hostWidget) hostWidget.toggleSettings()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(560))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTextKey: function(t) {
        if (t === "r" || t === "R") { if (hostWidget) hostWidget.runCheck() }
        if (t === "s" || t === "S") root.openSettings()
      }

      ColumnLayout {
        id: contentColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        RowLayout {
          Layout.fillWidth: true
          spacing: 8

          Text {
            textFormat: Text.PlainText
            text: "System Updates"
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
          }

          Button {
            text: "Settings"
            foreground: root.fg
            tooltipText: "Open system settings"
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            onClicked: root.openSettings()
          }

          Button {
            text: "Refresh"
            foreground: root.fg
            tooltipText: "Check for updates now"
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            onClicked: { if (hostWidget) hostWidget.runCheck() }
          }
        }

        PanelSeparator {
          Layout.fillWidth: true
          foreground: root.fg
        }

        Repeater {
          model: root.opened ? root.installedRepos : []

          delegate: BorderSurface {
            id: repoCard
            required property var modelData

            readonly property var packages: modelData.packages || []
            readonly property bool expandable: packages.length > 0
            readonly property bool expanded: root.isRepoExpanded(modelData.id)
            readonly property int count: root.repoCount(modelData)
            readonly property bool hasCommand: root.repoHasUpdateCommand(modelData)

            Layout.fillWidth: true
            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.055)
            borderSpec: Border.flat(Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08), 1)
            radius: Style.cornerRadius
            padding: Style.space(10)

            implicitHeight: repoColumn.implicitHeight + contentTopInset + contentBottomInset

            ColumnLayout {
              id: repoColumn
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.leftMargin: repoCard.contentLeftInset
              anchors.rightMargin: repoCard.contentRightInset
              anchors.topMargin: repoCard.contentTopInset
              spacing: Style.space(6)

              // Header. The MouseArea sits under the row, so clicks on the
              // text or whitespace toggle the row while the Update button
              // keeps its own clicks.
              Item {
                Layout.fillWidth: true
                implicitHeight: repoRow.implicitHeight

                MouseArea {
                  anchors.fill: parent
                  enabled: repoCard.expandable
                  hoverEnabled: repoCard.expandable
                  cursorShape: repoCard.expandable ? Qt.PointingHandCursor : Qt.ArrowCursor
                  onClicked: root.toggleRepo(repoCard.modelData.id)
                }

                RowLayout {
                  id: repoRow
                  anchors.fill: parent
                  spacing: Style.space(6)

                  ColumnLayout {
                    spacing: 1
                    Layout.leftMargin: Style.space(6)

                    Text {
                      textFormat: Text.PlainText
                      text: modelData.name
                      color: root.fg
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: true
                    }

                    Text {
                      Layout.fillWidth: true
                      textFormat: Text.PlainText
                      elide: Text.ElideRight
                      text: {
                        if (repoCard.count > 0) {
                          var label = repoCard.count === 1 ? "1 update" : repoCard.count + " updates"
                          if (modelData.id === "system" && modelData.omarchyPending === true) label += " · Omarchy update available"
                          return label
                        }
                        return "Up to date"
                      }
                      color: repoCard.count > 0 ? root.fg : root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  Item { Layout.fillWidth: true }

                  Text {
                    textFormat: Text.PlainText
                    visible: hostWidget && hostWidget.pendingRepo === modelData.id && hostWidget.fastPollActive
                    text: "…"
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    Layout.alignment: Qt.AlignVCenter
                  }

                  Text {
                    textFormat: Text.PlainText
                    visible: repoCard.expandable
                    text: repoCard.expanded ? "▼" : "▶"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    Layout.alignment: Qt.AlignVCenter
                  }

                  Button {
                    visible: repoCard.hasCommand && repoCard.count > 0
                    text: "Update"
                    Layout.rightMargin: Style.space(6)
                    foreground: root.fg
                    fontFamily: root.fontFamily
                    fontSize: Style.font.caption
                    horizontalPadding: Style.spacing.controlPaddingX
                    verticalPadding: Style.spacing.controlPaddingY
                    active: true
                    onClicked: root.updateRepo(modelData.id)
                  }
                }
              }

              // Expanded package list. Versioned entries show old → new;
              // git entries (plugins/themes, and a dev Omarchy checkout)
              // show the commits behind instead. The list is capped and
              // scrolls so a large batch can't overflow the panel.
              Flickable {
                id: packageList
                visible: repoCard.expanded
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(packagesColumn.implicitHeight, Style.space(260))
                contentWidth: width
                contentHeight: packagesColumn.implicitHeight
                clip: true
                interactive: contentHeight > height
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                  id: packagesColumn
                  width: parent.width
                  spacing: Style.space(2)

                  Repeater {
                    model: repoCard.packages

                    delegate: RowLayout {
                      required property var modelData
                      Layout.fillWidth: true
                      spacing: Style.space(8)

                      Text {
                        Layout.fillWidth: true
                        textFormat: Text.PlainText
                        text: modelData.name
                        color: root.fg
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        elide: Text.ElideRight
                      }

                      Text {
                        textFormat: Text.PlainText
                        visible: (modelData.behind || 0) > 0
                        text: modelData.behind + (modelData.behind === 1 ? " commit behind" : " commits behind")
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        Layout.alignment: Qt.AlignVCenter
                      }

                      Text {
                        textFormat: Text.PlainText
                        visible: (modelData.behind || 0) <= 0 && ((modelData.from || "") !== "" || (modelData.to || "") !== "")
                        text: ((modelData.from || "") !== "" ? modelData.from + " → " : "") + (modelData.to || "")
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        Layout.alignment: Qt.AlignVCenter
                      }
                    }
                  }
                }
              }
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          visible: {
            if (root.installedRepos.length === 0) return false
            for (var i = 0; i < root.installedRepos.length; i++) {
              if (root.installedRepos[i].count > 0) return false
            }
            return true
          }
          Layout.fillWidth: true
          Layout.topMargin: Style.space(4)
          text: "Everything is up to date"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          horizontalAlignment: Text.AlignHCenter
        }
      }
    }
  }
}
