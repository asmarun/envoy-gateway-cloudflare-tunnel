# Trade-offs, honestly

This pattern is not free of costs. It moves some of them from your cloud bill to other places. Decide with the downsides in view.

## What you gain
- **No inbound exposure.** No public IP or load balancer for ingress; the cluster only makes outbound connections.
- **Config as Kubernetes objects.** Routing, timeouts and rate limits are Gateway API and Envoy policy resources, reviewed and deployed like any other manifest, and reprogrammed in-cluster rather than through a cloud control plane.
- **Portability.** Gateway API is vendor-neutral; the same routes run on any conformant implementation.
- **A different cost shape.** Often lower, but you must measure it for your estate. See [cost-model.md](cost-model.md).

## What you give up or take on

### A third party in the request path
Cloudflare terminates TLS and sees plaintext traffic. That is a security, privacy and compliance question: check your data-handling requirements and contracts before you route regulated traffic through it. It is also a **hard dependency**: if Cloudflare is down or your account is suspended, ingress is down, and there is no cloud-native fallback unless you build one.

### WAF is not a like-for-like swap
Application Gateway WAF and Cloudflare WAF have different rule sets, tuning workflows and plan entitlements. You will re-validate protection, not just re-point it. Budget time for false-positive tuning.

### Client IP handling is now your responsibility
Your apps see Cloudflare's connection unless you handle `CF-Connecting-IP`. This lab does it at the proxy with `failClosed`, and protects the header with a NetworkPolicy. Skip either half and you have a spoofing problem.

### Plain HTTP inside the cluster
This lab terminates TLS at Cloudflare and speaks HTTP from cloudflared to Envoy over the cluster network. That is acceptable for many teams; for stricter requirements add a TLS listener on the Gateway (cert-manager) and run the tunnel origin over HTTPS, or use a service mesh with mTLS. It costs complexity.

### Operational ownership moves to you
Application Gateway is a managed service. Envoy Gateway and cloudflared are workloads you upgrade, monitor, size and page on. You need dashboards for Envoy and cloudflared, alerts on tunnel health, and a runbook ([operations.md](operations.md)).

### Route ownership is a footgun
One tunnel's route list is a single object. Without a clear single owner in Terraform, parallel applies silently overwrite each other ([architecture.md](architecture.md), decision 3).

### Limits and features vary by plan
Request size limits, WebSocket and gRPC support, rate-limiting features and WAF capabilities depend on your Cloudflare plan. Check them against your actual traffic before committing.

### Latency path
Requests take edge → tunnel → cluster. For a single-region app that can be slower than a regional gateway for users near the cluster, and faster for distant users. Measure from where your users are.

## Alternatives to weigh
| Option | When it fits |
|---|---|
| Keep Application Gateway + AGIC | You need an Azure-native WAF, private frontends, or the lowest operational ownership |
| Application Gateway for Containers | Azure-native, supports Gateway API, keeps you inside one vendor |
| Azure Front Door | Global entry, Azure-native WAF, multi-region failover |
| In-cluster Envoy Gateway behind a plain cloud load balancer | You want Gateway API without a third party in the path, and accept a public load balancer |
| This pattern | Cost and exposure matter, you can accept Cloudflare as a dependency, and you can own the operations |

## When not to use this
- Regulated data that cannot transit a third party.
- Internal-only apps that need private frontends (use Cloudflare Access or WARP, or keep an internal load balancer).
- A team with no capacity to run Envoy and cloudflared as production services.
