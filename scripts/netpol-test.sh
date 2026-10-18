#!/usr/bin/env bash
# Proves the NetworkPolicy: a pod that is NOT cloudflared cannot reach Envoy,
# even with a valid-looking CF-Connecting-IP header.
#
# Requires a CNI that enforces NetworkPolicy (the Makefile's minikube target
# starts the lab with Calico). On a cluster without enforcement this test fails,
# which is the correct result: your policy would not be protecting anything.
set -euo pipefail

ORIGIN="${ORIGIN:-http://edge-envoy.envoy-gateway-system.svc.cluster.local}"
POD="intruder-$RANDOM"

code=$(kubectl -n demo run "$POD" --rm -i --restart=Never --quiet \
  --image=curlimages/curl:8.11.1 --command -- \
  curl -s -o /dev/null -w '%{http_code}' --max-time 5 \
  -H 'CF-Connecting-IP: 203.0.113.10' "$ORIGIN/" || true)

# curl prints 000 when the connection times out or is refused.
if [[ "$code" == "000" || -z "$code" ]]; then
  echo "PASS  pod outside cloudflared cannot reach Envoy (connection blocked)"
else
  echo "FAIL  pod outside cloudflared reached Envoy -> HTTP $code"
  echo "      Is the NetworkPolicy applied, and does your CNI enforce it?"
  exit 1
fi
