import importlib.util
import pathlib
import plistlib
import tempfile
import unittest
import sys

sys.dont_write_bytecode = True

spec = importlib.util.spec_from_file_location("privacy", pathlib.Path(__file__).with_name("check-release-privacy.py"))
privacy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(privacy)


class ReleasePrivacyTests(unittest.TestCase):
    def test_real_shaped_keys_are_detected_without_exposing_the_value(self):
        value = b"mb-" + b"Z" * 48
        findings = privacy.scan_bytes(b"header\n" + value, "app")
        self.assertTrue(findings)
        self.assertEqual(findings[0]["line"], 2)
        self.assertNotIn(value.decode(), str(findings))

    def test_examples_and_generic_crypto_parser_strings_are_allowed(self):
        self.assertFalse(privacy.scan_bytes(b'api_key = "your_example_key_goes_here"', "source"))
        self.assertFalse(privacy.scan_bytes(b"-----BEGIN PRIVATE KEY-----", "crypto-parser"))

    def test_debug_seeds_and_private_device_resources_block_packaging(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            (root / "Info.plist").write_bytes(plistlib.dumps({"CFBundleName": "AnimeCompanion"}))
            (root / "account.sqlite").write_bytes(b"private local data")
            (root / "app").write_bytes(b"--ui-onboarding-preview")
            findings = privacy.scan_bundle(root)
            self.assertEqual({x["kind"] for x in findings}, {"private/device or test-only resource", "debug account/setup fixture in Release"})

    def test_public_anilist_app_id_is_not_a_personal_credential(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            (root / "Info.plist").write_bytes(plistlib.dumps({"AniListClientID": "12345"}))
            self.assertFalse(privacy.scan_bundle(root))


if __name__ == "__main__":
    unittest.main()
