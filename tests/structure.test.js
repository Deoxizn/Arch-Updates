"use strict"

const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

const root = path.join(__dirname, "..")
const read = (name) => fs.readFileSync(path.join(root, name), "utf8")
const exists = (name) => fs.existsSync(path.join(root, name))

test("manifest is version 2.0.0 and declares the system settings", () => {
  const manifest = JSON.parse(read("manifest.json"))
  assert.equal(manifest.id, "pizza.dirty.arch-updates")
  assert.equal(manifest.version, "2.0.0")
  assert.equal(manifest.entryPoints.barWidget, "BarWidget.qml")
  const defaults = manifest.barWidget.defaults
  assert.equal(defaults.refreshIntervalSec, 1800)
  assert.equal(defaults.alwaysShow, true)
  assert.equal(defaults.autoRefresh, true)
  assert.equal(defaults.checkAur, true)
  assert.equal(defaults.checkFlatpak, true)
  assert.equal(defaults.checkMise, true)
  assert.equal(defaults.checkPlugins, true)
  const keys = manifest.barWidget.schema.map((entry) => entry.key)
  for (const key of ["refreshIntervalSec", "alwaysShow", "autoRefresh", "checkAur", "checkFlatpak", "checkMise", "checkPlugins"]) {
    assert.ok(keys.includes(key), `schema missing ${key}`)
  }
})

test("the old bash scanner is gone; the Python scanner is the only checker", () => {
  assert.ok(!exists("check-updates.sh"), "check-updates.sh must be deleted")
  assert.ok(exists("scripts/check_updates.py"), "scripts/check_updates.py missing")
  assert.ok(exists("scripts/update_plugins_themes.py"), "scripts/update_plugins_themes.py missing")
  assert.ok(exists("Model.js"), "Model.js missing")
  assert.ok(exists("Panel.qml"), "Panel.qml missing")
  assert.ok(exists("SystemSettings.qml"), "SystemSettings.qml missing")
})

