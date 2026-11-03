ARG FFMPEG_BUILDER_IMAGE=dispatcharr-hotio-ffmpeg:builder
ARG HOTIO_BASE_IMAGE=ghcr.io/hotio/base:noblevpn
FROM ${FFMPEG_BUILDER_IMAGE} AS ffmpeg-builder

FROM node:26 AS frontend-builder
WORKDIR /app/frontend
COPY frontend/ ./
RUN npm install --no-audit --progress=false && npm run build

FROM ${HOTIO_BASE_IMAGE} AS runtime
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV DEBIAN_FRONTEND=noninteractive

# Noble packages keep shared libraries compatible with Hotio's Ubuntu base.
RUN apt-get update && apt-get install --no-install-recommends -y \
    ca-certificates curl wget gnupg software-properties-common \
    && add-apt-repository -y ppa:deadsnakes/ppa \
    && install -d /usr/share/postgresql-common/pgdg \
    && curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
       -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc \
    && echo 'deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt noble-pgdg main' \
       > /etc/apt/sources.list.d/pgdg.list \
    && curl -fsSL https://packages.redis.io/gpg \
       | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg \
    && echo 'deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb noble main' \
       > /etc/apt/sources.list.d/redis.list \
    && apt-get update && apt-get install --no-install-recommends -y \
    python3.13 python3.13-venv libpython3.13 libpcre2-8-0 libopenblas0 \
    nginx redis-server postgresql-17 postgresql-contrib-17 \
    libargtable2-0 libavformat60 libavcodec60 libavutil58 libswscale7 \
    libgnutls30t64 libgmp10 libxml2 libvorbis0a libvorbisenc2 libaom3 \
    libsvtav1enc1d1 libass9 libfreetype6 libfribidi0 libfontconfig1 libharfbuzz0b \
    libzvbi0t64 libsoxr0 libwebp7 libwebpmux3 libzimg2 libbluray2 \
    libsrt1.5-gnutls librist4 libdrm2 ocl-icd-libopencl1 mesa-va-drivers libva2 libva-drm2 \
    vlc-bin vlc-plugin-base procps pciutils jq iproute2 \
    && if [ "$(dpkg --print-architecture)" = amd64 ]; then \
       apt-get install --no-install-recommends -y i965-va-driver; fi \
    && rm -rf /var/lib/apt/lists/*

# Rebuild upstream FFmpeg against Noble rather than copying Resolute binaries.
COPY --from=ffmpeg-builder /usr/local/bin/ffmpeg /usr/local/bin/ffprobe /usr/local/bin/
COPY --from=ffmpeg-builder /usr/local/share/doc/dispatcharr-ffmpeg /usr/local/share/doc/dispatcharr-ffmpeg
COPY --from=ffmpeg-builder /opt/intel-media-runtime/ /
RUN printf '%s\n' /usr/local/lib/x86_64-linux-gnu /usr/local/lib/aarch64-linux-gnu \
    > /etc/ld.so.conf.d/dispatcharr-intel-media.conf && ldconfig \
    && dpkg-query -W -f '${Package} ${Version}\n' \
       > /usr/local/share/doc/dispatcharr-ffmpeg/UBUNTU-PACKAGES.txt \
    && ffmpeg -hide_banner -version
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    NVIDIA_DRIVER_CAPABILITIES=compute,video,utility \
    NVIDIA_VISIBLE_DEVICES=all \
    LIBVA_DRIVERS_PATH=/usr/local/lib/x86_64-linux-gnu/dri:/usr/local/lib/aarch64-linux-gnu/dri:/usr/lib/x86_64-linux-gnu/dri:/usr/lib/aarch64-linux-gnu/dri

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/
ENV VIRTUAL_ENV=/dispatcharrpy \
    UV_PROJECT_ENVIRONMENT=/dispatcharrpy \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    PATH="/dispatcharrpy/bin:$PATH"

FROM runtime AS python-builder
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN apt-get update && apt-get install --no-install-recommends -y \
    python3.13-dev build-essential libpcre2-dev gfortran libopenblas-dev ninja-build \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /tmp/build
COPY pyproject.toml version.py README.md ./
RUN uv sync --python 3.13 --no-cache --no-install-project --no-dev

# Preserve the existing runtime option for CPUs below NumPy's baseline.
RUN uv pip install --python "$VIRTUAL_ENV/bin/python" --no-cache build pip \
    && "$VIRTUAL_ENV/bin/python" -m pip download --no-binary numpy --no-deps numpy \
    && tar -xzf numpy-*.tar.gz \
    && cd numpy-*/ \
    && "$VIRTUAL_ENV/bin/python" -m build --wheel \
       -Csetup-args=-Dcpu-baseline=none -Csetup-args=-Dcpu-dispatch=none \
    && mkdir -p /opt && cp dist/*.whl /opt/ \
    && uv pip uninstall --python "$VIRTUAL_ENV/bin/python" build pip

# Match DispatcharrBase's Comskip source build and compatibility fixes.
RUN apt-get update && apt-get install --no-install-recommends -y \
    autoconf automake libtool pkg-config libargtable2-dev libavformat-dev libswscale-dev \
    && mkdir /tmp/comskip \
    && curl -fsSL https://github.com/erikkaashoek/Comskip/archive/refs/heads/master.tar.gz \
       | tar -xz --strip-components=1 -C /tmp/comskip \
    && cd /tmp/comskip \
    && sed -i \
       -e '/#include <libavcodec\/avcodec.h>/a #include <libavcodec/codec_desc.h>' \
       -e '/is->dec_ctx->ticks_per_frame = 1/d' \
       -e 's/is->dec_ctx->ticks_per_frame/(is->dec_ctx->codec_descriptor \&\& (is->dec_ctx->codec_descriptor->props \& AV_CODEC_PROP_FIELDS) ? 2 : 1)/g' \
       mpeg2dec.c \
    && MULTIARCH="$(dpkg-architecture -qDEB_HOST_MULTIARCH)" \
    && DISTRO_LIB="/usr/lib/${MULTIARCH}" \
    && export PKG_CONFIG_LIBDIR="${DISTRO_LIB}/pkgconfig" \
    && export LDFLAGS="-L${DISTRO_LIB} -Wl,-rpath-link,${DISTRO_LIB} -Wl,-rpath,${DISTRO_LIB} -Wl,--disable-new-dtags" \
    && ./autogen.sh && ./configure && make -j"$(nproc)" \
    && strip comskip \
    && install -m 0755 comskip /usr/local/bin/comskip \
    && rm -rf /tmp/comskip /var/lib/apt/lists/*

FROM runtime AS final
COPY --from=python-builder /dispatcharrpy /dispatcharrpy
COPY --from=python-builder /opt/numpy-*.whl /opt/
COPY --from=python-builder /usr/local/bin/comskip /usr/local/bin/comskip
WORKDIR /app
COPY . /app
COPY docker/nginx.conf /etc/nginx/sites-enabled/default
RUN rm -rf /app/frontend \
    && sed -i 's/\r$//' /app/docker/entrypoint*.sh \
    && chmod +x /app/docker/entrypoint*.sh \
    && mkdir -p /data \
    # The existing user setup reuses GPU GIDs when render already exists.
    && groupadd --system --force render \
    && usermod -s /bin/bash hotio
COPY --from=frontend-builder /app/frontend/dist /app/frontend/dist

# Keep Hotio's account name intact for its VPN and proxy services.
ENV POSTGRES_USER=hotio \
    POSTGRES_DB=dispatcharr \
    DISPATCHARR_ENV=aio \
    WEBUI_PORTS=9191/tcp
EXPOSE 9191

# Inherit /init: s6 completes Hotio's VPN initialization before starting CMD.
CMD ["/command/with-contenv", "/app/docker/entrypoint.sh"]
