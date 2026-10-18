output "published_hostnames" {
  description = "Hostnames now served by the tunnel."
  value       = sort(keys(local.routes_by_hostname))
}
