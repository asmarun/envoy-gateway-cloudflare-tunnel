# Availability

Replacing a managed, zone-redundant gateway with Envoy and `cloudflared` means **you now own the availability of ingress**, and a SaaS vendor sits in the path. This page says what the lab protects against, what it does not, and what was actually tested. Anything not marked as tested is a design claim, not a result.

Lab used for the drills: minikube, Kubernetes 1.33.1, Calico, Envoy Gateway v1.9.2, cloudflared 2026.10.1, a **quick tunnel** (one connector). Numbers are single runs and indicative, not benchmarks.

## What protects what

| Failure | Expected behaviour | Tested in the lab? |
|---|---|---|
| One Envoy proxy pod lost | Remaining replicas serve; HPA and PDB protect during drains | Yes: 80 of 80 requests succeeded while a pod was deleted |
| Envoy Gateway controller lost | Data plane keeps serving its last configuration; route and policy **changes** are not applied until a controller returns | Yes ([drill](#drill-controller-down)) |
| Tunnel egress blocked (firewall, NAT, routing) | Connector becomes not-ready, edge returns 530; recovery depends on the probes you chose | Yes ([drill](#drill-egress-block)) |
| One cloudflared connector lost | Other connectors keep the tunnel up | **No**: needs a named tunnel ([drill script](#drill-connector-failure), not yet run) |
| Node drain | PDBs and `maxUnavailable: 0` keep a floor of connectors and proxies | **No**: the lab is single-node |
| Availability-zone loss | Surviving pods serve, *if* the node pool spans zones | **No** |
| A whole cluster or region | One tunnel per cluster plus Cloudflare Load Balancer health checks steer to the healthy side | **No**: described, not simulated |
| Cloudflare itself unavailable | Ingress is down. There is no cloud-native fallback unless you build one | **No** |

Two facts that are easy to get wrong:
- **PodDisruptionBudgets only limit voluntary disruptions.** A node or zone that fails is not stopped by a PDB.
- **Topology spread rules set to `ScheduleAnyway` are preferences.** Replicas can co-locate rather than stay Pending, and spreading cannot create capacity in a zone your node pool does not span.

## Drills

Run them with `make`; each one states its expectation up front so a pass means something.

### Drill: controller down
`make drill-controller-down` (no Cloudflare account needed; also runs in CI)

Scales the Envoy Gateway controller to zero under traffic, applies a **new** route, then restores the controller.

| Step | Result |
|---|---|
| Existing route, controller down | 200, still served by the data plane |
| New route applied while controller down | 404, **not programmed** |
| Controller restored | New route served about **25 s** after scale-up |

**Meaning:** a controller outage does not drop traffic, but you cannot ship a route or policy change, including an emergency rollback, until a controller leader returns. Know your break-glass path.

### Drill: egress block
`make drill-egress-block` with `LIVENESS=ready` or `LIVENESS=healthcheck` (needs internet and an enforcing CNI)

Blocks everything except DNS, the in-cluster Envoy origin and HTTPS (443) for 90 seconds, which simulates a firewall that allows 443 but not the tunnel port. Then it removes the block and measures recovery.

| Liveness probe | Restarts during the 90 s block | Recovery after the block was removed |
|---|---|---|
| `GET /ready` | 5 | **165 s** |
| `GET /healthcheck` | 0 | **10 s** |

Findings:
- **Allowing 443 is not enough.** With 7844 blocked the tunnel did not connect; the edge returned 530.
- **Do not tie liveness to `/ready`.** `/ready` reports edge connectivity (it returns the number of ready connections), so during an egress or Cloudflare problem every connector fails liveness, restarts in a loop, and then waits in CrashLoopBackOff after the problem ends. `/healthcheck` checks the process. Keep **readiness** on `/ready`, so a connector with no edge connection stops counting as available, and put **liveness** on `/healthcheck`. The shipped manifests use that split.
- Single run per probe, one connector; treat the exact timings as indicative.

### Drill: connector failure
`URL=https://your-host make drill-connector-failure`

Deletes connectors one at a time under traffic and counts failed requests. It needs a named tunnel with two or more connectors, so it **has not been run** in this lab. Record your results here when you run it.

## Health checks and fail-closed

The main listener rejects any request without `CF-Connecting-IP` (fail-closed). A health monitor that probes the origin may not send that header and would then see a 403 from a perfectly healthy region. **Verify this before assuming it is a problem:** point the monitor at an echo endpoint and inspect the request headers it actually sends.

If it is a problem, do not weaken the main listener. Expose one narrow path on a second listener:

```bash
make health-listener        # adds listener "health" on 8081 and an exact /readyz route
make health-listener-test   # checks it
make health-listener-remove
```

Tested behaviour: the main listener still returns 403 without the header, the health listener serves `/readyz` without it, everything else on the health listener returns 404, and a pod that is not `cloudflared` is blocked by the NetworkPolicy. Publish a separate hostname on the tunnel pointing at port 8081 and aim the monitor at it.

## Tunnel health is not origin health

A connector can be connected while the application behind it returns errors, so a connected tunnel says nothing about whether the app works. For cross-region steering, use Cloudflare Load Balancer monitors that exercise a **readiness endpoint through that region's Gateway**, and keep the load balancer's configuration in code so it can be reviewed and rebuilt.

## What to monitor

Observed on the lab's cloudflared:

- `GET :2000/ready` returns 200 with `readyConnections` and `connectorId` when connected, and a non-200 when not.
- `GET :2000/healthcheck` returns `OK` while the process is alive.
- Prometheus metrics on `:2000/metrics`, including `cloudflared_tunnel_ha_connections` (active connections), `cloudflared_tunnel_total_requests`, `cloudflared_tunnel_request_errors` and `cloudflared_proxy_connect_streams_errors`.

Alert when a connector reports zero connections, when the number of ready connectors falls below your floor, and when origin errors rise. Add an external synthetic check that does not depend on your in-cluster monitoring.

## Egress is the lifeline

With no inbound path, outbound connectivity is the only thing keeping ingress alive.
- cloudflared needs outbound access to Cloudflare on **port 7844** (QUIC over UDP, falling back to HTTP/2 over TCP) plus DNS. Its startup precheck tests the regional endpoints and the API endpoint, and prints the result in the pod log.
- A change to a firewall, NAT, route table or DNS can take every connector down **at once**. Treat egress rules as part of ingress change review.
- On shared outbound paths, other workloads can exhaust SNAT ports and make reconnects fail. Consider a dedicated or larger outbound path for the connectors.

## Not covered

- Behaviour with many connectors and a named tunnel (script written, not run).
- Node drains, zone loss and cross-region failover.
- A Cloudflare outage, and DNS failover away from Cloudflare.
- Load testing; the traffic in the drills is a single low-rate client.
