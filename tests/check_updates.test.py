#!/usr/bin/env python3
"""Tests for scripts/check_updates.py (stdlib unittest, no network).

Run: python3 tests/check_updates.test.py
"""
import io
import json
import os
import shutil
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))

import check_updates


def fake_result(returncode=0, stdout=""):
    class R:
        pass

    r = R()
    r.returncode = returncode
    r.stdout = stdout
    r.stderr = ""
    return r


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


class TestThemeBehind(unittest.TestCase):
    def test_goes_through_run_git_not_raw_run(self):
        calls = []

        def fake_run_git(args, cwd, timeout=15):
            calls.append(args)
            if args[0] == "fetch":
                return fake_result(0)
            return fake_result(0, "2\n")

        # run_git is stubbed, so any raw git via run() would surface here.
        with patch.object(check_updates, "run_git", side_effect=fake_run_git), patch.object(
            check_updates, "run", side_effect=AssertionError("raw run() must not be used")
        ):
            entry = check_updates.theme_behind(Path("/tmp/theme-a"))
        self.assertEqual(entry, {"name": "theme-a", "behind": 2})
        self.assertEqual(calls[0][0], "fetch")
        self.assertEqual(calls[1][:2], ["rev-list", "--count"])

    def test_fetch_failure_is_none(self):
        with patch.object(check_updates, "run_git", return_value=fake_result(1)):
            self.assertIsNone(check_updates.theme_behind(Path("/tmp/theme-a")))


class TestHexciriCheckoutBehind(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.checkout = Path(self.tmp.name) / "hexciri"
        (self.checkout / ".git").mkdir(parents=True)

    def tearDown(self):
        self.tmp.cleanup()

    def run_checkout(self, ref_stdout, ref_rc=0):
        calls = []

        def fake_run_git(args, cwd, timeout=15):
            calls.append(args)
            if args[0] == "rev-parse":
                return fake_result(ref_rc, ref_stdout)
            if args[0] == "fetch":
                return fake_result(0)
            if args[0] == "rev-list":
                return fake_result(0, "4\n")
            return fake_result(1)

        with patch.dict(
            os.environ,
            {"HEXCIRI_PATH": str(self.checkout), "HOME": self.tmp.name},
        ), patch.object(check_updates, "run_git", side_effect=fake_run_git):
            return check_updates.hexciri_checkout_behind(), calls

    def test_valid_ref_counts_behind(self):
        entry, calls = self.run_checkout("origin/main\n")
        self.assertEqual(entry, {"name": "hexciri-dev-checkout", "behind": 4})
        self.assertIn(["rev-list", "--count", "HEAD..origin/main"], calls)

    def test_nyx_clone_fallback_when_no_dev_checkout(self):
        # No HEXCIRI_PATH (packaged build): the ~/.local/opt/hexciri-nyx
        # installer-repo clone is the live pending signal.
        home = Path(self.tmp.name)
        clone = home / ".local" / "opt" / "hexciri-nyx"
        (clone / ".git").mkdir(parents=True)

        def fake_run_git(args, cwd, timeout=15):
            if args[0] == "rev-parse":
                return fake_result(0, "origin/nyx\n")
            if args[0] == "fetch":
                return fake_result(0)
            if args[0] == "rev-list":
                return fake_result(0, "2\n")
            return fake_result(1)

        env = {"HEXCIRI_PATH": "/usr/share/hexciri", "HOME": str(home)}
        with patch.dict(os.environ, env), patch.object(
            check_updates, "run_git", side_effect=fake_run_git
        ):
            self.assertEqual(
                check_updates.hexciri_checkout_behind(),
                {"name": "hexciri-dev-checkout", "behind": 2},
            )

    def test_packaged_build_with_no_clone_is_none(self):
        with patch.dict(
            os.environ,
            {"HEXCIRI_PATH": "/usr/share/hexciri", "HOME": self.tmp.name},
        ):
            self.assertIsNone(check_updates.hexciri_checkout_behind())

    def test_full_sha_ref_is_accepted(self):
        entry, _ = self.run_checkout("a" * 40 + "\n")
        self.assertEqual(entry, {"name": "hexciri-dev-checkout", "behind": 4})

    def test_malicious_ref_is_rejected_before_rev_list(self):
        entry, calls = self.run_checkout("origin/main --upload-pack=touch /tmp/pwned\n")
        self.assertIsNone(entry)
        self.assertFalse(any(args[0] == "rev-list" for args in calls))

    def test_dotdot_ref_is_rejected(self):
        entry, calls = self.run_checkout("origin/../../etc/passwd\n")
        self.assertIsNone(entry)
        self.assertFalse(any(args[0] == "rev-list" for args in calls))

    def test_goes_through_run_git_not_raw_run(self):
        with patch.dict(
            os.environ,
            {"HEXCIRI_PATH": str(self.checkout), "HOME": self.tmp.name},
        ), patch.object(
            check_updates, "run_git", side_effect=lambda *a, **k: fake_result(1)
        ), patch.object(
            check_updates, "run", side_effect=AssertionError("raw run() must not be used")
        ):
            self.assertIsNone(check_updates.hexciri_checkout_behind())


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
            lines = [str(inside), str(outside), str(link), "/etc/passwd", ""]
            with patch.object(check_updates, "THEMES_DIR", base), patch.object(
                shutil, "which", return_value="/usr/bin/hexciri-theme-extras"
            ), patch.object(check_updates, "command_lines", return_value=lines):
                self.assertEqual(check_updates.theme_dirs(), [inside.resolve()])


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
            patch.object(check_updates, "hexciri_checkout_behind", return_value=stubs.get("checkout")),
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
        # The repo packages land in the combined section; with no
        # Hexciri checkout behind, hexciriPending stays false.
        data = self.run_main(
            [],
            {
                "repo": [
                    {"name": "linux", "from": "6.15.2-1", "to": "6.15.3-1"},
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
        self.assertEqual(system["name"], "System")
        self.assertEqual(system["count"], 2)
        self.assertTrue(system["installed"])
        self.assertFalse(system["hexciriPending"])
        self.assertEqual(by_id["aur"]["updater"], "yay")
        self.assertEqual(by_id["plugins"]["count"], 1)
        self.assertEqual(by_id["plugins"]["packages"][0]["behind"], 3)
        # Total counts every pending update once.
        self.assertEqual(data["total"], 2 + 1 + 1 + 1 + 1)

    def test_hexciri_checkout_behind_flags_pending(self):
        # A behind Hexciri checkout joins the system repo first and
        # flags hexciriPending; the repo packages still count once each.
        data = self.run_main(
            [],
            {
                "repo": [
                    {"name": "firefox", "from": "140.0-1", "to": "141.0-1"},
                    {"name": "linux", "from": "6.15.2-1", "to": "6.15.3-1"},
                ],
                "checkout": {"name": "hexciri-dev-checkout", "behind": 4},
            },
            which=lambda name: "/usr/bin/" + name,
        )
        by_id = {repo["id"]: repo for repo in data["repos"]}
        system = by_id["system"]
        self.assertEqual(system["count"], 3)
        self.assertTrue(system["hexciriPending"])
        self.assertEqual(system["packages"][0]["name"], "hexciri-dev-checkout")
        self.assertEqual(system["packages"][0]["behind"], 4)
        self.assertEqual(data["total"], 3)

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
