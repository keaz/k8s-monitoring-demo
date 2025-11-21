#!/bin/bash

set -euo pipefail

usage() {
    echo "Usage: $0 <workload-namespace>"
    echo "Example: $0 services"
    exit 1
}

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "ERROR: $1 is required but not found on PATH"
        exit 1
    fi
}

if [ $# -ne 1 ]; then
    usage
fi

WORKLOAD_NS="$1"

require_cmd kubectl
require_cmd jq

echo "Ensuring namespace '$WORKLOAD_NS' is labeled for sidecar injection..."
kubectl label namespace "$WORKLOAD_NS" istio-injection=enabled --overwrite

echo "Identifying pods without the Istio sidecar in namespace '$WORKLOAD_NS'..."
mapfile -t PODS_WITHOUT_SIDECAR < <(
    kubectl get pods -n "$WORKLOAD_NS" -o json \
        | jq -r '.items[] | select((.spec.containers // []) | map(.name) | index("istio-proxy") | not) | .metadata.name'
)

if [ ${#PODS_WITHOUT_SIDECAR[@]} -eq 0 ]; then
    echo "All pods in '$WORKLOAD_NS' already have the Istio sidecar."
    exit 0
fi

echo "Deleting pods without sidecars so they are recreated with injection enabled:"
for pod in "${PODS_WITHOUT_SIDECAR[@]}"; do
    echo " - $pod"
    kubectl delete pod "$pod" -n "$WORKLOAD_NS" --ignore-not-found
done

echo "Waiting for workloads to become Ready after pod restarts..."
kubectl wait --for=condition=available deployment -n "$WORKLOAD_NS" --all --timeout=120s || true
kubectl wait --for=condition=ready statefulset -n "$WORKLOAD_NS" --all --timeout=120s || true

echo "Done. Check Kiali to confirm sidecars are present on the recreated pods."
