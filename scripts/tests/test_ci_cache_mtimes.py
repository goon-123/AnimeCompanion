import importlib.util
import os
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("mtimes", Path(__file__).resolve().parents[1] / "ci-cache-mtimes.py")
mtimes = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mtimes)


class CacheTimestampTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "App").mkdir()
        self.source = self.root / "App/View.swift"
        self.source.write_text("original")
        os.utime(self.source, ns=(1_700_000_000_123456789,) * 2)
        self.saved = mtimes.snapshot(self.root, ["App"])

    def test_unchanged_input_restores_nanoseconds(self):
        os.utime(self.source, ns=(1_800_000_000_999999999,) * 2)
        mtimes.restore(self.root, ["App"], self.saved)
        self.assertEqual(self.source.stat().st_mtime_ns, 1_700_000_000_123456789)

    def test_changed_input_keeps_new_timestamp(self):
        self.source.write_text("modified")
        timestamp = self.source.stat().st_mtime_ns
        mtimes.restore(self.root, ["App"], self.saved)
        self.assertEqual(self.source.stat().st_mtime_ns, timestamp)

    def test_added_or_deleted_files_invalidate_directory(self):
        (self.root / "App/New.swift").write_text("new")
        directory_timestamp = (self.root / "App").stat().st_mtime_ns
        mtimes.restore(self.root, ["App"], self.saved)
        self.assertEqual((self.root / "App").stat().st_mtime_ns, directory_timestamp)
        self.source.unlink()
        mtimes.restore(self.root, ["App"], self.saved)
        self.assertFalse(self.source.exists())

    def test_cached_path_cannot_escape_allowed_inputs(self):
        outside = self.root / "outside.swift"
        outside.write_text("original")
        timestamp = outside.stat().st_mtime_ns
        self.saved["outside.swift"] = self.saved["App/View.swift"]
        self.saved["../outside.swift"] = self.saved["App/View.swift"]
        mtimes.restore(self.root, ["App"], self.saved)
        self.assertEqual(outside.stat().st_mtime_ns, timestamp)

    def test_symlink_is_not_restored(self):
        self.source.unlink()
        outside = self.root / "outside.swift"
        outside.write_text("original")
        self.source.symlink_to(outside)
        timestamp = outside.stat().st_mtime_ns
        mtimes.restore(self.root, ["App"], self.saved)
        self.assertEqual(outside.stat().st_mtime_ns, timestamp)


if __name__ == "__main__":
    unittest.main()
