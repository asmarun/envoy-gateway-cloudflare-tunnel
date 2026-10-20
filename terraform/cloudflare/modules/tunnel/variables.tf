variable "account_id" {
  description = "Cloudflare account ID that owns the tunnel."
  type        = string
}

variable "name" {
  description = "Tunnel name, e.g. one per cluster or region (\"cluster-a\")."
  type        = string
}
