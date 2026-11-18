"""Adapt the release's upstream build recipes to Hotio's Ubuntu 24.04 base."""

import re
import sys
from pathlib import Path


def replace_packages(recipe: str, replacements: dict[str, str]) -> str:
    for upstream, noble in replacements.items():
        recipe, count = re.subn(rf"\b{re.escape(upstream)}\b", noble, recipe)
        if not count:
            raise ValueError(
                f"Upstream build changed: expected {upstream}; review Noble adaptation"
            )
    return recipe


def adapt_dispatcharr(recipe: str) -> str:
    return replace_packages(
        recipe,
        {
            "libavformat62": "libavformat60",
            "libavcodec62": "libavcodec60",
            "libavutil60": "libavutil58",
            "libswscale9": "libswscale7",
        },
    )


def adapt_ffmpeg(recipe: str) -> str:
    recipe = replace_packages(
        recipe,
        {
            "libxml2-16": "libxml2",
            "libsvtav1enc2": "libsvtav1enc1d1",
            "libbluray3": "libbluray2",
            "mesa-libgallium": "mesa-va-drivers",
        },
    )
    # Hotio exports CONFIG_DIR=/config; libvpx uses CONFIG_DIR for generated files.
    recipe, count = re.subn(
        r"(?m)^(RUN .*; )/tmp/build-static-codecs\.sh$",
        r"\1env -u CONFIG_DIR /tmp/build-static-codecs.sh",
        recipe,
    )
    if count != 1:
        raise ValueError("Upstream build changed: expected static codec build command")
    guard = (
        'RUN . /etc/os-release && if [ "$ID:$VERSION_ID" != ubuntu:24.04 ]; then '
        'echo "Unsupported Hotio base: $ID:$VERSION_ID; expected ubuntu:24.04" >&2; '
        "exit 1; fi\n"
    )
    for stage in ("builder", "final"):
        marker = f"FROM ${{UBUNTU_BASE}} AS {stage}\n"
        if recipe.count(marker) != 1:
            raise ValueError(f"Upstream build changed: expected FFmpeg {stage} stage")
        recipe = recipe.replace(marker, marker + guard)
    return recipe


def prepare(source: Path) -> None:
    dispatcharr = source / "dispatcharr/docker/DispatcharrBase"
    ffmpeg = source / "ffmpeg/Dockerfile"
    recipes = {
        dispatcharr.with_suffix(".hotio"): adapt_dispatcharr(dispatcharr.read_text()),
        ffmpeg.with_suffix(".hotio"): adapt_ffmpeg(ffmpeg.read_text()),
    }
    for destination, recipe in recipes.items():
        destination.write_text(recipe)


if __name__ == "__main__":
    try:
        prepare(Path(sys.argv[1] if len(sys.argv) > 1 else "source"))
    except (OSError, ValueError) as error:
        sys.exit(f"Cannot prepare Hotio runtime: {error}")
