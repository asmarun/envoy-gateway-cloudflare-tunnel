#!/usr/bin/env bash
# Drill: kill cloudflared connectors one at a time while sending traffic through a
# NAMED tunnel, and count failed requests.
#
# Needs a named tunnel with 2+ connectors: `make tunnel-named` (Cloudflare account
# and domain required) and URL set to a hostname published on that tunnel.
#
#   URL=https://lab.example.com make drill-connector-failure
#
# Status: written but NOT yet run against a real tunnel (no Cloudflare account was
# used for this lab). Record your results in docs/availability.md.
set -euo pipefail

URL="${URL:?Set URL to a hostname published on your named tunnel}"
SELECTOR="app.kubernetes.io/name=cloudflared,app.kubernetes.io/instance=named"
NS=cloudflared
DURATION="${DURATION:-120}"

pods=($(kubectl -n "$NS" get pods -l "$SELECTOR" -o name))
echo "Connectors: ${#pods[@]}"
[[ ${#pods[@]} -ge 2 ]] || { echo "Need at least 2 connectors for this drill."; exit 1; }

ok=0; bad=0
end=$(( $(date +%s) + DURATION ))
next_kill=$(( $(date +%s) + 20 ))
i=0
while [[ $(date +%s) -lt $end ]]; do
  c=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$URL/" || echo 000)
  if [[ "$c" == "200" ]]; then ok=$((ok + 1)); else bad=$((bad + 1)); echo "  $(date +%T) -> $c"; fi
  if [[ $(date +%s) -ge $next_kill && $i -lt ${#pods[@]} ]]; then
    echo "  $(date +%T) deleting ${pods[$i]}"
    kubectl -n "$NS" delete "${pods[$i]}" --wait=false >/dev/null
    i=$((i + 1)); next_kill=$(( $(date +%s) + 30 ))
  fi
  sleep 0.5
done
echo "ok=$ok failed=$bad over ${DURATION}s with $i connector deletions"
