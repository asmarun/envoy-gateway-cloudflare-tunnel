provider "cloudflare" {
  # Authenticate with an API token in the environment:
  #   export CLOUDFLARE_API_TOKEN=...
  # Minimum permissions: Account > Cloudflare Tunnel > Edit, Zone > DNS > Edit.
}

module "tunnel" {
  source = "../modules/tunnel"

  account_id = var.cloudflare_account_id
  name       = var.tunnel_name
}

# One state owns the complete route list for this tunnel (see the module).
module "routes" {
  source = "../modules/tunnel-routes"

  account_id = var.cloudflare_account_id
  zone_id    = var.cloudflare_zone_id
  tunnel_id  = module.tunnel.tunnel_id

  published_routes = [
    for hostname in var.hostnames : {
      hostname = hostname
      service  = var.origin_service
    }
  ]
}
