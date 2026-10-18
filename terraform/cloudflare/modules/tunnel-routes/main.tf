locals {
  routes = [
    for r in var.published_routes : {
      hostname = lower(trimspace(r.hostname))
      service  = trimspace(r.service)
    }
  ]

  routes_by_hostname = { for r in local.routes : r.hostname => r }
}

# Cloudflare stores a tunnel's published routes as ONE ordered ingress list.
# Every apply replaces the whole list, so exactly one Terraform state must own
# it. If dev, qa and uat each applied "their" hostname from separate states, the
# last apply would silently delete the others. See docs/architecture.md.
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "this" {
  account_id = var.account_id
  tunnel_id  = var.tunnel_id

  config = {
    ingress = concat(
      [for r in local.routes : { hostname = r.hostname, service = r.service }],
      # Cloudflare requires the last rule to be a catch-all with no hostname.
      [{ service = var.catch_all_service }],
    )
  }
}

# One proxied CNAME per published hostname, pointing at the tunnel.
resource "cloudflare_dns_record" "route" {
  for_each = local.routes_by_hostname

  zone_id = var.zone_id
  name    = each.key
  content = "${var.tunnel_id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = var.proxied
  ttl     = 1 # 1 = automatic, required for proxied records
}
