#!/usr/bin/env bash
# Shared helper for the test scripts.

# run_curl <namespace> <pod-labels|""> <curl args...>
# Runs a throwaway curl pod, waits for it to finish, prints the HTTP status code
# (curl prints 000 when the connection fails or is blocked), then deletes the pod.
#
# It deliberately avoids `kubectl run -i --rm`: attaching to a very short-lived
# pod on a fresh cluster races with the image pull and can return nothing.
run_curl() {
  local ns="$1" labels="$2"
  shift 2
  local pod="curl-${RANDOM}${RANDOM}"
  local label_args=()
  [[ -n "$labels" ]] && label_args=(--labels="$labels")

  kubectl -n "$ns" run "$pod" --restart=Never "${label_args[@]}" \
    --image=curlimages/curl:8.11.1 --command -- \
    curl -s -o /dev/null -w '%{http_code}' --max-time 8 "$@" >/dev/null

  local phase=""
  for _ in $(seq 1 90); do
    phase=$(kubectl -n "$ns" get pod "$pod" -o jsonpath='{.status.phase}' 2>/dev/null || true)
    [[ "$phase" == "Succeeded" || "$phase" == "Failed" ]] && break
    sleep 2
  done

  kubectl -n "$ns" logs "$pod" 2>/dev/null || true
  kubectl -n "$ns" delete pod "$pod" --wait=false >/dev/null 2>&1 || true
}
