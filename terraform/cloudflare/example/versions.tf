terraform {
  required_version = ">= 1.6"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = ">= 5.18, < 6.0"
    }
  }

  # Local state keeps the lab simple. For real use, put state in a remote
  # backend with locking, one state per tunnel.
}
