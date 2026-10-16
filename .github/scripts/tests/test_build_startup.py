import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

spec = importlib.util.spec_from_file_location("build_release", Path(__file__).parents[1] / "build.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class BuildStartupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)

    def verify(self, output, code=0):
        result = subprocess.CompletedProcess([], code, output, "")
        with mock.patch.object(module.subprocess, "run", return_value=result) as run:
            module.verify_player_startup("fixture_game.exe", self.temp.name, "windows")
            self.assertEqual(run.call_args.args[0][-2:], ["--", "--verify-player-startup"])

    def test_successful_native_bootstrap_is_accepted(self):
        self.verify("PLAYER_STARTUP_RESULT scripts=63 failures=0\n")
        self.assertTrue((Path(self.temp.name) / "validation/windows_player_startup.log").is_file())

    def test_missing_marker_is_fatal(self):
        with self.assertRaises(RuntimeError):
            self.verify("Game started without verification")

    def test_reported_failure_is_fatal_even_with_zero_exit(self):
        with self.assertRaises(RuntimeError):
            self.verify("PLAYER_STARTUP_RESULT scripts=63 failures=1\n")

    def test_script_error_is_fatal_even_with_success_marker(self):
        with self.assertRaises(RuntimeError):
            self.verify("SCRIPT ERROR: missing fixture\nPLAYER_STARTUP_RESULT scripts=63 failures=0\n")

    def test_process_failure_is_fatal(self):
        with self.assertRaises(RuntimeError):
            self.verify("PLAYER_STARTUP_RESULT scripts=63 failures=0\n", 1)


if __name__ == "__main__":
    unittest.main()
