#!/usr/bin/env python3
"""Scan for pending updates and print a JSON document for the arch-updates widget.

Sources: Arch repo (checkupdates), AUR (yay/paru -Qua), Flatpak
(flatpak remote-ls --updates), mise (mise outdated --json), git shell
plugins and git themes. Check-only: nothing here installs anything.
Installs go through `hexciri update` (system, AUR, mise) and, separately,
`hexciri plugin update` / `hexciri theme update` for shell plugins and
themes.

Output is one JSON object on stdout:
  {"repos": [{"id", "name", "count", "installed", "packages", ...}], "total": N}
Each package is {"name", "from", "to"} for a versioned update, or
{"name", "behind"} for a git checkout (plugins/themes have no version).
The "system" repo combines the Arch repo packages with Hexciri itself:
its count is the repo count, plus a hexciri-dev-checkout entry when a
Hexciri checkout is behind its upstream, and "hexciriPending" is true
when that entry is present. (Hexciri is not a pacman package, so no repo
package can ever flag it; the checkout check is the only signal.) There
is only one update action for that repo and it runs `hexciri update`,
never a bare pacman system upgrade: a bare arch update bypasses the
managed pipeline (transcript, keyrings, migrations, post-update hooks).

Per-source toggles (from the widget's settings, passed as flags):
  --no-aur --no-flatpak --no-mise --no-plugins
A disabled source is skipped entirely and reported installed=false.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

MAX_STDOUT_BYTES = 512 * 1024
MAX_LINES = 10000
MAX_PACKAGES = 1000
MAX_NAME_LEN = 200
MAX_VER_LEN = 100

# Where the packaged Hexciri build lives. Any other HEXCIRI_PATH is a dev
# checkout. (There is no Hexciri pacman package: unlike Omarchy's
# ("omarchy", "omarchy-dev"), no repo package can ever carry the Hexciri
# release itself, so the checkout check below is the only pending signal.)
HEXCIRI_SYSTEM_PATH = "/usr/share/hexciri"
CHECKUPDATES_RETRY_DELAY_S = 2
GIT_FETCH_TIMEOUT_S = 15

PLUGINS_DIR = Path(os.path.expanduser("~")) / ".config" / "hexciri" / "plugins"
THEMES_DIR = Path(os.path.expanduser("~")) / ".config" / "hexciri" / "themes"

# An upstream ref from `git rev-parse @{upstream}` (e.g. "origin/main").
# Anything outside this shape is not a ref and must never reach rev-list.
SAFE_GIT_REF_RE = re.compile(r"[A-Za-z0-9._-]+(?:/[A-Za-z0-9._-]+)*")


def is_safe_git_ref(ref):
    """True when ref is a plain branch ref or a full SHA, not an injection."""
    return bool(SAFE_GIT_REF_RE.fullmatch(ref)) and ".." not in ref


def is_under(path, base):
    """True when the resolved path sits under the resolved base dir."""
    try:
        Path(path).resolve().relative_to(Path(base).resolve())
        return True
    except ValueError:
        return False

# `checkupdates`, `pacman -Qu`, and `yay/paru -Qua` all print
# "name oldver -> newver".
VERSION_LINE_RE = re.compile(r"^(\S+)\s+(\S+)\s+->\s+(\S+)$")


def run(command, timeout=30, env=None):
    """Run a command and return its CompletedProcess, or None on failure."""
    try:
        return subprocess.run(
            command, capture_output=True, text=True, timeout=timeout, env=env
        )
    except Exception:
        return None


def command_lines(command, timeout=30, env=None, require_ok=True):
    """Run a command and return its non-empty stdout lines."""
    result = run(command, timeout=timeout, env=env)
    if result is None:
        return []
    if require_ok and result.returncode != 0:
        return []
    out = (result.stdout or "")[:MAX_STDOUT_BYTES]
    return [line for line in out.splitlines()[:MAX_LINES] if line.strip()]


def parse_version_lines(lines):
    """Parse "name oldver -> newver" lines into package entries."""
    packages = []
    for raw in lines[:MAX_PACKAGES]:
        line = raw.strip()[:512]
        if not line:
            continue
        match = VERSION_LINE_RE.match(line)
        if match:
            packages.append(
                {
                    "name": match.group(1)[:MAX_NAME_LEN],
                    "from": match.group(2)[:MAX_VER_LEN],
                    "to": match.group(3)[:MAX_VER_LEN],
                }
            )
            continue
        parts = line.split()
        packages.append(
            {
                "name": parts[0][:MAX_NAME_LEN],
                "from": "",
                "to": parts[1][:MAX_VER_LEN] if len(parts) > 1 else "",
            }
        )
    return packages


def check_repo():
    """Arch repo updates from checkupdates (pacman-contrib)."""
    if shutil.which("checkupdates") is None:
        return []
    result = run(["checkupdates"], timeout=30)
    if result is None:
        return []
    # checkupdates syncs into one temp database per user, so a run elsewhere
    # at the same moment makes it exit 1 with "Cannot fetch updates". Retry
    # once in that case before reporting nothing.
    if result.returncode == 1 and "cannot fetch updates" in (
        result.stderr or ""
    ).lower():
        time.sleep(CHECKUPDATES_RETRY_DELAY_S)
        result = run(["checkupdates"], timeout=30)
        if result is None:
            return []
    # checkupdates exits 2 (with no output) when everything is current.
    return parse_version_lines(
        [line for line in (result.stdout or "").splitlines() if line.strip()]
    )


def aur_helper():
    """The installed AUR helper (yay preferred, then paru), or None."""
    for helper in ("yay", "paru"):
        if shutil.which(helper):
            return helper
    return None


def check_aur(helper):
    """AUR updates from the helper's -Qua output."""
    if helper is None:
        return []
    lines = command_lines([helper, "-Qua"], timeout=120, require_ok=False)
    packages = parse_version_lines(lines)
    for package in packages:
        # -Qua sometimes prefixes names with "aur/".
        if package["name"].startswith("aur/"):
            package["name"] = package["name"][4:]
    return packages


