#!/usr/bin/env bash
# Smoke test for the Gateway, without needing a Cloudflare account.
#
# It runs a throwaway curl pod that *looks like* a cloudflared pod (same
# namespace and labels), so it is allowed through the NetworkPolicy, and checks:
#   1. a request carrying CF-Connecting-IP reaches the demo app  -> HTTP 200
#   2. a request WITHOUT that header is refused (failClosed)     -> not 200
set -euo pipefail

ORIGIN="${ORIGIN:-http://edge-envoy.envoy-gateway-system.svc.cluster.local}"
NS=cloudflared
POD="smoke-$RANDOM"

echo "Waiting for the Gateway to be programmed..."
kubectl -n edge wait --for=condition=Programmed gateway/edge --timeout=180s
kubectl -n envoy-gateway-system rollout status deployment \
  -l gateway.envoyproxy.io/owning-gateway-name=edge --timeout=180s
kubectl -n demo rollout status deployment/podinfo --timeout=180s

run_curl() {
  kubectl -n "$NS" run "$POD" --rm -i --restart=Never --quiet \
    --labels="app.kubernetes.io/name=cloudflared,app.kubernetes.io/instance=smoke" \
    --image=curlimages/curl:8.11.1 --command -- \
    curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$@"
}

fail=0

code=$(run_curl -H 'CF-Connecting-IP: 203.0.113.10' "$ORIGIN/" || true)
if [[ "$code" == "200" ]]; then
  echo "PASS  with CF-Connecting-IP    -> $code"
else
  echo "FAIL  with CF-Connecting-IP    -> '$code' (expected 200)"; fail=1
fi

POD="smoke-$RANDOM"
code=$(run_curl "$ORIGIN/" || true)
if [[ "$code" != "200" ]]; then
  echo "PASS  without CF-Connecting-IP -> '$code' (refused, as intended)"
else
  echo "FAIL  without CF-Connecting-IP -> 200 (should have been refused)"; fail=1
fi

exit $fail
