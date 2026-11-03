import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from urllib.error import HTTPError

from scripts.update import update


class UpdateTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / "meta.json"
        self.original = {"ffmpeg_revision": "b" * 40}
        self.path.write_text(json.dumps(self.original))
        self.digest = "sha256:" + "c" * 64
        self.release = {"tag_name": "v0.33.0", "draft": False, "prerelease": False}
        self.commit = {"sha": "a" * 40}

    def responses(self):
        return [
            io.BytesIO(json.dumps(data).encode())
            for data in (self.release, self.commit)
        ]

    def test_records_exact_release_commit_and_base_without_losing_ffmpeg_pin(self):
        with patch("urllib.request.urlopen", side_effect=self.responses()):
            metadata = update(self.path, self.digest)
        self.assertEqual(metadata, json.loads(self.path.read_text()))
        self.assertEqual(metadata["version"], "v0.33.0")
        self.assertEqual(metadata["revision"], "a" * 40)
        self.assertEqual(metadata["base_digest"], self.digest)
        self.assertEqual(metadata["ffmpeg_revision"], "b" * 40)

    def test_unchanged_release_produces_identical_file(self):
        with patch("urllib.request.urlopen", side_effect=self.responses()):
            update(self.path, self.digest)
        before = self.path.read_bytes()
        with patch("urllib.request.urlopen", side_effect=self.responses()):
            update(self.path, self.digest)
        self.assertEqual(before, self.path.read_bytes())

    def test_invalid_release_or_revision_preserves_previous_metadata(self):
        for field, value in (
            ("tag_name", "../main"),
            ("prerelease", True),
            ("draft", True),
        ):
            with self.subTest(field=field):
                before = self.path.read_bytes()
                self.release = {
                    "tag_name": "v0.33.0",
                    "draft": False,
                    "prerelease": False,
                }
                self.release[field] = value
                with (
                    patch("urllib.request.urlopen", side_effect=self.responses()),
                    self.assertRaises(ValueError),
                ):
                    update(self.path, self.digest)
                self.assertEqual(before, self.path.read_bytes())

    def test_invalid_commit_preserves_previous_metadata(self):
        before = self.path.read_bytes()
        self.commit["sha"] = "main"
        with (
            patch("urllib.request.urlopen", side_effect=self.responses()),
            self.assertRaises(ValueError),
        ):
            update(self.path, self.digest)
        self.assertEqual(before, self.path.read_bytes())

    def test_invalid_base_digest_preserves_previous_metadata(self):
        before = self.path.read_bytes()
        with self.assertRaises(ValueError):
            update(self.path, "latest")
        self.assertEqual(before, self.path.read_bytes())

    def test_base_update_changes_metadata_without_a_dispatcharr_release(self):
        with patch("urllib.request.urlopen", side_effect=self.responses()):
            update(self.path, self.digest)
        self.digest = "sha256:" + "d" * 64
        with patch("urllib.request.urlopen", side_effect=self.responses()):
            metadata = update(self.path, self.digest)
        self.assertEqual(metadata["base_digest"], self.digest)
        self.assertEqual(metadata["version"], "v0.33.0")

    def test_invalid_ffmpeg_pin_preserves_previous_metadata(self):
        self.path.write_text(json.dumps({"ffmpeg_revision": "main"}))
        before = self.path.read_bytes()
        with (
            patch("urllib.request.urlopen", side_effect=self.responses()),
            self.assertRaises(ValueError),
        ):
            update(self.path, self.digest)
        self.assertEqual(before, self.path.read_bytes())

    def test_network_failure_preserves_previous_metadata(self):
        before = self.path.read_bytes()
        error = HTTPError("https://api.github.com", 503, "Unavailable", {}, None)
        with (
            patch("urllib.request.urlopen", side_effect=error),
            self.assertRaises(HTTPError),
        ):
            update(self.path, self.digest)
        self.assertEqual(before, self.path.read_bytes())


if __name__ == "__main__":
    unittest.main()