def check_flatpak():
    """Flatpak updates from `flatpak remote-ls --updates`."""
    if shutil.which("flatpak") is None:
        return []
    lines = command_lines(
        ["flatpak", "remote-ls", "--updates", "--columns=application,version"],
        timeout=60,
        require_ok=False,
    )
    packages = []
    for line in lines[:MAX_PACKAGES]:
        parts = line.split()
        if not parts:
            continue
        packages.append(
            {
                "name": parts[0][:MAX_NAME_LEN],
                "from": "",
                "to": parts[-1][:MAX_VER_LEN] if len(parts) > 1 else "",
            }
        )
    return packages


def mise_outdated(binary, release_age):
    """Run `mise outdated --json` and return the parsed object, or None."""
    env = os.environ.copy()
    if release_age is not None:
        env["MISE_MINIMUM_RELEASE_AGE"] = release_age
    result = run(
        [binary, "outdated", "--json"],
        timeout=120,
        env=env,
    )
    if result is None or result.returncode != 0:
        return None
    try:
        data = json.loads(result.stdout or "")
    except Exception:
        return None
    if not isinstance(data, dict):
        return None
    # Some mise builds reject MISE_MINIMUM_RELEASE_AGE=0 but still print
    # "{}" with exit 0, which would read as "everything current". Treat
    # that as a failed probe so the caller can retry without the override.
    if release_age is not None and "invalid date or duration" in (
        result.stderr or ""
    ).lower():
        return None
    return data


