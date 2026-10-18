#!/usr/bin/env bash
# Smoke test for the Gateway, without needing a Cloudflare account.
#
# It runs a throwaway curl pod that *looks like* a cloudflared pod (same
# namespace and labels), so it is allowed through the NetworkPolicy, and checks:
#   1. a request carrying CF-Connecting-IP reaches the demo app  -> HTTP 200
#   2. a request WITHOUT that header is refused (failClosed)     -> not 200
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

ORIGIN="${ORIGIN:-http://edge-envoy.envoy-gateway-system.svc.cluster.local}"
LABELS="app.kubernetes.io/name=cloudflared,app.kubernetes.io/instance=smoke"

echo "Waiting for the Gateway to be programmed..."
kubectl -n edge wait --for=condition=Programmed gateway/edge --timeout=180s
kubectl -n envoy-gateway-system rollout status deployment \
  -l gateway.envoyproxy.io/owning-gateway-name=edge --timeout=180s
kubectl -n demo rollout status deployment/podinfo --timeout=180s

# One retry: the very first pod on a fresh cluster can lose a race with the image pull.
request() {
  local code
  code=$(run_curl cloudflared "$LABELS" "$@")
  if [[ -z "$code" ]]; then code=$(run_curl cloudflared "$LABELS" "$@"); fi
  echo "$code"
}

fail=0

code=$(request -H 'CF-Connecting-IP: 203.0.113.10' "$ORIGIN/")
if [[ "$code" == "200" ]]; then
  echo "PASS  with CF-Connecting-IP    -> $code"
else
  echo "FAIL  with CF-Connecting-IP    -> '$code' (expected 200)"; fail=1
fi

code=$(request "$ORIGIN/")
if [[ "$code" != "200" && -n "$code" ]]; then
  echo "PASS  without CF-Connecting-IP -> '$code' (refused, as intended)"
else
  echo "FAIL  without CF-Connecting-IP -> '$code' (expected a refusal)"; fail=1
fi

exit $fail
