"""Track the latest stable Dispatcharr release and Hotio base digest."""

import json
import os
import re
import subprocess
import sys
import urllib.request
from pathlib import Path
from typing import Any


def github(path: str) -> dict[str, Any]:
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "dispatcharr-hotio",
    }
    if token := os.environ.get("GH_TOKEN"):
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(
        f"https://api.github.com/repos/Dispatcharr/Dispatcharr/{path}", headers=headers
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def image_digest(image: str) -> str:
    return subprocess.check_output(
        [
            "docker",
            "buildx",
            "imagetools",
            "inspect",
            image,
            "--format",
            "{{.Manifest.Digest}}",
        ],
        text=True,
        timeout=60,
    ).strip()


def update(path: Path, base_digest: str) -> dict[str, Any]:
    if not re.fullmatch(r"sha256:[0-9a-f]{64}", base_digest):
        raise ValueError("Hotio base must resolve to a SHA-256 digest")
    metadata = json.loads(path.read_text())
    release = github("releases/latest")
    version = release["tag_name"]
    if (
        release["draft"]
        or release["prerelease"]
        or not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", version)
    ):
        raise ValueError("Expected a stable Dispatcharr vX.Y.Z release")
    revision = github(f"commits/{version}")["sha"]
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise ValueError("Dispatcharr release must resolve to a commit SHA")
    image = f"ghcr.io/dispatcharr/dispatcharr:{version[1:]}"
    digest = image_digest(image)
    if not re.fullmatch(r"sha256:[0-9a-f]{64}", digest):
        raise ValueError("Dispatcharr release image must resolve to a SHA-256 digest")
    metadata.pop("ffmpeg_revision", None)
    metadata.update(
        version=version,
        revision=revision,
        base_digest=base_digest,
        upstream_image=f"{image}@{digest}",
    )
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n")
    temporary.replace(path)
    return metadata


if __name__ == "__main__":
    try:
        update(Path("meta.json"), sys.argv[1])
    except (
        OSError,
        ValueError,
        KeyError,
        IndexError,
        subprocess.SubprocessError,
    ) as error:
        sys.exit(f"Update failed: {error}")