def check_mise(binary):
    """mise dev-tool updates from `mise outdated --json`."""
    if binary is None:
        return []
    # Mirror what `hexciri update` installs: hexciri-update-mise runs
    # `MISE_MINIMUM_RELEASE_AGE=0 mise up`, so drop mise's release cooldown
    # to count the versions that command would actually pull in. Fall back
    # to the plain query on mise builds that reject the override.
    outdated = mise_outdated(binary, "0")
    if outdated is None:
        outdated = mise_outdated(binary, None)
    if not outdated:
        return []
    packages = []
    for key, info in outdated.items():
        info = info if isinstance(info, dict) else {}
        current = str(info.get("current") or "")
        latest = str(info.get("latest") or info.get("requested") or "")
        # Hexciri declares lazy system tools in
        # /etc/mise/conf.d/hexciri-tools.toml. `mise outdated --json`
        # reports those not-yet-installed tools with current=null, but
        # `mise up` leaves missing lazy tools alone (they install on first
        # use). Skip them so the count matches what `mise up` pulls in.
        if not current or not latest or current == latest:
            continue
        name = str(key).split("@")[0]
        packages.append(
            {"name": name[:MAX_NAME_LEN], "from": current[:MAX_VER_LEN], "to": latest[:MAX_VER_LEN]}
        )
    return packages


def git_plugin_dirs():
    """Installed Hexciri shell plugins that are git checkouts."""
    try:
        if not PLUGINS_DIR.is_dir():
            return []
        return sorted(d for d in PLUGINS_DIR.iterdir() if (d / ".git").is_dir())
    except Exception:
        return []


def run_git(args, cwd, timeout=GIT_FETCH_TIMEOUT_S):
    """Run git in a plugin checkout without letting its config run code.

    A plugin is an untrusted checkout: its .git/config can name an ext::
    transport or a core.fsmonitor command, both of which run shell code
    during what looks like a harmless fetch. Restrict the transports and
    disable the config-driven monitor for this repo.
    """
    env = os.environ.copy()
    env["GIT_TERMINAL_PROMPT"] = "0"
    env.setdefault("GIT_SSH_COMMAND", "ssh -oBatchMode=yes")
    env["GIT_ALLOW_PROTOCOL"] = "https:ssh"
    return run(
        ["git", "-c", "core.fsmonitor=false", "-C", str(cwd), *args],
        timeout=timeout,
        env=env,
    )


def checked_out_branch(dir_path):
    """The checked-out branch name, or None when detached/unknown.

    A plugin on nyx must be compared against nyx, not origin HEAD
    (main): main moving ahead would otherwise count a fully up-to-date
    nyx plugin as behind forever, and the updater (which pulls the
    checked-out branch) would never clear it.
    """
    head = run_git(["rev-parse", "--abbrev-ref", "HEAD"], dir_path, timeout=15)
    if head is None or head.returncode != 0:
        return None
    branch = (head.stdout or "").strip()
    if not branch or branch == "HEAD" or not is_safe_git_ref(branch):
        return None
    return branch


def plugin_behind(dir_path):
    """A package entry for a plugin behind its checked-out branch, else None.

    Mirrors `hexciri-plugin-update` (patched 2026-11-24): fetch the
    checked-out branch, then count the commits FETCH_HEAD has that HEAD
    lacks; detached HEAD falls back to origin HEAD. Offline plugins, and
    checkouts only ahead of their branch (local work), are skipped: the
    updater has nothing to pull for them.
    """
    branch = checked_out_branch(dir_path)
    if branch is not None:
        fetch = run_git(["fetch", "--quiet", "origin", branch], dir_path)
    else:
        fetch = run_git(["fetch", "--quiet", "origin", "HEAD"], dir_path)
    if fetch is None or fetch.returncode != 0:
        return None
    head = run_git(["rev-parse", "HEAD"], dir_path)
    upstream = run_git(["rev-parse", "FETCH_HEAD"], dir_path)
    if head is None or upstream is None:
        return None
    if head.returncode != 0 or upstream.returncode != 0:
        return None
    head_sha = (head.stdout or "").strip()
    upstream_sha = (upstream.stdout or "").strip()
    if not head_sha or not upstream_sha or head_sha == upstream_sha:
        return None
    behind = run_git(["rev-list", "--count", "HEAD..FETCH_HEAD"], dir_path)
    count = (behind.stdout or "").strip() if behind is not None and behind.returncode == 0 else ""
    if not count.isdigit() or count == "0":
        return None
    return {"name": dir_path.name[:MAX_NAME_LEN], "behind": int(count)}


