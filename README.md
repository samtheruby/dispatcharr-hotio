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
hour, at minute 17. It commits changes to [meta.json](meta.json), fetches the
exact Dispatcharr commit, builds the image, and runs [the container test](tests/test-image.sh).
Only passing images receive `latest` and the Dispatcharr version tag, such as
`v0.33.0`. Version tags can receive base updates; use an image digest to pin a build.
The `build-...` tags record completed builds. `buildcache` stores build layers.
Failed builds or publishing retry on the next hourly check.

FFmpeg stays pinned to the tested source revision in `meta.json` and is rebuilt
against Ubuntu 24.04 for compatibility with Hotio. Review that pin when Dispatcharr
changes its media requirements. Application code comes from Dispatcharr's release,
not a maintained fork. Packaging changes also trigger builds.

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

Requires Docker with Buildx, Git, Python 3, and jq. Run from this repository:

```bash
python3 -m unittest discover -s tests -v
git clone https://github.com/Dispatcharr/Dispatcharr.git source
git -C source checkout "$(jq -r .revision meta.json)"
export BASE_DIGEST="$(jq -r .base_digest meta.json)"
export FFMPEG_REVISION="$(jq -r .ffmpeg_revision meta.json)"
export REVISION="$(jq -r .revision meta.json)"
export VERSION="$(jq -r .version meta.json)"
docker buildx bake app --load
bash tests/test-image.sh
```

The container test uses fresh temporary data with VPN disabled. It checks imports,
media tools, GPU group handling, HTTP startup, and graceful shutdown. VPN routing,
tunnel failure blocking, real GPU acceleration, and existing database upgrades
need separate checks.

Packaging code uses BSD-3-Clause; Dispatcharr and bundled components retain their
own licenses. The image includes Dispatcharr's source and license in `/app` and
FFmpeg build information in `/usr/local/share/doc/dispatcharr-ffmpeg`.
