# Cost model

This page gives you a way to compare the two designs for **your** estate. It contains no prices because they change and depend on region, plan and negotiated rates. Fill the worksheet from your own bill and the vendors' current price pages.

## What each design bills

| Cost driver | Application Gateway + AGIC | Cloudflare Tunnel + Envoy Gateway |
|---|---|---|
| Gateway fixed charge | Hourly charge per gateway, per environment | None for the tunnel itself; Cloudflare plan fee if you need paid features |
| Throughput / capacity | Capacity units consumed over time (varies with connections, throughput, compute) | Cloudflare plan limits; Envoy CPU and memory in your own nodes |
| Data processing / transfer | Per-GB gateway processing and outbound transfer | Outbound transfer from your cluster to Cloudflare (tunnel traffic); Cloudflare plan terms |
| Public IP | Typically a static public IP per gateway | None |
| Subnet and networking | Dedicated gateway subnet | None for ingress |
| WAF | WAF-tier gateway pricing | Cloudflare WAF entitlement on your plan |
| In-cluster compute | AGIC controller pods | Envoy proxy pods + Envoy Gateway controller + cloudflared pods |
| People time | Mostly managed by Azure | You run, upgrade and monitor Envoy and cloudflared |

## Count gateways, not just environments

The gateway's fixed charge is paid **per gateway**. Depending on your backend-settings needs, one cluster can end up with more than one gateway in front of it (for example several for non-production and several for production), and the WAF tier adds to each. So the number to put in the worksheet is the total number of gateways across all clusters, not the number of environments.

## Worksheet

Compare one environment at a time, per month.

| Line | Current (gateway + AGIC) | Proposed (tunnel + Envoy) |
|---|---|---|
| Gateway fixed cost | | |
| Capacity / throughput cost | | |
| Data processing + transfer | | |
| Public IP | | |
| WAF | | |
| Extra in-cluster compute (pods x requests) | | |
| Cloudflare plan | | |
| **Subtotal** | | |
| Engineering time to run it (hours x rate) | | |
| **Total** | | |

## How to get honest numbers

1. **Current side:** use Azure Cost Management filtered to the gateway resource group and public IPs for a full billing month. Split fixed from usage-based.
2. **Proposed side:** run Envoy and cloudflared at your real traffic level and read their actual CPU and memory from metrics, then price those requests at your node cost. A tool like Kubecost or OpenCost does this per pod.
3. **Multiply by environments.** The fixed gateway charge is paid per environment, which is why the saving usually grows with environment count, not with traffic.
4. **Include the migration.** One-time engineering effort and a rollback window where you pay for both.

## Interpreting the result

- If your traffic is low and you have many environments, the fixed charges dominate and the new design tends to look better.
- If your traffic is very high, compare capacity-unit cost against Envoy's compute and the Cloudflare plan you would need.
- A saving that disappears once you price the people time to run it is not a saving. Say so in your decision record.
