// Parse and validate the check_updates.py JSON output. The scan result is
// produced by a subprocess and cached on disk, so treat it as untrusted
// input: keep only the repos this widget knows how to render and the fields
// it actually uses, with all strings and collections bounded. Update
// commands are owned by the widget, never by the scan output: the scanner
// reports the AUR helper as a fixed enum and the widget rebuilds the
// command from it.
var MAX_REPOS = 16
var MAX_PACKAGES_PER_REPO = 1000
var MAX_COUNT = 1000000
var MAX_NAME_LEN = 200
var MAX_VER_LEN = 100
var KNOWN_REPO_IDS = {
  "system": true,
  "aur": true,
  "flatpak": true,
  "plugins": true,
  "mise": true
}
var AUR_HELPERS = ["yay", "paru"]

function text(value, limit) {
  if (value === undefined || value === null) return ""
  var result = typeof value === "string" ? value : String(value)
  return result.length > limit ? result.slice(0, limit) : result
}

function count(value, limit) {
  var number = Number(value)
  if (!isFinite(number) || number <= 0) return 0
  return Math.min(Math.floor(number), limit)
}

function boolValue(value, fallback) {
  if (value === undefined || value === null) return fallback
  if (typeof value === "string") return value !== "false" && value !== "0" && value !== ""
  return value !== false
}

// The combined Omarchy + Arch repo is the only one whose update action is
// the managed pipeline. A bare pacman system upgrade bypasses Omarchy's
// guard and skips the transcript, snapshot, keyrings, migrations, and
// post-update hooks, so it is never an update action here, not even with
// the direct-pacman override env var set.
// Commands are bare, with no wait-for-keypress suffix: the widget runs
// them through omarchy-launch-floating-terminal-with-presentation, whose
// wrapper shows the Omarchy logo, runs the command, then shows Done and
// waits for a keypress itself. (The 2.0.0 read-prompt suffix was a
// workaround for plain xdg-terminal-exec closing instantly on success;
// with the wrapper it would prompt twice.)
function updateCommandFor(repo, updateScriptPath) {
  var id = String((repo && repo.id) || "")
  if (id === "system") return "omarchy update"
  if (id === "aur") {
    var helper = String((repo && repo.updater) || "")
    if (AUR_HELPERS.indexOf(helper) === -1) return ""
    return helper + " -Sua"
  }
  if (id === "flatpak") return "flatpak update"
  if (id === "plugins") {
    // Selective update: scripts/update_plugins_themes.py checks each
    // plugin and theme first and only pulls the ones behind upstream.
    // The blanket `omarchy plugin update --yes; omarchy theme update`
    // touches every plugin and pulls every theme on each run. It stays
    // as the fallback when the widget did not pass a script path.
    var script = String(updateScriptPath || "")
    if (script) return "python3 " + script
    return "omarchy plugin update --yes; omarchy theme update"
  }
  if (id === "mise") return "MISE_MINIMUM_RELEASE_AGE=0 mise up"
  return ""
}

function parseRepoList(raw) {
  var data
  try {
    data = JSON.parse(String(raw || "{}"))
  } catch (e) {
    return { repos: [], total: 0 }
  }
  if (!data || !Array.isArray(data.repos)) return { repos: [], total: 0 }

  var repos = []
  for (var i = 0; i < data.repos.length && repos.length < MAX_REPOS; i++) {
    var source = data.repos[i]
    if (!source || typeof source !== "object" || Array.isArray(source)) continue
    var id = text(source.id, 64)
    if (!Object.prototype.hasOwnProperty.call(KNOWN_REPO_IDS, id)) continue

    var packages = []
    if (Array.isArray(source.packages)) {
      for (var j = 0; j < source.packages.length && packages.length < MAX_PACKAGES_PER_REPO; j++) {
        var sourcePackage = source.packages[j]
        if (!sourcePackage || typeof sourcePackage !== "object" || Array.isArray(sourcePackage)) continue
        var name = text(sourcePackage.name, MAX_NAME_LEN)
        if (!name) continue
        var behind = count(sourcePackage.behind, MAX_COUNT)
        if (behind > 0) {
          packages.push({ name: name, behind: behind })
        } else {
          packages.push({
            name: name,
            from: text(sourcePackage.from, MAX_VER_LEN),
            to: text(sourcePackage.to, MAX_VER_LEN)
          })
        }
      }
    }

    var repo = {
      id: id,
      name: text(source.name, 80) || id,
      count: count(source.count, MAX_COUNT),
      installed: source.installed === true,
      packages: packages
    }
    if (id === "system") repo.omarchyPending = source.omarchyPending === true
    if (id === "aur") {
      var updater = text(source.updater, 32)
      repo.updater = AUR_HELPERS.indexOf(updater) === -1 ? "" : updater
    }
    repos.push(repo)
  }
  return { repos: repos, total: count(data.total, MAX_COUNT) }
}

// Automatic background scans are on unless explicitly turned off. Off means
// the scanner runs only when the panel is opened or refreshed by hand.
function autoRefreshEnabled(value) {
  return value !== false
}

if (typeof module !== "undefined") {
  module.exports = {
    parseRepoList: parseRepoList,
    updateCommandFor: updateCommandFor,
    autoRefreshEnabled: autoRefreshEnabled,
    boolValue: boolValue,
    text: text,
    count: count,
    MAX_REPOS: MAX_REPOS,
    MAX_PACKAGES_PER_REPO: MAX_PACKAGES_PER_REPO,
    MAX_COUNT: MAX_COUNT,
    KNOWN_REPO_IDS: KNOWN_REPO_IDS,
    AUR_HELPERS: AUR_HELPERS
  }
}