test("the System section updates with hexciri update, never bare pacman", () => {
  const model = read("Model.js")
  // The system repo's only update command is the managed pipeline.
  // Commands are bare: the presentation wrapper waits for a keypress
  // itself, so no read-prompt suffix.
  assert.match(model, /if \(id === "system"\) return "hexciri update"/)
  // No bare pacman anywhere in the command builder: not as a command, and
  // Hexciri has no direct-pacman override env var; its guard is a no-op.
  assert.doesNotMatch(model, /pacman -Syu/)
  assert.doesNotMatch(model, /OMARCHY_ALLOW_DIRECT_PACMAN/)
  assert.doesNotMatch(model, /read -n 1/)
  // The other sources keep their own safe updater.
  assert.match(model, /if \(id === "aur"\)/)
  assert.match(model, /return helper \+ " -Sua"/)
  assert.match(model, /if \(id === "flatpak"\) return "flatpak update"/)
  // Plugins & Themes update selectively: the widget passes the helper
  // script path, and the blanket `hexciri plugin update --yes;
  // hexciri theme update` is only the fallback when no path is given.
  assert.match(model, /if \(id === "plugins"\) \{/)
  assert.match(model, /return "python3 " \+ script/)
  assert.match(model, /return "hexciri plugin update --yes; hexciri theme update"/)
  assert.match(model, /if \(id === "mise"\) return "MISE_MINIMUM_RELEASE_AGE=0 mise up"/)
  // The AUR helper is a fixed enum: an unknown helper yields no command.
  assert.match(model, /AUR_HELPERS/)
  assert.match(model, /if \(AUR_HELPERS\.indexOf\(helper\) === -1\) return ""/)
  // Only the five known repo ids parse.
  assert.match(model, /"system": true/)
  assert.match(model, /"aur": true/)
  assert.match(model, /"flatpak": true/)
  assert.match(model, /"plugins": true/)
  assert.match(model, /"mise": true/)
})

test("the widget scans with python3, shows the badge, and opens the panel", () => {
  const widget = read("BarWidget.qml")
  assert.match(widget, /\["python3", root\.scriptPath\]/)
  assert.match(widget, /scripts\/check_updates\.py/)
  // Nerd Font package icons, as QML escapes (ASCII, so they survive
  // transport): clean U+F487, pending U+F03D6.
  assert.match(widget, /property string noUpdatesIcon: "\\uf487"/)
  assert.match(widget, /property string updatesIcon: "\\udb80\\udfd6"/)
  // The badge shows the count when updates are waiting.
  assert.match(widget, /text: root\.hasUpdates \? root\.updatesIcon \+ " " \+ root\.totalCount : root\.noUpdatesIcon/)
  // Left click opens the panel, middle refreshes, right opens settings.
  assert.match(widget, /root\.togglePanel\(\)/)
  assert.match(widget, /Qt\.RightButton\) \{ root\.toggleSettings\(\); return \}/)
  assert.match(widget, /Qt\.MiddleButton\) \{ root\.runCheck\(\); return \}/)
  // The panel is loaded through a Loader, on the clock's pattern.
  assert.match(widget, /source: Qt\.resolvedUrl\("Panel\.qml"\)/)
  assert.match(widget, /target\.anchorItem = badge/)
  assert.match(widget, /target\.hostWidget = root/)
  // Settings come from the layout entry and are written through the same
  // updateEntryInline the bar's System tab uses.
  assert.match(widget, /function setSystem\(patch\)/)
  assert.match(widget, /root\.bar\.shell\.updateEntryInline\(root\.moduleName, entry\)/)
  assert.match(widget, /refreshIntervalSec/)
  assert.match(widget, /checkAur/)
  assert.match(widget, /checkFlatpak/)
  assert.match(widget, /checkMise/)
  assert.match(widget, /checkPlugins/)
  // The scanner gets the per-source toggles as --no-* flags.
  assert.match(widget, /args\.push\("--no-aur"\)/)
  assert.match(widget, /args\.push\("--no-flatpak"\)/)
  assert.match(widget, /args\.push\("--no-mise"\)/)
  assert.match(widget, /args\.push\("--no-plugins"\)/)
  // Updates open a terminal through bar.run, the 1.x left-click path:
  // a plain string to the bar's run (Util.execDetached, shell), with
  // Hexciri's presentation wrapper as the launcher. That combination
  // worked in 1.x and still works for the menu's right-click. The 2.0.0
  // QML Process launches never opened a terminal, and plain
  // xdg-terminal-exec closes instantly on success, which is why the
  // wrapper exists: logo, update, Done, wait for a keypress.
  assert.match(widget, /root\.bar\.run\("hexciri-launch-floating-terminal-with-presentation " \+ root\.shellQuote\(cmd\)\)/)
  assert.match(widget, /function shellQuote\(value\)/)
  assert.doesNotMatch(widget, /id: launchProc/)
  assert.doesNotMatch(widget, /launchStartedAt/)
  assert.doesNotMatch(widget, /launchProc\.command/)
  // The fast poll ends when a rescan shows the pending repo at zero.
  assert.match(widget, /root\.repos\[i\]\.id === root\.pendingRepo && root\.repos\[i\]\.count === 0/)
  assert.match(widget, /Model\.updateCommandFor\(repo, root\.updateScriptPath\)/)
  assert.match(widget, /updateScriptPath: .*scripts\/update_plugins_themes\.py/)
  // The scanner and its updater live under the Hexciri plugin dir, and
  // the last-good cache lives under ~/.cache/hexciri.
  assert.match(widget, /\.config\/hexciri\/plugins\/pizza\.dirty\.arch-updates\/scripts\/check_updates\.py/)
  assert.match(widget, /\/hexciri\/pizza\.dirty\.arch-updates\.json/)
  assert.match(widget, /fastPollTimer/)
  // The standalone settings window, one per bar surface.
  assert.match(widget, /SystemSettings \{/)
  assert.match(widget, /visible: root\.settingsOpen/)
})

