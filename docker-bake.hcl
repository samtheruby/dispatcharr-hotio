variable "IMAGE" {
  default = "dispatcharr-hotio:test"
}

variable "BASE_DIGEST" {
  default = ""
}

variable "UPSTREAM_IMAGE" {
  default = ""
}

variable "REVISION" {
  default = ""
}

variable "VERSION" {
  default = ""
}

variable "FFMPEG_REVISION" {
  default = ""
}

target "ffmpeg" {
  context = "source/ffmpeg"
  dockerfile = "Dockerfile.hotio"
  args = {
    UBUNTU_BASE = "ghcr.io/hotio/base:noblevpn@${BASE_DIGEST}"
    SOURCE_REVISION = FFMPEG_REVISION
  }
  platforms = ["linux/amd64"]
}

target "runtime" {
  context = "source/dispatcharr"
  dockerfile = "docker/DispatcharrBase.hotio"
  args = {
    FFMPEG_IMAGE = "ffmpeg-base"
  }
  contexts = {
    ffmpeg-base = "target:ffmpeg"
  }
  platforms = ["linux/amd64"]
}

target "app" {
  context = "."
  dockerfile = "Dockerfile"
  args = {
    UPSTREAM_IMAGE = UPSTREAM_IMAGE
    DISPATCHARR_VERSION = VERSION
  }
  contexts = {
    runtime-base = "target:runtime"
  }
  labels = {
    "org.opencontainers.image.source" = "https://github.com/samtheruby/dispatcharr-hotio"
    "org.opencontainers.image.version" = VERSION
    "org.opencontainers.image.revision" = REVISION
    "org.opencontainers.image.description" = "Dispatcharr on Hotio's VPN-enabled base (community build)"
  }
  platforms = ["linux/amd64"]
  tags = [IMAGE]
}
