import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Standalone system settings. A floating layer-shell window with the same
// controls as the bar's settings window System tab, for when the
// arch-updates plugin runs on its own (stock Omarchy bar, no Nyxiri bar),
// where there is no bar settings window to open. Opened by right-clicking
// the badge; the widget's toggleSettings() flips it.
// Every control writes through hostWidget.setSystem(), which is the same
// updateEntryInline the bar's window uses, so the two stay in sync: both
// write to the same arch-updates layout entry. When the bar IS installed,
// the bar's settings window is the primary UI and this is just an
// alternate door into the same settings.
PanelWindow {
  id: popup

  // `bar` is passed from the widget (the bar the widget sits on, Nyxiri
  // or stock); `hostWidget` is the arch-updates widget root, which owns
  // the settings and the write mechanism.
  property var bar: null
  property var hostWidget: null

  // A real layer-shell surface, not a popup: it takes keyboard focus
  // natively, so the slider just works. Floating: it reserves no bar
  // space, and the mask limits input to the window body so clicks
  // outside it pass through to the windows below.
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "pizza.dirty.arch-updates-settings"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }

  // Close is named closeSettings, not close: PanelWindow is a QQuickWindow
  // and already has a close() method, which this must not shadow.
  function closeSettings() {
    if (hostWidget) hostWidget.settingsOpen = false
  }

  // ---------------------------------------------------------------- settings

  function sysSetting(name, fallback) {
    return hostWidget ? hostWidget.setting(name, fallback) : fallback
  }

  function boolSysSetting(name, fallback) {
    var value = popup.sysSetting(name, fallback)
    if (value === undefined || value === null) return fallback
    if (typeof value === "string") return value !== "false" && value !== "0" && value !== ""
    return value !== false
  }

  function setSystem(patch) {
    if (hostWidget) hostWidget.setSystem(patch)
  }

  // ------------------------------------------------------------------- ui

  component SectionLabel: Text {
    color: Qt.darker(popup.bar.foreground, 1.35)
    font.family: popup.bar.fontFamily
    font.pixelSize: Style.font.title
    font.bold: true
    font.letterSpacing: 0.4
    textFormat: Text.PlainText
    topPadding: Style.space(16)
    bottomPadding: Style.spacing.md
  }

  // Sub-headers under a section (Refresh, Sources, ...): one step smaller
  // than a section header, still bigger than the old caption labels, with
  // room under them too.
  component SubLabel: Text {
    color: Qt.darker(popup.bar.foreground, 1.4)
    font.family: popup.bar.fontFamily
    font.pixelSize: Style.font.body
    font.bold: true
    textFormat: Text.PlainText
    bottomPadding: Style.spacing.sm
  }

  component BodyText: Text {
    color: popup.bar.foreground
    font.family: popup.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
    textFormat: Text.PlainText
    verticalAlignment: Text.AlignVCenter
  }

  // A slider with its label on its own line above it. The label gets its
  // own line and the slider gets the whole width. `value` is bound to the
  // setting, `released` writes it back.
  component SliderRow: Column {
    id: sliderRow
    required property string label
    required property real value
    required property real minimum
    required property real maximum
    required property real step
    property bool integer: false
    required property string valueText
    signal released(real value)

    width: parent.width
    spacing: Style.spacing.xxs

    BodyText {
      text: sliderRow.label
      width: parent.width
    }

    Row {
      width: parent.width
      spacing: Style.spacing.sm

      PanelSlider {
        width: parent.width - sliderValue.width - parent.spacing
        bar: popup.bar
        value: sliderRow.value
        minimum: sliderRow.minimum
        maximum: sliderRow.maximum
        step: sliderRow.step
        integer: sliderRow.integer
        onReleased: function(value) { sliderRow.released(value) }
      }

      BodyText {
        id: sliderValue
        text: sliderRow.valueText
        width: Style.space(64)
        horizontalAlignment: Text.AlignRight
      }
    }
  }

  Shortcut {
    sequence: "Escape"
    enabled: popup.visible
    onActivated: popup.closeSettings()
  }

  // The window body: a fixed-size surface centered on its screen. The
  // PanelWindow itself spans the screen (transparent) and the mask limits
  // input to this body, so clicks outside it pass through.
  BorderSurface {
    id: windowBody
    anchors.centerIn: parent
    width: Style.space(560)
    height: Style.space(600)
    radius: Style.cornerRadius
    color: popup.bar.background
    borderSpec: Border.flat(popup.bar.foreground, 1)

    Column {
      anchors.fill: parent
      anchors.margins: Style.spacing.md
      spacing: Style.spacing.sm

      Flickable {
        id: scrollArea
        width: parent.width
        height: parent.height - closeButton.height - parent.spacing
        contentWidth: width
        contentHeight: body.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        clip: true

        Column {
          id: body
          width: scrollArea.width
          spacing: Style.space(16)

          SectionLabel { text: "SYSTEM" }

          SubLabel { text: "Refresh" }

          SliderRow {
            label: "Refresh interval"
            value: Number(popup.sysSetting("refreshIntervalSec", 1800))
            minimum: 300
            maximum: 7200
            step: 300
            integer: true
            valueText: Math.round(Number(popup.sysSetting("refreshIntervalSec", 1800)) / 60) + " min"
            onReleased: function(value) { popup.setSystem({ refreshIntervalSec: Math.round(value) }) }
          }

          Toggle {
            width: body.width
            label: "Automatic checks"
            description: popup.boolSysSetting("autoRefresh", true) ? "Check on the interval and once after startup" : "Checks run only when the panel is opened"
            checked: popup.boolSysSetting("autoRefresh", true)
            foreground: popup.bar.foreground
            onClicked: popup.setSystem({ autoRefresh: !checked })
          }

          Toggle {
            width: body.width
            label: "Always show"
            description: popup.boolSysSetting("alwaysShow", true) ? "Keep the icon visible even when no updates are available" : "Hide the icon when everything is up to date"
            checked: popup.boolSysSetting("alwaysShow", true)
            foreground: popup.bar.foreground
            onClicked: popup.setSystem({ alwaysShow: !checked })
          }

          SubLabel { text: "Sources" }

          Toggle {
            width: body.width
            label: "AUR"
            description: "AUR updates from your helper (yay or paru)"
            checked: popup.boolSysSetting("checkAur", true)
            foreground: popup.bar.foreground
            onClicked: popup.setSystem({ checkAur: !checked })
          }

          Toggle {
            width: body.width
            label: "Flatpak"
            description: "Flatpak updates"
            checked: popup.boolSysSetting("checkFlatpak", true)
            foreground: popup.bar.foreground
            onClicked: popup.setSystem({ checkFlatpak: !checked })
          }

          Toggle {
            width: body.width
            label: "mise"
            description: "mise dev tools"
            checked: popup.boolSysSetting("checkMise", true)
            foreground: popup.bar.foreground
            onClicked: popup.setSystem({ checkMise: !checked })
          }

          Toggle {
            width: body.width
            label: "Plugins & themes"
            description: "Git-managed shell plugins and themes"
            checked: popup.boolSysSetting("checkPlugins", true)
            foreground: popup.bar.foreground
            onClicked: popup.setSystem({ checkPlugins: !checked })
          }
        }
      }

      Button {
        id: closeButton
        width: parent.width
        text: "Close"
        bordered: true
        foreground: popup.bar.foreground
        onClicked: popup.closeSettings()
      }
    }
  }

  // Input goes only to the window body; the rest of the fullscreen surface
  // is transparent to the pointer.
  mask: Region { item: windowBody }
}
