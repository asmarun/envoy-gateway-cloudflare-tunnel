variable "cloudflare_account_id" {
  description = "Cloudflare account ID."
  type        = string
}

variable "cloudflare_zone_id" {
  description = "Zone ID of the domain you will publish hostnames under."
  type        = string
}

variable "tunnel_name" {
  description = "Name for the tunnel."
  type        = string
  default     = "envoy-gateway-lab"
}

variable "hostnames" {
  description = "Hostnames to publish through the tunnel, e.g. [\"lab.example.com\"]."
  type        = list(string)
}

variable "origin_service" {
  description = "In-cluster URL of the Envoy Service (name fixed by envoyService.name in deploy/envoy-gateway/10-gateway.yaml)."
  type        = string
  default     = "http://edge-envoy.envoy-gateway-system.svc.cluster.local:80"
}
