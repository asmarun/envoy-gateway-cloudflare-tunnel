#!/usr/bin/env bash
# Sends steady traffic through the quick tunnel while one Envoy pod is deleted,
# then reports how many requests failed. Needs `make tunnel-quick` first.
#
# This is an observation, not a guarantee: one sequential client, low rate. Use a
# proper load tool and your own SLOs before drawing conclusions for production.
set -euo pipefail

URL="${URL:-$(kubectl -n cloudflared logs deployment/cloudflared-quick 2>/dev/null \
  | grep -Eo 'https://[a-z0-9-]+\.trycloudflare\.com' | tail -1)}"
REQUESTS="${REQUESTS:-80}"
[[ -n "$URL" ]] || { echo "No tunnel URL. Run: make tunnel-quick"; exit 1; }

POD=$(kubectl -n envoy-gateway-system get pods \
  -l gateway.envoyproxy.io/owning-gateway-name=edge -o name | head -1)
echo "Target: $URL"
echo "Deleting $POD after 4s while sending $REQUESTS requests..."

( sleep 4; kubectl -n envoy-gateway-system delete "$POD" --wait=false >/dev/null 2>&1 ) &

ok=0; bad=0
for i in $(seq 1 "$REQUESTS"); do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$URL/" || echo 000)
  if [[ "$code" == "200" ]]; then ok=$((ok + 1)); else bad=$((bad + 1)); echo "  request $i -> $code"; fi
  sleep 0.25
done
wait

echo "ok=$ok failed=$bad"
[[ "$bad" -eq 0 ]]
