# Dispatcharr on Hotio

Community Dispatcharr image using Hotio's VPN-enabled Ubuntu base. This project
is independent of the Dispatcharr and Hotio teams. Supports Linux amd64.

## Run

```bash
docker run -d --name dispatcharr-hotio \
  -p 9191:9191 \
  -e PUID=1000 -e PGID=1000 \
  -v dispatcharr_hotio_config:/config \
  -v dispatcharr_hotio_data:/data \
  ghcr.io/samtheruby/dispatcharr-hotio:latest
```

Open `http://localhost:9191`. Adjust PUID and PGID for your host.
`/data` holds Dispatcharr's database and files; `/config` holds Hotio settings.
Keep `POSTGRES_USER=hotio` at its default. Back up data before upgrading.

The VPN is disabled by default. To enable it, follow
[Hotio's WireGuard instructions](https://hotio.dev/containers/base/#wireguard).
Dispatcharr's web port is `9191/tcp`. Keep VPN keys outside the image and repository.
Pass GPU devices through Docker when needed; verify acceleration on your hardware.

## Updates

GitHub Actions checks the latest stable Dispatcharr release and Hotio base every
12 hours, at 00:17 and 12:17 UTC. It commits the release image digest, source revision,
and the release's FFmpeg source revision to [meta.json](meta.json). It builds the
runtime on Hotio's Ubuntu 24.04 base, copies the released application, and runs
[the container test](tests/test-image.sh).
Only passing images receive `latest` and the Dispatcharr version tag, such as
`v0.34.1`. Version tags can receive base updates; use an image digest to pin a build.
The `build-...` tags record completed builds. `buildcache` stores build layers.
Failed builds or publishing retry on the next scheduled check.

The application and built frontend come directly from the official release image.
FFmpeg, ffprobe, the Intel media stack, Comskip, Python dependencies, and the
legacy NumPy wheel are built for Ubuntu 24.04. The build reuses Dispatcharr's
`docker/DispatcharrBase` recipe at the release revision and the FFmpeg recipe
recorded in the release image. [The adapter](scripts/prepare_runtime.py) changes
Ubuntu package names, isolates codec builds from Hotio's configuration directory,
and rejects unexpected recipe changes for review.
Python dependencies resolve from the release's `pyproject.toml`, as in upstream's
base build; unpinned packages can be newer. Comskip follows upstream's source recipe.
Tests compare application files and FFmpeg source pins with the official image,
check Python dependencies and native libraries, encode a sample, and test startup
and shutdown before publishing. Pull requests and manual runs on other branches
build and test without publishing. Only runs on `main` publish images.
Image-level NVIDIA settings must also match upstream so driver libraries are
requested before container startup.

System packages and repositories match Ubuntu 24.04. The build does not copy
Ubuntu 26.04 native binaries, Python environments, or apt repositories into Hotio.
Hotio supplies startup, VPN support, its service account, and `/config` handling.
Upstream's application environment defaults are applied after Hotio initializes;
explicit environment settings take precedence.

The build rejects bases other than Ubuntu 24.04. Dependency layers cache separately
from the application, so application-only releases reuse existing build layers.
The first source build can take several hours; later builds reuse the registry cache.
Packaging changes also trigger builds.

Builds do not upgrade running containers. Pull and recreate your container when
you are ready. Keep existing volume mappings when switching from the local image.

In GitHub notification settings, enable **System → Actions → Email** and
**Only notify for failed workflows**. Scheduled notifications go to the workflow
creator, the last person who changed its schedule, or the person who re-enabled it.
Public repository schedules can stop after 60 days without repository activity;
version commits help, but a long gap between updates still needs attention.
A disabled schedule does not generate a failed build notification.

To retry immediately, open **Actions → Update and build Dispatcharr Hotio → Run workflow**.
If publishing initially fails, check repository Actions permissions. New GHCR
packages can be private: set this package's visibility to public in GitHub's
package settings to allow pulls without logging in.

## Local build

Requires Docker with Buildx, Python 3, Git, jq, and enough disk space for source
builds. Run from this repository with a fresh `source` directory:

```bash
python3 -m unittest discover -s tests -v
export BASE_DIGEST="$(jq -r .base_digest meta.json)"
export UPSTREAM_IMAGE="$(jq -r .upstream_image meta.json)"
export REVISION="$(jq -r .revision meta.json)"
export VERSION="$(jq -r .version meta.json)"
export FFMPEG_REVISION="$(jq -r .ffmpeg_revision meta.json)"
git clone https://github.com/Dispatcharr/Dispatcharr.git source/dispatcharr
git -C source/dispatcharr checkout "$REVISION"
git clone https://github.com/Dispatcharr/FFmpeg.git source/ffmpeg
git -C source/ffmpeg checkout "$FFMPEG_REVISION"
python3 scripts/prepare_runtime.py
bash tests/test-compatibility.sh
docker buildx bake app --load
bash tests/test-image.sh dispatcharr-hotio:test "$UPSTREAM_IMAGE"
```

The container test uses fresh temporary data with VPN disabled. It checks imports,
media tools, GPU group handling, HTTP startup, and graceful shutdown. VPN routing,
tunnel failure blocking, real GPU acceleration, and existing database upgrades
need separate checks.

Packaging code uses BSD-3-Clause; Dispatcharr and bundled components retain their
own licenses. The image retains Dispatcharr's application files in `/app` and
the rebuilt media components' notices under `/usr/local/share`. The official image's
package inventory (for reference only) and application defaults are retained in
`/usr/local/share/dispatcharr-upstream`.
