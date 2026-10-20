#!/usr/bin/env bash
# Drill: block cloudflared's tunnel egress (port 7844) and measure what happens.
#
# Compares two liveness-probe choices on the quick-tunnel connector:
#   LIVENESS=ready        probe /ready       (503 when no edge connection)
#   LIVENESS=healthcheck  probe /healthcheck (always OK while the process lives)
#
# Hypothesis under test: a liveness probe tied to /ready restarts the connector on
# every connectivity loss, so after the outage the pod sits in CrashLoopBackOff and
# recovery is slower than with a process-level liveness check.
#
# Needs: `make tunnel-quick` first, internet access, and a CNI that enforces
# NetworkPolicy (the minikube target uses Calico).
set -euo pipefail

LIVENESS="${LIVENESS:-ready}"
BLOCK_SECONDS="${BLOCK_SECONDS:-90}"
NS=cloudflared
DEP=cloudflared-quick
POLICY="$(dirname "$0")/../drills/egress-block-policy.yaml"

case "$LIVENESS" in
  ready) PATH_="/ready" ;;
  healthcheck) PATH_="/healthcheck" ;;
  *) echo "LIVENESS must be 'ready' or 'healthcheck'"; exit 2 ;;
esac

current_url() {
  kubectl -n "$NS" logs "deployment/$DEP" 2>/dev/null \
    | grep -Eo 'https://[a-z0-9-]+\.trycloudflare\.com' | tail -1 || true
}
public_code() {
  local u; u=$(current_url)
  [[ -n "$u" ]] && curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$u/" || echo 000
}
pod_state() {
  kubectl -n "$NS" get pod -l app.kubernetes.io/instance=quick \
    -o jsonpath='{.items[0].status.containerStatuses[0].restartCount} ready={.items[0].status.containerStatuses[0].ready}'
}
cleanup() { kubectl delete -f "$POLICY" --ignore-not-found >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "Liveness probe under test: GET $PATH_ (failureThreshold 1, period 10s)"
kubectl -n "$NS" patch deployment "$DEP" --type=json -p="[
  {\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/livenessProbe\",\"value\":
    {\"httpGet\":{\"path\":\"$PATH_\",\"port\":\"metrics\"},\"initialDelaySeconds\":10,\"periodSeconds\":10,\"failureThreshold\":1}}
]" >/dev/null
kubectl -n "$NS" rollout status "deployment/$DEP" --timeout=120s >/dev/null
sleep 15
echo "Baseline: public request -> $(public_code), pod: $(pod_state)"

echo "Blocking egress for ${BLOCK_SECONDS}s (policy drops everything except DNS, Envoy and 443)..."
kubectl apply -f "$POLICY" >/dev/null
# Existing flows survive a new policy, so restart the pod to force a fresh connect.
kubectl -n "$NS" delete pod -l app.kubernetes.io/instance=quick --wait=false >/dev/null
end=$(( $(date +%s) + BLOCK_SECONDS ))
while [[ $(date +%s) -lt $end ]]; do
  sleep 15
  echo "  blocked: public request -> $(public_code), pod: $(pod_state 2>/dev/null || echo 'starting')"
done

echo "Removing the block; measuring recovery..."
kubectl delete -f "$POLICY" >/dev/null
start=$(date +%s)
rec=""
for _ in $(seq 1 120); do
  c=$(public_code)
  if [[ "$c" == "200" ]]; then rec=$(( $(date +%s) - start )); break; fi
  sleep 5
done
echo "RESULT liveness=$LIVENESS recovery=${rec:-not recovered in 600s}s, final pod: $(pod_state)"
