# Migrating from Application Gateway + AGIC

This is a plan, not a promise: every estate has different annotations, certificates and WAF rules. Treat the mapping table as a starting point and verify each row against the versions you run.

## 1. Inventory what AGIC is actually doing

List every Ingress and the `appgw.ingress.kubernetes.io/*` annotations on it. Also list what lives on the Application Gateway itself and is **not** in Kubernetes: WAF policy and custom rules, custom error pages, rewrite rule sets, listener certificates, health probes configured outside AGIC. Those are the things that will not migrate by translating YAML.

```bash
kubectl get ingress -A -o json | jq -r '
  .items[] | . as $i |
  ($i.metadata.annotations // {}) | to_entries[] |
  select(.key | startswith("appgw.ingress.kubernetes.io")) |
  "\($i.metadata.namespace)/\($i.metadata.name)  \(.key)=\(.value)"'
```

## 2. Annotation to Gateway API / Envoy mapping

| AGIC annotation or Application Gateway feature | Gateway API / Envoy Gateway equivalent | Notes |
|---|---|---|
| `ssl-redirect` | `HTTPRoute` filter `RequestRedirect` (scheme `https`), or Cloudflare "Always Use HTTPS" | With a tunnel, TLS ends at Cloudflare; do the redirect there |
| `request-timeout` | `BackendTrafficPolicy` `timeout.http.requestTimeout` | Per route or per Gateway |
| `backend-path-prefix` | `HTTPRoute` filter `URLRewrite` (`ReplacePrefixMatch`) | Standard Gateway API |
| `health-probe-path` / interval / timeout | `BackendTrafficPolicy` `healthCheck.active` | Plus `passive` for outlier detection |
| `cookie-based-affinity` | `BackendTrafficPolicy` `loadBalancer` (consistent hash on a cookie) | Check support in your Envoy Gateway version |
| `connection-draining` | Envoy drains on endpoint removal; add a `preStop` sleep and a sane `terminationGracePeriodSeconds` on the app | Behaviour lives in the pod spec, not a gateway setting |
| `backend-protocol: https` | `BackendTLSPolicy` | Check the support level in your Gateway API and Envoy Gateway versions |
| `appgw-ssl-certificate` / listener certs | Certificates at the Cloudflare edge; for end-to-end TLS, a TLS listener on the Gateway with cert-manager | See [trade-offs](trade-offs.md) |
| `waf-policy-for-path` and WAF rules | Cloudflare WAF (managed rules, custom rules, rate limiting) | **Not a like-for-like swap.** Rule sets, tuning and plan entitlements differ; re-validate |
| Rewrite rule sets | `HTTPRoute` `RequestHeaderModifier`, `ResponseHeaderModifier`, `URLRewrite` | Complex regex rewrites may need Envoy extension policies |
| Private frontend IP / internal-only apps | Not what tunnels are for | Use Cloudflare Access or WARP for internal apps, or keep an internal load balancer |

An example of the translation is in [`deploy/sample-app/`](../deploy/sample-app/): an `HTTPRoute` plus a `BackendTrafficPolicy` carrying the timeout, health check and rate limit.

## 3. Build alongside, don't swap in place

1. Install Envoy Gateway and the `edge` Gateway in the cluster. They coexist with AGIC; nothing changes for live traffic.
2. Create the tunnel and a **test hostname** (for example `new.example.com`) pointing at the same backends via `HTTPRoute`s.
3. Compare behaviour on the test hostname against the live one: status codes, redirects, headers, cookies, large uploads, WebSockets/gRPC, timeouts, and the client IP your app sees.
4. Re-create WAF behaviour in Cloudflare and test it with realistic attack and false-positive samples, not just the happy path.

## 4. Cut over

- Lower the DNS TTL ahead of time, then change the production hostname's record to the tunnel CNAME (or add the hostname to `published_routes`, which creates it).
- Cut over one hostname or service at a time, lowest risk first.
- Watch error rate, latency and the client-IP logs for the first hour of each cutover.

## 5. Rollback

Keep Application Gateway and AGIC running, unchanged, until the new path has carried real production traffic through a full business cycle. Rolling back is then a DNS change back to the gateway's address. Only decommission the gateway after that window, and take a copy of its configuration (WAF policy, rewrite rules, certificates inventory) before you delete anything.

## 6. Decommission

Remove the Ingress objects and AGIC, delete the Application Gateway, release its public IP, and remove the now-unused subnet and NSG rules. Then re-check the bill: that is the point of the exercise.
