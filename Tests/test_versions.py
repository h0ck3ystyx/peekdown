"""Version synchronization must reject drift and malformed input without edits."""
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

class Versions(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for name in ["VERSION", "BUILD_NUMBER", "project.yml", "Packaging", "scripts/sync-version.py"]:
            source, dest = ROOT / name, self.root / name
            dest.parent.mkdir(parents=True, exist_ok=True)
            if source.is_dir():
                shutil.copytree(source, dest)
            else:
                shutil.copy2(source, dest)

    def run_sync(self, *args):
        return subprocess.run(["python3", "scripts/sync-version.py", *args],
                              cwd=self.root, capture_output=True)

    def test_build_drift_and_repair(self):
        (self.root / "BUILD_NUMBER").write_text("11\n")
        self.assertNotEqual(self.run_sync("--check").returncode, 0)
        self.assertEqual(self.run_sync().returncode, 0)
        self.assertEqual(self.run_sync("--check").returncode, 0)

    def test_invalid_input_does_not_edit(self):
        before = (self.root / "project.yml").read_bytes()
        for name, value in [("VERSION", "1.0/invalid"), ("BUILD_NUMBER", "0")]:
            path = self.root / name
            original = path.read_bytes()
            path.write_text(value)
            self.assertNotEqual(self.run_sync().returncode, 0)
            self.assertEqual((self.root / "project.yml").read_bytes(), before)
            path.write_bytes(original)

    def test_missing_plist_key_does_not_partially_sync(self):
        path = self.root / "Packaging/ThumbExt-Info.plist"
        path.write_text(path.read_text().replace("CFBundleVersion", "MissingBuild"))
        before = (self.root / "project.yml").read_bytes()
        (self.root / "BUILD_NUMBER").write_text("11\n")
        self.assertNotEqual(self.run_sync().returncode, 0)
        self.assertEqual((self.root / "project.yml").read_bytes(), before)

if __name__ == "__main__":
    unittest.main()
