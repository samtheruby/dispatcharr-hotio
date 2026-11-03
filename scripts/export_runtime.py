"""Export installed runtime requirements from the published Dispatcharr image."""

import os
import re
import runpy
import subprocess
import sys
from collections.abc import Mapping
from pathlib import Path


def write_manifest(path: Path, packages: str, environment: Mapping[str, str]) -> None:
    installed = []
    for line in packages.splitlines():
        status, name, version = line.split("\t")
        if status != "ii ":
            continue
        if not re.fullmatch(r"[a-z0-9][a-z0-9+.-]*(?::[a-z0-9]+)?", name):
            raise ValueError(f"Invalid upstream package name: {name!r}")
        installed.append(f"{name}\t{version}\n")
    if not installed:
        raise ValueError("Upstream runtime has no installed packages")

    excluded = {
        "PATH",
        "HOME",
        "HOSTNAME",
        "PWD",
        "SHLVL",
        "_",
        "TERM",
        "DEBIAN_FRONTEND",
        "DISPATCHARR_VERSION",
        "PUID",
        "PGID",
        "UMASK",
        "TZ",
    }
    defaults = []
    for name, value in sorted(environment.items()):
        if (
            name in excluded
            or name.startswith(("S6_", "LSIO_"))
            or name.upper().endswith("_PROXY")
        ):
            continue
        if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", name) or "\0" in value:
            raise ValueError(f"Invalid upstream environment setting: {name!r}")
        defaults.append(f"{name}={value}\0")
    path.mkdir(parents=True, exist_ok=True)
    (path / "packages.tsv").write_text("".join(sorted(installed)))
    (path / "environment").write_bytes("".join(defaults).encode())


if __name__ == "__main__":
    version = runpy.run_path("/app/version.py")["__version__"]
    if version != sys.argv[1].removeprefix("v"):
        sys.exit(f"Upstream image version {version!r} does not match {sys.argv[1]!r}")
    packages = subprocess.check_output(
        [
            "dpkg-query",
            "-W",
            "-f",
            "${db:Status-Abbrev}\t${binary:Package}\t${Version}\n",
        ],
        text=True,
    )
    destination = Path("/dispatcharr-export")
    write_manifest(destination, packages, os.environ)
    (destination / "architecture").write_text(
        subprocess.check_output(["dpkg", "--print-architecture"], text=True)
    )
