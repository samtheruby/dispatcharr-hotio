import tempfile
import unittest
from pathlib import Path

from scripts.export_runtime import write_manifest


class ExportRuntimeTests(unittest.TestCase):
    def test_records_installed_packages_and_safe_application_defaults(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            write_manifest(
                path,
                "ii \tpython3.13\t3.13.17\nii \tlibc6:amd64\t2.39\nrc \told-package\t1\n",
                {
                    "PATH": "/dispatcharrpy/bin:/bin",
                    "HOME": "/root",
                    "HOSTNAME": "temporary-build-host",
                    "S6_STAGE2_HOOK": "/docker-mods",
                    "LSIO_FIRST_PARTY": "true",
                    "DISPATCHARR_VERSION": "v0.33.0",
                    "HTTPS_PROXY": "https://private-proxy.invalid",
                    "LD_LIBRARY_PATH": "/usr/local/lib",
                    "UV_PROJECT_ENVIRONMENT": "/dispatcharrpy",
                    "VALUE": "spaces and $(literal);\nnewlines",
                },
            )
            self.assertEqual(
                (path / "packages.tsv").read_text(),
                "libc6:amd64\t2.39\npython3.13\t3.13.17\n",
            )
            self.assertEqual(
                (path / "environment").read_bytes(),
                b"LD_LIBRARY_PATH=/usr/local/lib\0"
                b"UV_PROJECT_ENVIRONMENT=/dispatcharrpy\0"
                b"VALUE=spaces and $(literal);\nnewlines\0",
            )

    def test_rejects_invalid_package_names_without_writing_files(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            with self.assertRaises(ValueError):
                write_manifest(path, "ii \t--allow-unauthenticated\t1\n", {})
            self.assertEqual(list(path.iterdir()), [])

    def test_manifest_does_not_change_for_build_host_or_application_version(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            packages = "ii \tpython3.13\t3.13.17\n"
            write_manifest(
                path, packages, {"HOSTNAME": "a", "DISPATCHARR_VERSION": "v1.0.0"}
            )
            before = {file.name: file.read_bytes() for file in path.iterdir()}
            write_manifest(
                path, packages, {"HOSTNAME": "b", "DISPATCHARR_VERSION": "v1.0.1"}
            )
            self.assertEqual(
                before, {file.name: file.read_bytes() for file in path.iterdir()}
            )


if __name__ == "__main__":
    unittest.main()