def check_plugins(dirs):
    """Behind counts for every git-managed shell plugin."""
    if not dirs:
        return []
    # Each plugin is an independent network fetch; run a bounded number
    # concurrently so a large plugin collection cannot fan out unbounded.
    with ThreadPoolExecutor(max_workers=min(len(dirs), 4)) as pool:
        results = list(pool.map(plugin_behind, dirs))
    return [entry for entry in results if entry is not None]


def theme_dirs():
    """Git theme checkouts from hexciri-theme-extras."""
    if shutil.which("hexciri-theme-extras") is None:
        return []
    lines = command_lines(["hexciri-theme-extras"], timeout=30)
    dirs = []
    for line in lines:
        # hexciri-theme-extras only lists ~/.config/hexciri/themes/*, but
        # trust the listing, not the source: resolve symlinks and drop
        # anything outside the themes dir before git ever touches it.
        path = Path(line.strip()).resolve()
        if is_under(path, THEMES_DIR) and (path / ".git").is_dir():
            dirs.append(path)
    return dirs


def theme_behind(dir_path):
    """A package entry for a theme behind its upstream, else None."""
    fetch = run_git(["fetch", "--quiet"], dir_path, timeout=30)
    if fetch is None or fetch.returncode != 0:
        return None
    behind = run_git(
        ["rev-list", "--count", "HEAD..@{upstream}"], dir_path, timeout=15
    )
    count = (behind.stdout or "").strip() if behind is not None and behind.returncode == 0 else ""
    if not count.isdigit() or count == "0":
        return None
    return {"name": dir_path.name[:MAX_NAME_LEN], "behind": int(count)}


def check_themes(dirs):
    """Behind counts for every git-managed theme."""
    if not dirs:
        return []
    with ThreadPoolExecutor(max_workers=min(len(dirs), 4)) as pool:
        results = list(pool.map(theme_behind, dirs))
    return [entry for entry in results if entry is not None]


def _checkout_behind(checkout):
    """A behind entry for one Hexciri checkout dir, else None."""
    if not checkout.is_dir() or not (checkout / ".git").is_dir():
        return None
    upstream = run_git(
        ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"],
        checkout,
        timeout=15,
    )
    if upstream is None or upstream.returncode != 0 or not (upstream.stdout or "").strip():
        return None
    ref = (upstream.stdout or "").strip()
    # rev-parse output goes straight into rev-list below, so reject
    # anything that is not a plain ref or a full SHA first.
    if not is_safe_git_ref(ref):
        return None
    run_git(["fetch", "--quiet"], checkout, timeout=10)
    behind = run_git(
        ["rev-list", "--count", "HEAD..%s" % ref],
        checkout,
        timeout=15,
    )
    count = (behind.stdout or "").strip() if behind is not None and behind.returncode == 0 else ""
    if not count.isdigit() or count == "0":
        return None
    return {"name": "hexciri-dev-checkout", "behind": int(count)}


def hexciri_checkout_behind():
    """A package entry for a Hexciri checkout behind upstream, else None.

    Two checkouts can carry Hexciri itself, in priority order:
    1. $HEXCIRI_PATH when it points at a git checkout other than the
       packaged build at HEXCIRI_SYSTEM_PATH (/usr/share/hexciri): the
       dev-checkout case, the exact analog of Omarchy's OMARCHY_PATH.
    2. ~/.local/opt/hexciri-nyx, the installer-repo clone that
       `hexciri update` maintains (clone once, then fetch/pull). On a
       normal install this is the checkout that is actually behind when
       a Hexciri update is out, so it is the live pending signal.
    Either one behind upstream reports as hexciri-dev-checkout.
    """
    path = os.environ.get("HEXCIRI_PATH", "").rstrip("/")
    if path and path != HEXCIRI_SYSTEM_PATH:
        entry = _checkout_behind(Path(path))
        if entry is not None:
            return entry
    return _checkout_behind(
        Path(os.path.expanduser("~")) / ".local" / "opt" / "hexciri-nyx"
    )


