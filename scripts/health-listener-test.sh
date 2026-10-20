#!/usr/bin/env bash
# Verifies the OPTIONAL health listener (deploy/optional/health-listener.yaml):
#   - the main listener still fails closed without CF-Connecting-IP
#   - the health listener serves ONE path without the header
#   - the health listener exposes nothing else
#   - a pod that is not cloudflared cannot reach it (needs an enforcing CNI)
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

O="${ORIGIN:-http://edge-envoy.envoy-gateway-system.svc.cluster.local}"
L="app.kubernetes.io/name=cloudflared,app.kubernetes.io/instance=healthtest"
fail=0
check() { if [[ "$3" == "$2" ]]; then echo "PASS  $1 -> $3"; else echo "FAIL  $1 -> '$3' (expected $2)"; fail=1; fi; }

kubectl -n edge wait --for=condition=Programmed gateway/edge --timeout=120s >/dev/null
sleep 5
check "main listener, no header, /"            403 "$(run_curl cloudflared "$L" "$O/")"
check "main listener, header, /"               200 "$(run_curl cloudflared "$L" -H 'CF-Connecting-IP: 203.0.113.10' "$O/")"
check "health listener, no header, /readyz"    200 "$(run_curl cloudflared "$L" "$O:8081/readyz")"
check "health listener, no header, / (404)"    404 "$(run_curl cloudflared "$L" "$O:8081/")"
check "intruder to health listener (blocked)"  000 "$(run_curl demo "" "$O:8081/readyz")"
exit $fail
