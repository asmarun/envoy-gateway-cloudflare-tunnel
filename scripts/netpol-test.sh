#!/usr/bin/env bash
# Proves the NetworkPolicy: a pod that is NOT cloudflared cannot reach Envoy,
# even with a valid-looking CF-Connecting-IP header.
#
# Requires a CNI that enforces NetworkPolicy (the Makefile's minikube target
# starts the lab with Calico). On a cluster without enforcement this test fails,
# which is the correct result: your policy would not be protecting anything.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

ORIGIN="${ORIGIN:-http://edge-envoy.envoy-gateway-system.svc.cluster.local}"

code=$(run_curl demo "" -H 'CF-Connecting-IP: 203.0.113.10' "$ORIGIN/")

# curl prints 000 when the connection times out or is refused.
if [[ "$code" == "000" ]]; then
  echo "PASS  pod outside cloudflared cannot reach Envoy (connection blocked)"
else
  echo "FAIL  pod outside cloudflared got '$code' (expected the connection to be blocked)"
  echo "      Is the NetworkPolicy applied, and does your CNI enforce it?"
  exit 1
fi
