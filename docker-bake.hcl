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

target "app" {
  context = "."
  dockerfile = "Dockerfile"
  args = {
    HOTIO_BASE_IMAGE = "ghcr.io/hotio/base:noblevpn@${BASE_DIGEST}"
    UPSTREAM_IMAGE = UPSTREAM_IMAGE
    DISPATCHARR_VERSION = VERSION
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
