variable "IMAGE" {
  default = "dispatcharr-hotio:test"
}

variable "BASE_DIGEST" {
  default = ""
}

variable "FFMPEG_REVISION" {
  default = "fce79836385ee64bc3c91360fb9cfb40818b80c7"
}

variable "REVISION" {
  default = ""
}

variable "VERSION" {
  default = ""
}

target "ffmpeg" {
  context = "https://github.com/Dispatcharr/FFmpeg.git#${FFMPEG_REVISION}"
  target = "builder"
  args = {
    UBUNTU_BASE = "ubuntu:24.04"
    SOURCE_REVISION = FFMPEG_REVISION
  }
}

target "app" {
  context = "source"
  dockerfile = "../Dockerfile"
  contexts = {
    ffmpeg-builder = "target:ffmpeg"
  }
  args = {
    HOTIO_BASE_IMAGE = "ghcr.io/hotio/base:noblevpn@${BASE_DIGEST}"
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
