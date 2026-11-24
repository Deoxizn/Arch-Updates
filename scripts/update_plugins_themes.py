#!/usr/bin/env python3
"""Update only the Hexciri shell plugins and git themes behind upstream.

Replaces the blanket `hexciri plugin update --yes; hexciri theme update`,
which touches every plugin and pulls every theme on each run. This script
checks each checkout first (fetch + behind count) and only updates the
ones that actually have something to pull, so up-to-date plugins and
themes are left alone.

Plugins update through `hexciri plugin update <id> --yes`, which reuses
Hexciri's own validation and rollback. Themes update with a
fast-forward-only pull, so a theme with local changes fails cleanly
instead of merging.

Prints what it updated, what was already up to date, and what failed.
Exits 0 when everything that needed updating succeeded (or nothing
needed it), 1 when any update failed.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

GIT_FETCH_TIMEOUT_S = 30
GIT_UPDATE_TIMEOUT_S = 120
PLUGIN_UPDATE_TIMEOUT_S = 180

PLUGINS_DIR = Path(os.path.expanduser("~")) / ".config" / "hexciri" / "plugins"
THEMES_DIR = Path(os.path.expanduser("~")) / ".config" / "hexciri" / "themes"


def is_under(path, base):
    """True when the resolved path sits under the resolved base dir."""
    try:
        Path(path).resolve().relative_to(Path(base).resolve())
        return True
    except ValueError:
        return False


def run(command, timeout=30, env=None):
    try:
        return subprocess.run(
            command, capture_output=True, text=True, timeout=timeout, env=env
        )
    except (subprocess.TimeoutExpired, OSError):
        return None


def run_git(args, cwd, timeout=GIT_FETCH_TIMEOUT_S):
    """Run git in a checkout without letting its config run code.

    A plugin or theme is an untrusted checkout: its .git/config can name
    an ext:: transport or a core.fsmonitor command, both of which run
    shell code during what looks like a harmless fetch. Restrict the
    transports and disable the config-driven monitor for this repo.
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


def git_plugin_dirs():
    """Installed Hexciri shell plugins that are git checkouts."""
    try:
        if not PLUGINS_DIR.is_dir():
            return []
        return sorted(d for d in PLUGINS_DIR.iterdir() if (d / ".git").is_dir())
    except Exception:
        return []


def theme_dirs():
    """Git theme checkouts from hexciri-theme-extras."""
    if shutil.which("hexciri-theme-extras") is None:
        return []
    result = run(["hexciri-theme-extras"], timeout=30)
    if result is None or result.returncode != 0:
        return []
    dirs = []
    for line in (result.stdout or "").splitlines():
        # hexciri-theme-extras only lists ~/.config/hexciri/themes/*, but
        # trust the listing, not the source: resolve symlinks and drop
        # anything outside the themes dir before git ever touches it.
        path = Path(line.strip()).resolve()
        if is_under(path, THEMES_DIR) and (path / ".git").is_dir():
            dirs.append(path)
    return dirs


def theme_behind_count(dir_path):
    """Commits dir_path is behind its upstream, or None if unknown.

    Mirrors the scanner's theme_behind: fetch, then count HEAD..@{upstream}.
    """
    fetch = run_git(["fetch", "--quiet"], dir_path)
    if fetch is None or fetch.returncode != 0:
        return None
    behind = run_git(
        ["rev-list", "--count", "HEAD..@{upstream}"], dir_path, timeout=15
    )
    count = (
        (behind.stdout or "").strip()
        if behind is not None and behind.returncode == 0
        else ""
    )
    if not count.isdigit():
        return None
    return int(count)


def checked_out_branch(dir_path):
    """The checked-out branch name, or None when detached/unknown."""
    head = run_git(["rev-parse", "--abbrev-ref", "HEAD"], dir_path, timeout=15)
    if head is None or head.returncode != 0:
        return None
    branch = (head.stdout or "").strip()
    if not branch or branch == "HEAD":
        return None
    return branch


def plugin_behind_count(dir_path):
    """Commits dir_path is behind its checked-out branch, or None if unknown.

    Mirrors the scanner's plugin_behind and `hexciri-plugin-update`
    (patched 2026-11-24): fetch the checked-out branch, not origin
    HEAD (main), or a nyx plugin counts as behind main forever while
    the updater pulls nyx and never clears it. A checkout only ahead
    of its branch (local work, a feature branch) counts as 0: the
    updater has nothing to pull for it.
    """
    branch = checked_out_branch(dir_path)
    if branch is not None:
        fetch = run_git(["fetch", "--quiet", "origin", branch], dir_path)
    else:
        fetch = run_git(["fetch", "--quiet", "origin", "HEAD"], dir_path)
    if fetch is None or fetch.returncode != 0:
        return None
    head = run_git(["rev-parse", "HEAD"], dir_path, timeout=15)
    upstream = run_git(["rev-parse", "FETCH_HEAD"], dir_path, timeout=15)
    if head is None or upstream is None:
        return None
    if head.returncode != 0 or upstream.returncode != 0:
        return None
    head_sha = (head.stdout or "").strip()
    upstream_sha = (upstream.stdout or "").strip()
    if not head_sha or not upstream_sha or head_sha == upstream_sha:
        return 0
    behind = run_git(
        ["rev-list", "--count", "HEAD..FETCH_HEAD"], dir_path, timeout=15
    )
    count = (
        (behind.stdout or "").strip()
        if behind is not None and behind.returncode == 0
        else ""
    )
    if not count.isdigit():
        return None
    return int(count)


def update_theme(dir_path):
    """Fast-forward-only pull for a behind theme. True on success."""
    result = run_git(["pull", "--ff-only"], dir_path, timeout=GIT_UPDATE_TIMEOUT_S)
    return result is not None and result.returncode == 0


def update_plugin(dir_path):
    """Update one behind plugin through Hexciri. True on success."""
    result = run(
        ["hexciri", "plugin", "update", dir_path.name, "--yes"],
        timeout=PLUGIN_UPDATE_TIMEOUT_S,
    )
    return result is not None and result.returncode == 0


def main():
    updated = []
    up_to_date = []
    unchecked = []
    failed = []

    for dir_path in theme_dirs():
        count = theme_behind_count(dir_path)
        if count is None:
            unchecked.append(dir_path.name)
            continue
        if count == 0:
            up_to_date.append(dir_path.name)
            continue
        if update_theme(dir_path):
            updated.append(dir_path.name)
        else:
            failed.append(dir_path.name)

    for dir_path in git_plugin_dirs():
        count = plugin_behind_count(dir_path)
        if count is None:
            unchecked.append(dir_path.name)
            continue
        if count == 0:
            up_to_date.append(dir_path.name)
            continue
        if update_plugin(dir_path):
            updated.append(dir_path.name)
        else:
            failed.append(dir_path.name)

    if updated:
        print("Updated: " + ", ".join(updated))
    if up_to_date:
        print("Up to date: " + ", ".join(up_to_date))
    if unchecked:
        print("Could not check: " + ", ".join(unchecked))
    if failed:
        print("Failed: " + ", ".join(failed), file=sys.stderr)
        return 1
    if not updated and not up_to_date and not unchecked:
        print("No plugins or themes found.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