test("the panel lists pending packages per source with an update button each", () => {
  const panel = read("Panel.qml")
  assert.match(panel, /KeyboardPanel \{/)
  assert.match(panel, /anchorItem: root\.anchorItem/)
  assert.match(panel, /owner: root\.barIdentity/)
  assert.match(panel, /model: root\.opened \? root\.installedRepos : \[\]/)
  assert.match(panel, /modelData\.name/)
  // Versioned entries show old → new; git entries show commits behind.
  assert.match(panel, /modelData\.from \+ " → "/)
  assert.match(panel, /commits behind/)
  // The combined section notes an available Hexciri update.
  assert.match(panel, /Hexciri update available/)
  // Each card's Update button calls the widget's updater and closes.
  assert.match(panel, /text: "Update"/)
  assert.match(panel, /onClicked: root\.updateRepo\(modelData\.id\)/)
  // Rows expand to reveal their packages.
  assert.match(panel, /function toggleRepo\(id\)/)
  assert.match(panel, /visible: repoCard\.expanded/)
  // Header has Refresh and a way into settings.
  assert.match(panel, /text: "Refresh"/)
  assert.match(panel, /text: "Settings"/)
})

test("the standalone settings window mirrors the System tab", () => {
  const settings = read("SystemSettings.qml")
  assert.match(settings, /PanelWindow \{/)
  assert.match(settings, /WlrLayershell\.namespace: "pizza\.dirty\.arch-updates-settings"/)
  assert.match(settings, /SectionLabel \{ text: "SYSTEM UPDATER" \}/)
  assert.match(settings, /label: "Refresh interval"/)
  assert.match(settings, /popup\.sysSetting\("refreshIntervalSec", 1800\)/)
  assert.match(settings, /label: "Automatic checks"/)
  assert.match(settings, /label: "Always show"/)
  assert.match(settings, /label: "AUR"/)
  assert.match(settings, /label: "Flatpak"/)
  assert.match(settings, /label: "mise"/)
  assert.match(settings, /label: "Plugins & themes"/)
  // Every control writes through the host widget's setSystem, the same
  // updateEntryInline the bar's System tab uses.
  assert.match(settings, /popup\.setSystem\(\{/)
  assert.match(settings, /hostWidget\.setSystem\(patch\)/)
  // Escape closes it.
  assert.match(settings, /sequence: "Escape"/)
})

test("the panel reopens after any close: widget owns the panel contract and the panel has explicit close controls", () => {
  const widget = read("BarWidget.qml")
  // The bar-widget panel contract, same as the clock: Bar.findPanelWidget
  // needs open/close/opened on the widget root, and KeyboardPanel's
  // outside-click dismiss calls owner.close() when the owner has one.
  // Without close() on the widget, the dismiss assigned the KeyboardPanel's
  // own `open = false` directly, breaking the `open: root.opened` binding:
  // panelController.open stayed true, so the panel opened once and never
  // again after a click-outside dismiss.
  assert.match(widget, /readonly property bool opened: panelLoader\.item \? panelLoader\.item\.opened === true : false/)
  assert.match(widget, /function open\(\) \{/)
  assert.match(widget, /function close\(\) \{/)
  assert.match(widget, /if \(panelLoader\.item\) panelLoader\.item\.close\(\)/)
  // togglePanel goes through the contract functions: one open path.
  assert.match(widget, /if \(panelLoader\.item\.opened\) root\.close\(\)/)
  assert.match(widget, /else root\.open\(\)/)
  // The old parallel names are gone.
  assert.doesNotMatch(widget, /function openPanel\(\)/)
  assert.doesNotMatch(widget, /function closePanel\(\)/)
  assert.doesNotMatch(widget, /panelOpened/)

  const panel = read("Panel.qml")
  // The KeyboardPanel still binds open to root.opened and hands the widget
  // over as owner, so the dismiss routes through the widget's close().
  assert.match(panel, /owner: root\.barIdentity/)
  assert.match(panel, /open: root\.opened/)
  // Explicit close controls, both on the clean close path.
  assert.match(panel, /text: "\\u00d7"/)
  assert.match(panel, /text: "Close"/)
  assert.match(panel, /onClicked: root\.close\(\)/)
})

test("the scanner emits the combined system repo and per-source flags", () => {
  const scanner = read("scripts/check_updates.py")
  assert.match(scanner, /"system"/)
  assert.match(scanner, /"system",\s+"System",/)
  assert.match(scanner, /hexciriPending/)
  assert.match(scanner, /hexciri_checkout_behind/)
  assert.match(scanner, /HEXCIRI_PATH/)
  assert.match(scanner, /HEXCIRI_SYSTEM_PATH/)
  // No Hexciri pacman package exists, so the old Omarchy package list
  // and pending flag are gone, not renamed.
  assert.doesNotMatch(scanner, /OMARCHY_PACKAGES/)
  assert.doesNotMatch(scanner, /omarchyPending/)
  assert.match(scanner, /--no-aur/)
  assert.match(scanner, /--no-flatpak/)
  assert.match(scanner, /--no-mise/)
  assert.match(scanner, /--no-plugins/)
  // The scanner is check-only: it never installs anything, and it never
  // runs a bare pacman upgrade.
  assert.doesNotMatch(scanner, /pacman -Syu/)
  assert.doesNotMatch(scanner, /OMARCHY_ALLOW_DIRECT_PACMAN/)
  assert.match(scanner, /"repos": repos/)
  assert.match(scanner, /"total": total/)
})
