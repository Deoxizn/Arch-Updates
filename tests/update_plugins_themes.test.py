#!/usr/bin/env python3
"""Tests for scripts/update_plugins_themes.py (stdlib unittest, no network).

Run: python3 tests/update_plugins_themes.test.py
"""
import io
import os
import shutil
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))

import update_plugins_themes as upt


def fake_result(returncode=0, stdout=""):
    class R:
        pass

    r = R()
    r.returncode = returncode
    r.stdout = stdout
    r.stderr = ""
    return r


class TestBehindCounts(unittest.TestCase):
    def test_theme_behind_count(self):
        calls = []

        def fake_run_git(args, cwd, timeout=30):
            calls.append(args)
            if args[0] == "fetch":
                return fake_result(0)
            if args[0] == "rev-list":
                return fake_result(0, "3\n")
            return fake_result(1)

        with patch.object(upt, "run_git", side_effect=fake_run_git):
            self.assertEqual(upt.theme_behind_count(Path("/tmp/theme-a")), 3)
        self.assertEqual(calls[0][0], "fetch")
        self.assertEqual(calls[1][:2], ["rev-list", "--count"])

    def test_theme_up_to_date_is_zero(self):
        def fake_run_git(args, cwd, timeout=30):
            if args[0] == "fetch":
                return fake_result(0)
            return fake_result(0, "0\n")

        with patch.object(upt, "run_git", side_effect=fake_run_git):
            self.assertEqual(upt.theme_behind_count(Path("/tmp/theme-a")), 0)

    def test_theme_fetch_failure_is_none(self):
        with patch.object(upt, "run_git", return_value=fake_result(1)):
            self.assertIsNone(upt.theme_behind_count(Path("/tmp/theme-a")))

    def test_plugin_behind_count(self):
        def fake_run_git(args, cwd, timeout=30):
            if args == ["fetch", "--quiet", "origin", "HEAD"]:
                return fake_result(0)
            if args == ["rev-parse", "HEAD"]:
                return fake_result(0, "aaa\n")
            if args == ["rev-parse", "FETCH_HEAD"]:
                return fake_result(0, "bbb\n")
            if args[:2] == ["rev-list", "--count"]:
                return fake_result(0, "2\n")
            return fake_result(1)

        with patch.object(upt, "run_git", side_effect=fake_run_git):
            self.assertEqual(upt.plugin_behind_count(Path("/tmp/plugin-a")), 2)

    def test_plugin_same_head_is_zero(self):
        def fake_run_git(args, cwd, timeout=30):
            if args[0] == "fetch":
                return fake_result(0)
            return fake_result(0, "aaa\n")

        with patch.object(upt, "run_git", side_effect=fake_run_git):
            self.assertEqual(upt.plugin_behind_count(Path("/tmp/plugin-a")), 0)


class TestThemeDirs(unittest.TestCase):
    def test_drops_paths_outside_themes_dir(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp) / "themes"
            inside = base / "tokyo-night"
            outside = Path(tmp) / "evil"
            for d in (inside, outside):
                (d / ".git").mkdir(parents=True)
            # A symlink inside the themes dir pointing outside it resolves
            # outside, so it must be dropped too.
            link = base / "link"
            link.symlink_to(outside, target_is_directory=True)
            stdout = "\n".join([str(inside), str(outside), str(link), "/etc/passwd"])
            with patch.object(upt, "THEMES_DIR", base), patch.object(
                shutil, "which", return_value="/usr/bin/omarchy-theme-extras"
            ), patch.object(upt, "run", return_value=fake_result(0, stdout)):
                self.assertEqual(upt.theme_dirs(), [inside.resolve()])

    def test_no_extras_binary_is_empty(self):
        with patch.object(shutil, "which", return_value=None):
            self.assertEqual(upt.theme_dirs(), [])


class TestMain(unittest.TestCase):
    def run_main(self, themes, plugins):
        """Run main() with dirs and counts stubbed; return (rc, stdout)."""
        theme_dirs = [Path("/tmp/t-" + name) for name, _ in themes]
        plugin_dirs = [Path("/tmp/p-" + name) for name, _ in plugins]
        theme_counts = {Path("/tmp/t-" + n): c for n, c in themes}
        plugin_counts = {Path("/tmp/p-" + n): c for n, c in plugins}
        updated_themes = set()
        updated_plugins = set()

        def fake_update_theme(d):
            updated_themes.add(d.name)
            return True

        def fake_update_plugin(d):
            updated_plugins.add(d.name)
            return True

        patches = [
            patch.object(upt, "theme_dirs", return_value=theme_dirs),
            patch.object(upt, "git_plugin_dirs", return_value=plugin_dirs),
            patch.object(
                upt, "theme_behind_count", side_effect=lambda d: theme_counts[d]
            ),
            patch.object(
                upt, "plugin_behind_count", side_effect=lambda d: plugin_counts[d]
            ),
            patch.object(upt, "update_theme", side_effect=fake_update_theme),
            patch.object(upt, "update_plugin", side_effect=fake_update_plugin),
        ]
        for p in patches:
            p.start()
        try:
            buf = io.StringIO()
            with redirect_stdout(buf):
                rc = upt.main()
            return rc, buf.getvalue(), updated_themes, updated_plugins
        finally:
            for p in patches:
                p.stop()

    def test_only_behind_items_update(self):
        rc, out, updated_themes, updated_plugins = self.run_main(
            themes=[("behind-theme", 2), ("current-theme", 0)],
            plugins=[("behind-plugin", 1), ("current-plugin", 0)],
        )
        self.assertEqual(rc, 0)
        self.assertEqual(updated_themes, {"t-behind-theme"})
        self.assertEqual(updated_plugins, {"p-behind-plugin"})
        self.assertIn("behind-theme", out)
        self.assertIn("behind-plugin", out)
        self.assertIn("current-theme", out)
        self.assertIn("current-plugin", out)

    def test_nothing_behind_is_zero(self):
        rc, out, updated_themes, updated_plugins = self.run_main(
            themes=[("a", 0)], plugins=[("b", 0)]
        )
        self.assertEqual(rc, 0)
        self.assertEqual(updated_themes, set())
        self.assertEqual(updated_plugins, set())
        self.assertIn("Up to date", out)

    def test_failed_update_is_one(self):
        patches = [
            patch.object(upt, "theme_dirs", return_value=[Path("/tmp/t-bad")]),
            patch.object(upt, "git_plugin_dirs", return_value=[]),
            patch.object(upt, "theme_behind_count", return_value=1),
            patch.object(upt, "update_theme", return_value=False),
        ]
        for p in patches:
            p.start()
        try:
            buf = io.StringIO()
            with redirect_stdout(buf):
                rc = upt.main()
            self.assertEqual(rc, 1)
        finally:
            for p in patches:
                p.stop()

    def test_unchecked_item_does_not_update(self):
        rc, out, updated_themes, updated_plugins = self.run_main(
            themes=[("offline-theme", None)], plugins=[]
        )
        self.assertEqual(rc, 0)
        self.assertEqual(updated_themes, set())
        self.assertIn("Could not check", out)


if __name__ == "__main__":
    unittest.main()
