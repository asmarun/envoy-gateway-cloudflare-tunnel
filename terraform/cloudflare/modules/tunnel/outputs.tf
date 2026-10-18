output "tunnel_id" {
  description = "Tunnel ID."
  value       = cloudflare_zero_trust_tunnel_cloudflared.this.id
}

output "cname_target" {
  description = "Hostname that proxied DNS records must point at to reach this tunnel."
  value       = "${cloudflare_zero_trust_tunnel_cloudflared.this.id}.cfargotunnel.com"
}

output "tunnel_token" {
  description = "Token the cloudflared connectors use to authenticate. Store it in a Secret, never in git."
  value       = data.cloudflare_zero_trust_tunnel_cloudflared_token.this.token
  sensitive   = true
}
