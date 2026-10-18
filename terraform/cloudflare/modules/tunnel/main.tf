resource "cloudflare_zero_trust_tunnel_cloudflared" "this" {
  account_id = var.account_id
  name       = var.name

  # "cloudflare" = remotely managed: routes live in Cloudflare (managed by the
  # tunnel-routes module), connectors only need the token.
  config_src = "cloudflare"
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "this" {
  account_id = var.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.this.id
}
