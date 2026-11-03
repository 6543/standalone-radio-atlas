"""Standalone launcher routes actions to a running instance or starts one."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

PROJECT = Path(__file__).resolve().parents[1]
LAUNCHER = PROJECT / "standalone" / "radio-atlas"


class LauncherTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.app = self.root / "share radio-atlas"
        self.app.mkdir()
        self.calls = self.root / "calls"
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        # Records argv plus the action env, and answers IPC as configured.
        fake = bin_dir / "quickshell"
        fake.write_text(f"""#!/bin/sh
printf '%s|%s\\n' "${{RADIO_ATLAS_ACTION-}}" "$*" >> {self.calls}
if [ "$1" = ipc ]; then
  [ -n "${{FAKE_RUNNING-}}" ] && exit 0
  echo 'No running instances' >&2
  exit 1
fi
exit 0
""")
        fake.chmod(0o755)
        player = self.app / "radio-player"
        player.write_text(f"#!/bin/sh\nprintf 'player|%s\\n' \"$*\" >> {self.calls}\n")
        player.chmod(0o755)
        self.env = dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}",
                        RADIO_ATLAS_DIR=str(self.app))
        self.env.pop("RADIO_ATLAS_ACTION", None)

    def run_launcher(self, *arguments, running=False):
        env = dict(self.env)
        if running:
            env["FAKE_RUNNING"] = "1"
        return subprocess.run([str(LAUNCHER), *arguments], env=env,
                              capture_output=True, text=True, timeout=10)

    def recorded(self):
        return self.calls.read_text().splitlines() if self.calls.exists() else []

    def test_open_starts_single_instance_when_none_runs(self):
        result = self.run_launcher()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.recorded(), [
            f"|ipc -p {self.app} call radio-atlas open",
            f"open|-n -p {self.app}",
        ])

    def test_open_reuses_running_instance(self):
        result = self.run_launcher("open", running=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.recorded(), [f"|ipc -p {self.app} call radio-atlas open"])

    def test_toggle_closes_running_instance(self):
        result = self.run_launcher("toggle", running=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.recorded(), [f"|ipc -p {self.app} call radio-atlas toggle"])

    def test_toggle_opens_when_none_runs(self):
        result = self.run_launcher("toggle")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.recorded()[-1], f"open|-n -p {self.app}")

    def test_random_passes_action_to_new_instance(self):
        result = self.run_launcher("random")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.recorded(), [
            f"|ipc -p {self.app} call radio-atlas random",
            f"random|-n -p {self.app}",
        ])

    def test_random_reuses_running_instance(self):
        result = self.run_launcher("random", running=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.recorded(), [f"|ipc -p {self.app} call radio-atlas random"])

    def test_player_actions_run_without_the_window(self):
        for action in ("stop", "resume"):
            result = self.run_launcher(action)
            self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.recorded(), ["player|stop", "player|resume"])

    def test_unknown_action_prints_usage(self):
        result = self.run_launcher("explode")
        self.assertEqual(result.returncode, 2)
        self.assertIn("usage: radio-atlas", result.stderr)
        self.assertEqual(self.recorded(), [])


if __name__ == "__main__":
    unittest.main()
