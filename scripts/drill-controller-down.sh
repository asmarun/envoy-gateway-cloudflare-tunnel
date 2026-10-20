#!/usr/bin/env bash
# Drill: lose the Envoy Gateway controller while traffic is flowing.
#
# Expectation (to be confirmed by this run, not assumed):
#   - existing routes keep being served by the Envoy data plane
#   - a NEW route applied while the controller is down is NOT programmed
#   - once the controller returns, the new route is reconciled and served
#
# Needs no Cloudflare account: requests come from a throwaway pod that looks like
# cloudflared (so it is allowed through the NetworkPolicy).
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

ORIGIN="${ORIGIN:-http://edge-envoy.envoy-gateway-system.svc.cluster.local}"
LABELS="app.kubernetes.io/name=cloudflared,app.kubernetes.io/instance=drill"
HDR='CF-Connecting-IP: 203.0.113.10'
CTRL=envoy-gateway
NS=envoy-gateway-system

req() { # path -> http code, one retry for fresh-cluster image pulls
  local c
  c=$(run_curl cloudflared "$LABELS" -H "$HDR" "$ORIGIN$1")
  [[ -n "$c" ]] || c=$(run_curl cloudflared "$LABELS" -H "$HDR" "$ORIGIN$1")
  echo "$c"
}

orig=$(kubectl -n "$NS" get deploy "$CTRL" -o jsonpath='{.spec.replicas}')
restore() {
  kubectl -n demo delete httproute drill-new-route --ignore-not-found >/dev/null 2>&1 || true
  kubectl -n "$NS" scale deploy "$CTRL" --replicas="$orig" >/dev/null 2>&1 || true
}
trap restore EXIT

fail=0
check() { # label expected actual
  if [[ "$3" == "$2" ]]; then echo "PASS  $1 -> $3"; else echo "FAIL  $1 -> '$3' (expected $2)"; fail=1; fi
}

check "baseline, existing route"            200 "$(req /)"

echo "Scaling the controller to 0 (was $orig)..."
kubectl -n "$NS" scale deploy "$CTRL" --replicas=0 >/dev/null
kubectl -n "$NS" wait --for=delete pod -l control-plane=envoy-gateway --timeout=120s >/dev/null 2>&1 || true

check "controller down, existing route"      200 "$(req /)"

echo "Applying a NEW route while the controller is down..."
kubectl apply -f - >/dev/null <<'YAML'
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: drill-new-route
  namespace: demo
spec:
  parentRefs:
    - name: edge
      namespace: edge
      sectionName: http
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /drill
      filters:
        - type: URLRewrite
          urlRewrite:
            path:
              type: ReplaceFullPath
              replaceFullPath: /healthz
      backendRefs:
        - name: podinfo
          port: 80
YAML
sleep 15
# Without the route, /drill falls through to the app and returns 404. With it, the
# rewrite sends the request to /healthz and returns 200.
check "controller down, NEW route NOT served" 404 "$(req /drill)"

echo "Restoring the controller to $orig replicas..."
start=$(date +%s)
kubectl -n "$NS" scale deploy "$CTRL" --replicas="$orig" >/dev/null
code=""
for _ in $(seq 1 60); do
  code=$(req /drill)
  [[ "$code" == "200" ]] && break
  sleep 3
done
elapsed=$(( $(date +%s) - start ))
check "controller back, NEW route served"    200 "$code"
echo "      time from scale-up to the new route being served: ${elapsed}s"

exit $fail
