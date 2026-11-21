#!/usr/bin/env python3
"""Tests for scripts/check_updates.py (stdlib unittest, no network).

Run: python3 tests/check_updates.test.py
"""
import io
import json
import os
import shutil
import sys
import unittest
from contextlib import redirect_stdout
from unittest.mock import patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))

import check_updates


class TestParseVersionLines(unittest.TestCase):
    def test_name_old_new(self):
        lines = ["firefox 140.0-1 -> 141.0-1", "linux 6.15.2-1 -> 6.15.3-1"]
        parsed = check_updates.parse_version_lines(lines)
        self.assertEqual(
            parsed,
            [
                {"name": "firefox", "from": "140.0-1", "to": "141.0-1"},
                {"name": "linux", "from": "6.15.2-1", "to": "6.15.3-1"},
            ],
        )

    def test_empty_and_malformed_lines(self):
        self.assertEqual(check_updates.parse_version_lines([]), [])
        self.assertEqual(check_updates.parse_version_lines(["", "   "]), [])
        # A line with no version arrow still yields a name-only entry.
        parsed = check_updates.parse_version_lines(["somepackage"])
        self.assertEqual(parsed[0]["name"], "somepackage")
        self.assertEqual(parsed[0]["from"], "")

    def test_bounded(self):
        lines = ["pkg%d 1 -> 2" % i for i in range(check_updates.MAX_PACKAGES + 50)]
        parsed = check_updates.parse_version_lines(lines)
        self.assertEqual(len(parsed), check_updates.MAX_PACKAGES)


class TestCollectRepo(unittest.TestCase):
    def test_count_is_package_count(self):
        repo = check_updates.collect_repo(
            "aur", "AUR", [{"name": "a", "from": "1", "to": "2"}], True, updater="yay"
        )
        self.assertEqual(repo["count"], 1)
        self.assertEqual(repo["updater"], "yay")
        self.assertTrue(repo["installed"])


class TestMainContract(unittest.TestCase):
    def run_main(self, argv, stubs, which):
        """Run main() with the check functions stubbed; return parsed JSON."""
        patches = [
            patch.object(check_updates, "check_repo", return_value=stubs.get("repo", [])),
            patch.object(check_updates, "aur_helper", return_value=stubs.get("helper")),
            patch.object(check_updates, "check_aur", return_value=stubs.get("aur", [])),
            patch.object(check_updates, "check_flatpak", return_value=stubs.get("flatpak", [])),
            patch.object(check_updates, "check_mise", return_value=stubs.get("mise", [])),
            patch.object(check_updates, "omarchy_checkout_behind", return_value=stubs.get("checkout")),
            patch.object(check_updates, "git_plugin_dirs", return_value=stubs.get("plugin_dirs", [])),
            patch.object(check_updates, "theme_dirs", return_value=stubs.get("theme_dirs", [])),
            patch.object(check_updates, "check_plugins", return_value=stubs.get("plugins", [])),
            patch.object(check_updates, "check_themes", return_value=stubs.get("themes", [])),
            patch.object(shutil, "which", side_effect=which),
        ]
        for p in patches:
            p.start()
        try:
            buf = io.StringIO()
            with redirect_stdout(buf):
                rc = check_updates.main(argv)
            self.assertEqual(rc, 0)
            return json.loads(buf.getvalue())
        finally:
            for p in patches:
                p.stop()

    def test_combined_system_repo_and_total(self):
        # The omarchy package rides inside the repo list; the combined
        # section counts it once and flags omarchyPending.
        data = self.run_main(
            [],
            {
                "repo": [
                    {"name": "omarchy", "from": "4.5.0-1", "to": "4.5.1-1"},
                    {"name": "firefox", "from": "140.0-1", "to": "141.0-1"},
                ],
                "helper": "yay",
                "aur": [{"name": "brave-bin", "from": "1.0", "to": "1.1"}],
                "flatpak": [{"name": "org.gimp.GIMP", "from": "", "to": "3.0"}],
                "mise": [{"name": "node", "from": "22.0.0", "to": "22.1.0"}],
                "plugins": [{"name": "pizza.dirty.nyxiri", "behind": 3}],
            },
            which=lambda name: "/usr/bin/" + name,
        )
        by_id = {repo["id"]: repo for repo in data["repos"]}
        self.assertEqual(set(by_id), {"system", "aur", "flatpak", "plugins", "mise"})
        system = by_id["system"]
        self.assertEqual(system["name"], "Omarchy + Arch")
        self.assertEqual(system["count"], 2)
        self.assertTrue(system["installed"])
        self.assertTrue(system["omarchyPending"])
        self.assertEqual(by_id["aur"]["updater"], "yay")
        self.assertEqual(by_id["plugins"]["count"], 1)
        self.assertEqual(by_id["plugins"]["packages"][0]["behind"], 3)
        # Total counts every pending update once.
        self.assertEqual(data["total"], 2 + 1 + 1 + 1 + 1)

    def test_no_aur_flag_hides_the_row(self):
        data = self.run_main(
            ["--no-aur"],
            {
                "repo": [],
                "helper": "yay",
                "aur": [{"name": "brave-bin", "from": "1.0", "to": "1.1"}],
            },
            which=lambda name: "/usr/bin/" + name,
        )
        by_id = {repo["id"]: repo for repo in data["repos"]}
        self.assertFalse(by_id["aur"]["installed"])
        self.assertEqual(by_id["aur"]["count"], 0)
        self.assertEqual(data["total"], 0)

    def test_no_helper_hides_aur(self):
        data = self.run_main(
            [],
            {"repo": [], "helper": None, "aur": []},
            which=lambda name: None,
        )
        by_id = {repo["id"]: repo for repo in data["repos"]}
        self.assertFalse(by_id["aur"]["installed"])
        self.assertEqual(by_id["aur"]["updater"], "")


if __name__ == "__main__":
    unittest.main()
