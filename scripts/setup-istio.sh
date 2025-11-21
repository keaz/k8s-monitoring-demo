#!/bin/bash

set -euo pipefail

# Pin to a Kubernetes 1.27-compatible Istio release by default. Override with
# ISTIO_VERSION env var if you need a different supported version.
ISTIO_VERSION="${ISTIO_VERSION:-1.23.3}"
ISTIO_DOWNLOAD_URL="https://istio.io/downloadIstio"
PROMETHEUS_URL="http://prometheus.monitoring.svc.cluster.local:9090"

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

install_helm() {
    if command -v helm >/dev/null 2>&1; then
        return
    fi

    echo "Helm not found, installing..."
    local tmpdir
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"' RETURN

    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 -o "$tmpdir/get-helm-3"
    chmod +x "$tmpdir/get-helm-3"
    "$tmpdir/get-helm-3"
 }

find_local_istioctl() {
    # Prefer a versioned istioctl that matches ISTIO_VERSION, then fall back to any on PATH.
    local versioned_bin="istio-${ISTIO_VERSION}/bin/istioctl"
    if [ -x "$versioned_bin" ]; then
        echo "$versioned_bin"
        return
    fi

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

download_istio() {
    echo "Downloading Istio ${ISTIO_VERSION}..."
    ISTIO_VERSION="$ISTIO_VERSION" curl -sL "$ISTIO_DOWNLOAD_URL" | sh -
}

if [ $# -ne 1 ]; then
    usage
fi

WORKLOAD_NS="$1"

require_cmd kubectl
require_cmd curl
require_cmd tar
install_helm

ISTIOCTL_PATH="$(find_local_istioctl)"

if [ -z "$ISTIOCTL_PATH" ]; then
    download_istio
    ISTIOCTL_PATH="$(find_local_istioctl)"
fi

if [ -z "$ISTIOCTL_PATH" ]; then
    echo "ERROR: istioctl could not be located after download"
    exit 1
fi

export PATH="$(dirname "$ISTIOCTL_PATH"):$PATH"
ISTIOCTL_BIN="$(basename "$ISTIOCTL_PATH")"

echo "Installing Istio with tracing enabled (using existing Prometheus)..."
"$ISTIOCTL_BIN" install \
    --set profile=default \
    --set meshConfig.enableTracing=true \
    -y

echo "Labeling namespace '$WORKLOAD_NS' for sidecar injection..."
kubectl label namespace "$WORKLOAD_NS" istio-injection=enabled --overwrite

echo "Installing Kiali (using existing monitoring Prometheus at $PROMETHEUS_URL)..."
helm repo add kiali https://kiali.org/helm-charts >/dev/null 2>&1
helm repo update >/dev/null 2>&1
helm upgrade --install kiali-server kiali/kiali-server \
    --namespace istio-system \
    --create-namespace \
    --set external_services.prometheus.url="$PROMETHEUS_URL" \
    --set auth.strategy=anonymous

echo "Istio and Kiali installation complete."