def collect_repo(repo_id, name, packages, installed, **extra):
    entry = {
        "id": repo_id,
        "name": name,
        "count": len(packages),
        "installed": installed,
        "packages": packages,
    }
    entry.update(extra)
    return entry


def main(argv=None):
    parser = argparse.ArgumentParser(description="Check for pending updates.")
    parser.add_argument("--no-aur", action="store_true", help="Skip the AUR check")
    parser.add_argument("--no-flatpak", action="store_true", help="Skip the Flatpak check")
    parser.add_argument("--no-mise", action="store_true", help="Skip the mise check")
    parser.add_argument("--no-plugins", action="store_true", help="Skip the plugins and themes check")
    args = parser.parse_args(argv)

    helper = aur_helper()
    flatpak_installed = shutil.which("flatpak") is not None
    mise = shutil.which("mise")
    plugin_dirs = git_plugin_dirs()
    themes = theme_dirs()

    # Sources are independent subprocesses (repo DB sync, AUR RPC,
    # Flatpak remote, mise, git fetches). Run them in parallel: the
    # sequential scan summed to minutes, and the widget's fast poll
    # (10s ticks, 30-poll budget) could expire before any fresh result
    # landed, leaving the badge stale until the 1800s timer. Output
    # shape is unchanged; each source keeps its own timeout.
    with ThreadPoolExecutor(max_workers=7) as pool:
        f_repo = pool.submit(check_repo)
        f_aur = pool.submit(check_aur, helper) if not args.no_aur else None
        f_flatpak = pool.submit(check_flatpak) if not args.no_flatpak else None
        f_mise = pool.submit(check_mise, mise) if not args.no_mise else None
        f_checkout = pool.submit(hexciri_checkout_behind)
        f_plugins = pool.submit(check_plugins, plugin_dirs) if not args.no_plugins else None
        f_themes = pool.submit(check_themes, themes) if not args.no_plugins else None
        repo_updates = f_repo.result()
        aur_updates = [] if f_aur is None else f_aur.result()
        flatpak_updates = [] if f_flatpak is None else f_flatpak.result()
        mise_updates = [] if f_mise is None else f_mise.result()
        checkout = f_checkout.result()
        plugin_updates = [] if f_plugins is None else f_plugins.result()
        theme_updates = [] if f_themes is None else f_themes.result()

    # The combined Hexciri + Arch repo: the repo packages, plus the
    # Hexciri checkout behind entry when there is one. No Hexciri package
    # rides inside the repo list (Hexciri is not a pacman package), so
    # the checkout entry is the only Hexciri-pending signal.
    system_packages = list(repo_updates)
    if checkout is not None:
        system_packages.insert(0, checkout)
    hexciri_pending = checkout is not None

    repos = [
        collect_repo(
            "system",
            "System",
            system_packages,
            True,
            hexciriPending=hexciri_pending,
        ),
        collect_repo(
            "aur",
            "AUR",
            aur_updates,
            helper is not None and not args.no_aur,
            updater=helper or "",
        ),
        collect_repo(
            "flatpak",
            "Flatpak",
            flatpak_updates,
            flatpak_installed and not args.no_flatpak,
        ),
        collect_repo(
            "plugins",
            "Plugins & Themes",
            plugin_updates + theme_updates,
            bool(plugin_dirs or themes) and not args.no_plugins,
        ),
        collect_repo(
            "mise",
            "mise",
            mise_updates,
            mise is not None and not args.no_mise,
        ),
    ]

    total = sum(repo["count"] for repo in repos)
    print(json.dumps({"repos": repos, "total": total}, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
