#!/usr/bin/env python3
"""Isolated release-boundary tests; never access Keychain or installed app data."""
import base64
import json
from pathlib import Path
import plistlib
import subprocess
import stat
import tempfile
import unittest
import zipfile
from release_policy import ROOT, info, validate_archive


class ReleaseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory(prefix="copystory-release-test-")
        cls.directory = Path(cls.tmp.name)
        generator = cls.directory / "fixtures.swift"
        generator.write_text('''import Foundation
import CryptoKit
let dir = URL(fileURLWithPath: CommandLine.arguments[1])
let key = Curve25519.Signing.PrivateKey()
let content = Data("<rss><channel><title>Fixture</title></channel></rss>\\n".utf8)
let signature = try key.signature(for: content).base64EncodedString()
let block = "<!-- sparkle-signatures:\\nedSignature: \\(signature)\\nlength: \\(content.count)\\n-->\\n"
try (content + Data(block.utf8)).write(to: dir.appendingPathComponent("valid.xml"))
try content.write(to: dir.appendingPathComponent("archive.zip"))
let metadata = ["publicKey": key.publicKey.rawRepresentation.base64EncodedString(), "signature": signature]
try JSONSerialization.data(withJSONObject: metadata).write(to: dir.appendingPathComponent("fixture.json"))
''')
        subprocess.run(["swift", str(generator), str(cls.directory)], check=True)
        cls.metadata = json.loads((cls.directory / "fixture.json").read_text())

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def verify(self, path, signature=None, public_key=None):
        command = ["swift", str(ROOT / "scripts/verify-update.swift"), public_key or self.metadata["publicKey"], str(path)]
        if signature is not None:
            command.append(signature)
        return subprocess.run(command, capture_output=True).returncode

    def test_valid_signed_feed_and_archive(self):
        self.assertEqual(self.verify(self.directory / "valid.xml"), 0)
        self.assertEqual(self.verify(self.directory / "archive.zip", self.metadata["signature"]), 0)

    def test_feed_tampering_rejected(self):
        path = self.directory / "tampered.xml"
        path.write_bytes((self.directory / "valid.xml").read_bytes().replace(b"Fixture", b"Malware"))
        self.assertNotEqual(self.verify(path), 0)

    def test_archive_tampering_rejected(self):
        path = self.directory / "tampered.zip"
        path.write_bytes((self.directory / "archive.zip").read_bytes() + b"!")
        self.assertNotEqual(self.verify(path, self.metadata["signature"]), 0)

    def test_wrong_public_key_rejected(self):
        self.assertNotEqual(self.verify(self.directory / "valid.xml", public_key=base64.b64encode(bytes(32)).decode()), 0)

    def test_unsigned_and_duplicate_feed_rejected(self):
        self.assertNotEqual(self.verify(self.directory / "archive.zip"), 0)
        path = self.directory / "duplicate.xml"
        path.write_bytes((self.directory / "valid.xml").read_bytes() * 2)
        self.assertNotEqual(self.verify(path), 0)

    def test_unsigned_trailing_bytes_rejected(self):
        path = self.directory / "trailing.xml"
        path.write_bytes((self.directory / "valid.xml").read_bytes() + b"<item>unsigned</item>")
        self.assertNotEqual(self.verify(path), 0)

    def test_inaccurate_length_rejected(self):
        import re
        path = self.directory / "length.xml"
        path.write_bytes(re.sub(rb"length: [0-9]+", b"length: 1", (self.directory / "valid.xml").read_bytes()))
        self.assertNotEqual(self.verify(path), 0)

    def test_configuration_cannot_weaken_security(self):
        original = info()
        for name, value in [("SURequireSignedFeed", False), ("SUVerifyUpdateBeforeExtraction", False),
                            ("SUSignedFeedFailureExpirationInterval", 86400), ("SUEnableJavaScript", True),
                            ("SUAutomaticallyUpdate", True), ("SUEnableAutomaticChecks", True),
                            ("CFBundleVersion", "3.1"), ("SUPublicEDKey", ""),
                            ("CFBundleVersion", str(2**64)),
                            ("SUFeedURL", "https://example.invalid/update.xml")]:
            with self.subTest(name=name):
                path = self.directory / "invalid.plist"
                path.write_bytes(plistlib.dumps(dict(original, **{name: value})))
                with self.assertRaises(ValueError):
                    info(path)

    def archive(self, entries):
        path = self.directory / "fixture-package.zip"
        with zipfile.ZipFile(path, "w") as archive:
            archive.writestr("CopyStory.app/", b"")
            for name, value, symlink in entries:
                member = zipfile.ZipInfo(name)
                member.create_system = 3
                member.external_attr = ((stat.S_IFLNK | 0o777) if symlink else (stat.S_IFREG | 0o644)) << 16
                archive.writestr(member, value)
        return path

    def test_normal_framework_symlink_archive_accepted(self):
        prefix = "CopyStory.app/Contents/Frameworks/Sparkle.framework/"
        path = self.archive([(prefix + "Versions/B/Sparkle", b"binary", False),
                             (prefix + "Versions/Current", b"B", True),
                             (prefix + "Sparkle", b"Versions/Current/Sparkle", True)])
        validate_archive(path)

    def test_archive_symlink_ancestor_rejected(self):
        prefix = "CopyStory.app/Contents/Frameworks/Sparkle.framework/"
        path = self.archive([(prefix + "Versions/Current", b"B", True),
                             (prefix + "Versions/Current/payload", b"payload", False)])
        with self.assertRaises(ValueError):
            validate_archive(path)

    def test_archive_traversal_and_external_symlinks_rejected(self):
        prefix = "CopyStory.app/Contents/Frameworks/Sparkle.framework/"
        for name, target, symlink in [("CopyStory.app/../../escape", b"bad", False),
                                      (prefix + "escape", b"../../../../escape", True),
                                      ("__MACOSX/escape", b"/tmp/escape", True),
                                      ("CopyStory.app/other", b"Contents", True)]:
            with self.subTest(name=name):
                with self.assertRaises(ValueError):
                    validate_archive(self.archive([(name, target, symlink)]))

    def test_archive_duplicate_entries_rejected(self):
        with self.assertRaises(ValueError):
            validate_archive(self.archive([("CopyStory.app/item", b"one", False), ("CopyStory.app/item", b"two", False)]))

    def test_archive_case_and_unicode_aliases_rejected(self):
        prefix = "CopyStory.app/Contents/Frameworks/Sparkle.framework/"
        for alias in ["a", "A"]:
            path = self.archive([(prefix + "A", b"Versions/B", True),
                                 (prefix + alias + "/payload", b"payload", False)])
            with self.assertRaises(ValueError):
                validate_archive(path)
        for names in [("Item", "item"), ("caf\u00e9", "cafe\u0301")]:
            with self.assertRaises(ValueError):
                validate_archive(self.archive([("CopyStory.app/" + name, b"payload", False) for name in names]))


if __name__ == "__main__":
    unittest.main()
