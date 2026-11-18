import os
import subprocess
import tempfile
import unittest
from pathlib import Path

from scripts.prepare_runtime import adapt_dispatcharr, adapt_ffmpeg, prepare


class PrepareRuntimeTests(unittest.TestCase):
    def test_dispatcharr_uses_noble_libav_without_changing_build_commands(self):
        original = (
            "FROM ${FFMPEG_IMAGE} AS builder\nRUN uv sync --python 3.13\n"
            "FROM ${FFMPEG_IMAGE} AS final\n"
            "RUN apt-get install libavformat62 libavcodec62 libavutil60 libswscale9\n"
        )
        self.assertEqual(
            adapt_dispatcharr(original),
            original.replace(
                "libavformat62 libavcodec62 libavutil60 libswscale9",
                "libavformat60 libavcodec60 libavutil58 libswscale7",
            ),
        )

    def test_ffmpeg_keeps_source_build_and_guards_each_hotio_stage(self):
        original = (
            "FROM ${UBUNTU_BASE} AS builder\n"
            "RUN apt-get install libsvtav1enc-dev\nRUN /tmp/build.sh\n"
            "RUN true; /tmp/build-static-codecs.sh\n"
            "FROM ${UBUNTU_BASE} AS final\n"
            "RUN apt-get install libxml2-16 libsvtav1enc2 libbluray3 mesa-libgallium\n"
        )
        result = adapt_ffmpeg(original)
        self.assertIn("RUN /tmp/build.sh\n", result)
        self.assertIn("RUN apt-get install libsvtav1enc-dev\n", result)
        self.assertIn(
            "RUN apt-get install libxml2 libsvtav1enc1d1 libbluray2 mesa-va-drivers\n",
            result,
        )
        self.assertEqual(result.count("Unsupported Hotio base:"), 2)

    def test_hotio_config_directory_does_not_leak_into_codec_build(self):
        recipe = (
            "FROM ${UBUNTU_BASE} AS builder\n"
            "RUN apt-get install libsvtav1enc-dev\n"
            "RUN true; /tmp/build-static-codecs.sh\n"
            "FROM ${UBUNTU_BASE} AS final\n"
            "RUN apt-get install libxml2-16 libsvtav1enc2 libbluray3 mesa-libgallium\n"
        )
        command = next(
            line.removeprefix("RUN ")
            for line in adapt_ffmpeg(recipe).splitlines()
            if line.startswith("RUN ") and "build-static-codecs.sh" in line
        )
        with tempfile.TemporaryDirectory() as directory:
            script = Path(directory) / "codecs.sh"
            script.write_text('#!/bin/sh\nprintf "%s" "${CONFIG_DIR-unset}"\n')
            script.chmod(0o755)
            result = subprocess.check_output(
                [
                    "sh",
                    "-ec",
                    command.replace("/tmp/build-static-codecs.sh", str(script)),
                ],
                env={**os.environ, "CONFIG_DIR": "/config"},
                text=True,
            )
        self.assertEqual(result, "unset")

    def test_upstream_package_changes_require_review(self):
        with self.assertRaisesRegex(ValueError, "Upstream build changed"):
            adapt_dispatcharr("RUN apt-get install libavformat63\n")
        with self.assertRaisesRegex(ValueError, "Upstream build changed"):
            adapt_ffmpeg("FROM ubuntu:28.04\n")

    def test_preparation_does_not_write_partial_outputs_on_invalid_input(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory)
            (source / "dispatcharr/docker").mkdir(parents=True)
            (source / "ffmpeg").mkdir()
            (source / "dispatcharr/docker/DispatcharrBase").write_text(
                "libavformat62 libavcodec62 libavutil60 libswscale9\n"
            )
            (source / "ffmpeg/Dockerfile").write_text("unsupported\n")
            with self.assertRaises(ValueError):
                prepare(source)
            self.assertEqual(list(source.rglob("*.hotio")), [])


if __name__ == "__main__":
    unittest.main()
