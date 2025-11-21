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

find_local_istioctl() {
    if command -v istioctl >/dev/null 2>&1; then
        echo "$(command -v istioctl)"
        return
    fi

    local candidate
    candidate="$(ls -d istio-*/bin/istioctl 2>/dev/null | sort -V | tail -1 || true)"
    if [ -n "${candidate:-}" ] && [ -x "$candidate" ]; then
        echo "$candidate"
        return
    fi

    echo ""
}

if [ $# -ne 1 ]; then
    usage
fi

WORKLOAD_NS="$1"

require_cmd kubectl

ISTIOCTL_PATH="$(find_local_istioctl)"
if [ -z "$ISTIOCTL_PATH" ]; then
    echo "ERROR: istioctl is required to uninstall Istio. Please install it or re-run setup."
    exit 1
fi

export PATH="$(dirname "$ISTIOCTL_PATH"):$PATH"
ISTIOCTL_BIN="$(basename "$ISTIOCTL_PATH")"

echo "Removing Kiali..."
if command -v helm >/dev/null 2>&1; then
    helm uninstall kiali-server -n istio-system --wait --ignore-not-found || true
else
    echo "WARN: helm not found, skipping Kiali uninstall"
fi

echo "Removing Istio control plane..."
"$ISTIOCTL_BIN" uninstall --purge -y || true

echo "Removing istio-system namespace (if empty)..."
kubectl delete namespace istio-system --ignore-not-found

echo "Removing sidecar injection label from '$WORKLOAD_NS'..."
kubectl label namespace "$WORKLOAD_NS" istio-injection- --overwrite || true

echo "Istio and Kiali teardown complete."
