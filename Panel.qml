import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui

// The panel loaded by BarWidget.qml: the Noctalia-style vertical list.
// One collapsible section per category (Repo, AUR, Mise, Plugins,
// Themes), each row naming the package and its old -> new version
// (plugins/themes show commits behind instead, there is no version).
// It does NOT own IPC (manageIpc: false) — the bar widget does — and it
// keeps moduleName = the manifest id. bar/settings/anchorItem/hostWidget
// are injected by BarWidget.injectPanel(); the lists live on hostWidget
// (BarWidget.repoList etc.), so this file holds no check logic at all.
//
// Click a section header to collapse/expand it, for long lists. The
// viewport caps at ~430px and scrolls (Flickable, same shape as the
// Nyxiri settings card), so 50 pending packages do not blow the panel
// off the screen.

Panel {
  id: root

  moduleName: "devi.arch-updates"
  ipcTarget: "devi.arch-updates"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  // The bar tracks the widget mounted in its slot (BarWidget.qml), not this
  // nested panel, so stand in for it wherever the bar identifies a panel.
  readonly property var barIdentity: hostWidget || root

  function open() { root.controller.show() }
  function close() { root.controller.hide() }
  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // Guarded so the panel still renders before the bar is injected.
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.rgba(fg.r, fg.g, fg.b, 0.6)
  readonly property string ff: bar ? bar.fontFamily : Style.font.family

  // One bool per section (not a var map: mutating a map entry does not
  // re-evaluate bindings, a plain bool does). All expanded by default.
  property bool repoCollapsed: false
  property bool aurCollapsed: false
  property bool miseCollapsed: false
  property bool pluginsCollapsed: false
  property bool themesCollapsed: false

  readonly property bool hasWidget: root.hostWidget !== null && root.hostWidget !== undefined
  readonly property int totalCount: root.hasWidget ? root.hostWidget.totalCount : 0
  readonly property bool checked: root.hasWidget ? root.hostWidget.checked === true : false

  KeyboardPanel {
    id: panel

    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher

    contentWidth: panel.fittedContentWidth(Style.space(460))
    // Size the card to the content (capped), so nothing overflows the border.
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(760))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        width: parent.width
        padding: Style.space(16)
        spacing: Style.space(12)

        Text {
          text: !root.checked ? "Checking for updates…"
            : root.totalCount > 0 ? root.totalCount + " updates pending"
            : "No updates pending"
          color: root.fg
          font.family: root.ff
          font.pixelSize: Style.font.title
          font.bold: true
        }

        Text {
          visible: root.checked
          text: root.hasWidget
            ? "Repo " + root.hostWidget.repoCount + " · AUR " + root.hostWidget.aurCount + " · Mise " + root.hostWidget.miseCount + " · Plugins " + root.hostWidget.pluginsCount + " · Themes " + root.hostWidget.themesCount
            : ""
          color: root.dim
          font.family: root.ff
          font.pixelSize: Style.font.caption
        }

        Row {
          width: parent.width
          spacing: Style.space(8)

          Button {
            text: "Update all"
            bordered: true
            foreground: root.fg
            onClicked: { if (root.hasWidget) root.hostWidget.runUpdate() }
          }

          Button {
            text: "Refresh"
            bordered: true
            foreground: root.fg
            onClicked: { if (root.hasWidget) root.hostWidget.runCheck() }
          }

          Button {
            text: "Close"
            bordered: true
            foreground: root.fg
            onClicked: { root.close() }
          }
        }

        Item {
          id: viewport
          width: parent.width
          height: Math.min(body.implicitHeight, Style.space(430))
          clip: true

          Flickable {
            id: scrollArea
            anchors.fill: parent
            contentWidth: width
            contentHeight: body.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            clip: true

            Column {
              id: body
              width: scrollArea.width
              spacing: Style.space(8)

              Text {
                visible: root.checked && root.totalCount === 0
                text: "Up to date. Nothing pending."
                color: root.dim
                font.family: root.ff
                font.pixelSize: Style.font.body
              }

              Text {
                visible: !root.checked
                text: "Checking for updates…"
                color: root.dim
                font.family: root.ff
                font.pixelSize: Style.font.body
              }

              // -------------------------------------------------- Repo
              Column {
                visible: root.checked && root.hasWidget && root.hostWidget.repoCount > 0
                width: parent.width
                spacing: Style.space(4)

                Item {
                  width: parent.width
                  height: Style.space(24)
                  Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Repo (" + (root.hasWidget ? root.hostWidget.repoCount : 0) + ")"
                    color: root.fg
                    font.family: root.ff
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }
                  Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.repoCollapsed ? "▸" : "▾"
                    color: root.dim
                    font.family: root.ff
                    font.pixelSize: Style.font.body
                  }
                  MouseArea {
                    anchors.fill: parent
                    onClicked: root.repoCollapsed = !root.repoCollapsed
                  }
                }

                Repeater {
                  model: root.hasWidget ? root.hostWidget.repoList : []
                  delegate: RowLayout {
                    required property var modelData
                    visible: !root.repoCollapsed
                    width: body.width
                    spacing: Style.space(8)
                    Text {
                      text: modelData.name
                      color: root.fg
                      font.family: root.ff
                      font.pixelSize: Style.font.body
                      elide: Text.ElideRight
                      Layout.fillWidth: true
                    }
                    Text {
                      text: modelData.oldVersion + " → " + modelData.newVersion
                      color: root.dim
                      font.family: root.ff
                      font.pixelSize: Style.font.body
                      elide: Text.ElideRight
                      Layout.alignment: Qt.AlignRight
                    }
                  }
                }

                Text {
                  visible: !root.repoCollapsed && root.hasWidget && root.hostWidget.repoList.length === 0
                  text: "Details unavailable — check-updates.sh is older than v1.7.0."
                  color: root.dim
                  font.family: root.ff
                  font.pixelSize: Style.font.caption
                }
              }

              // -------------------------------------------------- AUR
              Column {
                visible: root.checked && root.hasWidget && root.hostWidget.aurCount > 0
                width: parent.width
                spacing: Style.space(4)

                Item {
                  width: parent.width
                  height: Style.space(24)
                  Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "AUR (" + (root.hasWidget ? root.hostWidget.aurCount : 0) + ")"
                    color: root.fg
                    font.family: root.ff
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }
                  Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.aurCollapsed ? "▸" : "▾"
                    color: root.dim
                    font.family: root.ff
                    font.pixelSize: Style.font.body
                  }
                  MouseArea {
                    anchors.fill: parent
                    onClicked: root.aurCollapsed = !root.aurCollapsed
                  }
                }

                Repeater {
                  model: root.hasWidget ? root.hostWidget.aurList : []
                  delegate: RowLayout {
                    required property var modelData
                    visible: !root.aurCollapsed
                    width: body.width
                    spacing: Style.space(8)
                    Text {
                      text: modelData.name
                      color: root.fg
                      font.family: root.ff
                      font.pixelSize: Style.font.body
                      elide: Text.ElideRight
                      Layout.fillWidth: true
                    }
                    Text {
                      text: modelData.oldVersion + " → " + modelData.newVersion
                      color: root.dim
                      font.family: root.ff
                      font.pixelSize: Style.font.body
                      elide: Text.ElideRight
                      Layout.alignment: Qt.AlignRight
                    }
                  }
                }

                Text {
                  visible: !root.aurCollapsed && root.hasWidget && root.hostWidget.aurList.length === 0
                  text: "Details unavailable — check-updates.sh is older than v1.7.0."
                  color: root.dim
                  font.family: root.ff
                  font.pixelSize: Style.font.caption
                }
              }

              // -------------------------------------------------- Mise
              Column {
                visible: root.checked && root.hasWidget && root.hostWidget.miseCount > 0
                width: parent.width
                spacing: Style.space(4)

                Item {
                  width: parent.width
                  height: Style.space(24)
                  Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Mise (" + (root.hasWidget ? root.hostWidget.miseCount : 0) + ")"
                    color: root.fg
                    font.family: root.ff
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }
                  Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.miseCollapsed ? "▸" : "▾"
                    color: root.dim
                    font.family: root.ff
                    font.pixelSize: Style.font.body
                  }
                  MouseArea {
                    anchors.fill: parent
                    onClicked: root.miseCollapsed = !root.miseCollapsed
                  }
                }

                Repeater {
                  model: root.hasWidget ? root.hostWidget.miseList : []
                  delegate: RowLayout {
                    required property var modelData
                    visible: !root.miseCollapsed
                    width: body.width
                    spacing: Style.space(8)
                    Text {
                      text: modelData.name
                      color: root.fg
                      font.family: root.ff
                      font.pixelSize: Style.font.body
                      elide: Text.ElideRight
                      Layout.fillWidth: true
                    }
                    Text {
                      text: modelData.oldVersion + " → " + modelData.newVersion
                      color: root.dim
                      font.family: root.ff
                      font.pixelSize: Style.font.body
                      elide: Text.ElideRight
                      Layout.alignment: Qt.AlignRight
                    }
                  }
                }

                Text {
                  visible: !root.miseCollapsed && root.hasWidget && root.hostWidget.miseList.length === 0
                  text: "Details unavailable — check-updates.sh is older than v1.7.0."
                  color: root.dim
                  font.family: root.ff
                  font.pixelSize: Style.font.caption
                }
              }

              // -------------------------------------------------- Plugins
              Column {
                visible: root.checked && root.hasWidget && root.hostWidget.pluginsCount > 0
                width: parent.width
                spacing: Style.space(4)

                Item {
                  width: parent.width
                  height: Style.space(24)
                  Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Plugins (" + (root.hasWidget ? root.hostWidget.pluginsCount : 0) + ")"
                    color: root.fg
                    font.family: root.ff
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }
                  Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.pluginsCollapsed ? "▸" : "▾"
                    color: root.dim
                    font.family: root.ff
                    font.pixelSize: Style.font.body
                  }
                  MouseArea {
                    anchors.fill: parent
                    onClicked: root.pluginsCollapsed = !root.pluginsCollapsed
                  }
                }

                Repeater {
                  model: root.hasWidget ? root.hostWidget.pluginsList : []
                  delegate: RowLayout {
                    required property var modelData
                    visible: !root.pluginsCollapsed
                    width: body.width
                    spacing: Style.space(8)
                    Text {
                      text: modelData.name
                      color: root.fg
                      font.family: root.ff
                      font.pixelSize: Style.font.body
                      elide: Text.ElideRight
                      Layout.fillWidth: true
                    }
                    Text {
                      text: modelData.behind + " commits behind"
                      color: root.dim
                      font.family: root.ff
                      font.pixelSize: Style.font.body
                      elide: Text.ElideRight
                      Layout.alignment: Qt.AlignRight
                    }
                  }
                }

                Text {
                  visible: !root.pluginsCollapsed && root.hasWidget && root.hostWidget.pluginsList.length === 0
                  text: "Details unavailable — check-updates.sh is older than v1.7.0."
                  color: root.dim
                  font.family: root.ff
                  font.pixelSize: Style.font.caption
                }
              }

              // -------------------------------------------------- Themes
              Column {
                visible: root.checked && root.hasWidget && root.hostWidget.themesCount > 0
                width: parent.width
                spacing: Style.space(4)

                Item {
                  width: parent.width
                  height: Style.space(24)
                  Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Themes (" + (root.hasWidget ? root.hostWidget.themesCount : 0) + ")"
                    color: root.fg
                    font.family: root.ff
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }
                  Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.themesCollapsed ? "▸" : "▾"
                    color: root.dim
                    font.family: root.ff
                    font.pixelSize: Style.font.body
                  }
                  MouseArea {
                    anchors.fill: parent
                    onClicked: root.themesCollapsed = !root.themesCollapsed
                  }
                }

                Repeater {
                  model: root.hasWidget ? root.hostWidget.themesList : []
                  delegate: RowLayout {
                    required property var modelData
                    visible: !root.themesCollapsed
                    width: body.width
                    spacing: Style.space(8)
                    Text {
                      text: modelData.name
                      color: root.fg
                      font.family: root.ff
                      font.pixelSize: Style.font.body
                      elide: Text.ElideRight
                      Layout.fillWidth: true
                    }
                    Text {
                      text: modelData.behind + " commits behind"
                      color: root.dim
                      font.family: root.ff
                      font.pixelSize: Style.font.body
                      elide: Text.ElideRight
                      Layout.alignment: Qt.AlignRight
                    }
                  }
                }

                Text {
                  visible: !root.themesCollapsed && root.hasWidget && root.hostWidget.themesList.length === 0
                  text: "Details unavailable — check-updates.sh is older than v1.7.0."
                  color: root.dim
                  font.family: root.ff
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }
        }

        Text {
          visible: root.checked && root.hasWidget && root.hostWidget.checkedAt !== ""
          text: "Checked " + root.hostWidget.checkedAt + " · Left-click the pill to reopen · Right-click updates now"
          color: root.dim
          font.family: root.ff
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
