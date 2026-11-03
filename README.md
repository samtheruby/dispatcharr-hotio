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
12 hours, at 00:17 and 12:17 UTC. It commits the release image digest and source revision to
[meta.json](meta.json), packages that published runtime on Hotio, and runs
[the container test](tests/test-image.sh).
Only passing images receive `latest` and the Dispatcharr version tag, such as
`v0.33.0`. Version tags can receive base updates; use an image digest to pin a build.
The `build-...` tags record completed builds. `buildcache` stores build layers.
Failed builds or publishing retry on the next scheduled check.

The application, built frontend, FFmpeg, ffprobe, Comskip, and installed Python
packages come directly from the official release image. They are not rebuilt or
independently upgraded. Tests compare the application files, media binary hashes,
and Python package versions with that image before publishing.
Image-level NVIDIA settings must also match upstream so driver libraries are
requested before container startup.

System packages use the official image's installed package list and repositories.
Available OS package patches can be newer than the donor image; this is a Hotio
distribution, not an identical copy of Dispatcharr's complete operating system.
Hotio supplies startup, VPN support, its service account, and `/config` handling.
Upstream's application environment defaults are applied after Hotio initializes;
explicit environment settings take precedence.

The build checks that upstream and Hotio use the same OS release and architecture.
An incompatible release stops publishing and needs a reviewed packaging change.
There is no automatic fallback to different FFmpeg or Python packages. Dependency
layers cache separately from the application, so application-only releases reuse
the existing dependency layers. Packaging changes also trigger builds.

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

Requires Docker with Buildx, Python 3, and jq. Run from this repository:

```bash
python3 -m unittest discover -s tests -v
export BASE_DIGEST="$(jq -r .base_digest meta.json)"
export UPSTREAM_IMAGE="$(jq -r .upstream_image meta.json)"
export REVISION="$(jq -r .revision meta.json)"
export VERSION="$(jq -r .version meta.json)"
docker buildx bake app --load
bash tests/test-compatibility.sh
bash tests/test-image.sh dispatcharr-hotio:test "$UPSTREAM_IMAGE"
```

The container test uses fresh temporary data with VPN disabled. It checks imports,
media tools, GPU group handling, HTTP startup, and graceful shutdown. VPN routing,
tunnel failure blocking, real GPU acceleration, and existing database upgrades
need separate checks.

Packaging code uses BSD-3-Clause; Dispatcharr and bundled components retain their
own licenses. The image retains Dispatcharr's application files in `/app` and
upstream's installed notices under `/usr/local/share`. The package inventory and
application defaults used during packaging are in `/usr/local/share/dispatcharr-upstream`.
