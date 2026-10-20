# Operations runbook

## What to monitor

| Signal | Source | Alert when |
|---|---|---|
| cloudflared ready | `GET :2000/ready` (returns `readyConnections`), kube readiness | Fewer than your floor of ready connectors for more than a few minutes |
| Tunnel connections | `cloudflared_tunnel_ha_connections` on `:2000/metrics` | Any connector at zero connections |
| Origin errors | `cloudflared_tunnel_request_errors`, `cloudflared_proxy_connect_streams_errors` | Rising rate |
| Envoy health | Envoy metrics on `:19001` | 5xx rate or upstream connect failures rising |
| Envoy replicas | HPA / PDB status | At `maxReplicas` for a sustained period |
| Controller reconcile | Envoy Gateway controller logs (level `warn`) | Repeated errors applying Gateway API objects |
| Route list drift | Terraform plan on the `tunnel-routes` state | Any unexpected diff |
| Edge errors | Cloudflare analytics | Spike in 52x (origin unreachable) |

Also keep a synthetic check that requests a known hostname from outside the cluster, independent of your own monitoring stack.

See [availability.md](availability.md) for why liveness uses `/healthcheck` and readiness uses `/ready`.

## Common situations

### Origin unreachable (Cloudflare 52x errors)
1. Is cloudflared Ready? `kubectl -n cloudflared get pods`; `kubectl -n cloudflared logs deploy/cloudflared`.
2. Can cloudflared reach Envoy? Check the origin URL in the route list matches the Service (`edge-envoy.envoy-gateway-system.svc.cluster.local:80`).
3. Is the NetworkPolicy blocking it? Selectors must match cloudflared's labels and the Envoy **container** port (10080).
4. Is Envoy rejecting requests? Without `CF-Connecting-IP` it fails closed by design.

### A hostname returns 404 from Cloudflare
The hostname is not in `published_routes`, so it hit the catch-all. Add it in the single state that owns the tunnel and apply.

### Rotate the tunnel token
Tokens are credentials. To rotate: delete and recreate the tunnel resource (or rotate via the Cloudflare dashboard/API), apply, update the `cloudflared-token` Secret, and restart the deployment. Do it replica by replica; the PDB and `maxUnavailable: 0` keep traffic flowing.

## Upgrades

### cloudflared
Bump the image tag, apply, and let the rolling update (`maxUnavailable: 0`) replace one pod at a time. Watch the ready count.

### Envoy Gateway
1. Read the release notes for the target version, especially CRD and API changes.
2. Upgrade the Helm release (`make install-envoy ENVOY_GATEWAY_VERSION=vX.Y.Z`). Check how your chart version manages the CRDs, and apply them explicitly first if the chart does not upgrade them for you.
3. Roll the data plane (Envoy proxies upgrade via the controller) and watch error rate.
4. Test in a non-production cluster first.

### Kubernetes
Drain nodes one at a time; the PDBs on cloudflared and Envoy protect availability. Confirm the topology spread still holds afterwards.

## Change process for routes
- App routes (`HTTPRoute`) change with the app, owned by the app team.
- Hostnames in the tunnel change through a pull request to the Terraform that owns the route list, with `terraform plan` output attached. Never edit the route list in the dashboard in parallel, or the next apply will overwrite it.

## Secrets
- The tunnel token lives only in a Kubernetes Secret (or your secret manager). Never in git, state files you share, or logs.
- Terraform state contains the token: use an encrypted remote backend with restricted access.
- CI runs gitleaks to catch accidental commits.
