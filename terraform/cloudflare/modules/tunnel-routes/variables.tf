variable "account_id" {
  description = "Cloudflare account ID that owns the tunnel."
  type        = string
}

variable "zone_id" {
  description = "Zone ID where the DNS records are created."
  type        = string
}

variable "tunnel_id" {
  description = "ID of the tunnel whose routes this module owns (from the tunnel module)."
  type        = string
}

variable "published_routes" {
  description = "Every hostname that must be served by this tunnel, with its origin service URL. This list is authoritative: hostnames not listed here are removed from the tunnel."
  type = list(object({
    hostname = string
    service  = string
  }))

  validation {
    condition     = length(var.published_routes) > 0
    error_message = "Provide at least one published route."
  }

  validation {
    condition = alltrue([
      for r in var.published_routes : trimspace(r.hostname) != "" && trimspace(r.service) != ""
    ])
    error_message = "Every route needs a non-empty hostname and service."
  }

  validation {
    condition     = length(distinct([for r in var.published_routes : lower(trimspace(r.hostname))])) == length(var.published_routes)
    error_message = "Hostnames must be unique (case-insensitive); duplicates would collapse into one DNS record."
  }
}

variable "catch_all_service" {
  description = "Service for requests that match no hostname."
  type        = string
  default     = "http_status:404"
}

variable "proxied" {
  description = "Whether DNS records are proxied through Cloudflare. Must be true for tunnels to serve traffic."
  type        = bool
  default     = true
}
