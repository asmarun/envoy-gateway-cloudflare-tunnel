output "tunnel_id" {
  value = module.tunnel.tunnel_id
}

output "published_hostnames" {
  value = module.routes.published_hostnames
}

output "tunnel_token" {
  description = "Feed this to the cloudflared Secret: terraform output -raw tunnel_token"
  value       = module.tunnel.tunnel_token
  sensitive   = true
}
