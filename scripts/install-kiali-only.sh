#!/bin/bash

# Install only Kiali in istio-system (no duplicate monitoring tools)
# Kiali will be configured to use your existing Prometheus, Grafana, and Jaeger
# in the monitoring namespace

set -e

echo "========================================="
echo "Installing Kiali for Istio"
echo "========================================="
echo ""

# Check if Istio is installed
if ! kubectl get namespace istio-system &> /dev/null; then
    echo "Error: istio-system namespace not found"
    echo "Please install Istio first using ./install-istio.sh"
    exit 1
fi

echo "Found istio-system namespace"
echo ""

# Check if Kiali already exists
if kubectl get deployment kiali -n istio-system &> /dev/null; then
    echo "Kiali is already installed"
    read -p "Do you want to reinstall? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Skipping installation"
        exit 0
    fi
fi

# Find Istio samples directory
ISTIO_VERSION=1.24.0
ADDONS_DIR=""

if [ -d "istio-$ISTIO_VERSION/samples/addons" ]; then
    ADDONS_DIR="istio-$ISTIO_VERSION/samples/addons"
elif command -v istioctl &> /dev/null; then
    ISTIO_ROOT=$(dirname $(dirname $(which istioctl)))
    if [ -d "$ISTIO_ROOT/samples/addons" ]; then
        ADDONS_DIR="$ISTIO_ROOT/samples/addons"
    fi
fi

if [ -z "$ADDONS_DIR" ] || [ ! -d "$ADDONS_DIR" ]; then
    echo "Could not find Istio addons directory locally"
    echo "Downloading Kiali from GitHub..."

    KIALI_URL="https://raw.githubusercontent.com/istio/istio/release-1.24/samples/addons/kiali.yaml"
    kubectl apply -f "$KIALI_URL"
else
    echo "Found Istio addons directory: $ADDONS_DIR"
    echo "Installing Kiali..."
    kubectl apply -f "$ADDONS_DIR/kiali.yaml"
fi

echo ""
echo "Waiting for Kiali to be ready..."
kubectl wait --for=condition=available --timeout=180s deployment/kiali -n istio-system

echo ""
echo "Applying custom Kiali configuration to use existing monitoring stack..."
kubectl apply -f kubernetes/base/istio/kiali-custom-config.yaml

echo "Restarting Kiali to pick up configuration..."
kubectl rollout restart deployment/kiali -n istio-system
kubectl wait --for=condition=available --timeout=120s deployment/kiali -n istio-system

echo ""
echo "========================================="
echo "Installation Complete!"
echo "========================================="
echo ""

kubectl get deployment,service -n istio-system | grep kiali

echo ""
echo "========================================="
echo "Kiali Configuration"
echo "========================================="
echo ""
echo "Kiali is configured to use:"
echo "  ✓ Prometheus: http://prometheus.monitoring.svc.cluster.local:9090"
echo "  ✓ Grafana: http://grafana.monitoring.svc.cluster.local:3000"
echo "  ✓ Jaeger: http://jaeger-query.monitoring.svc.cluster.local:16686"
echo ""
echo "No duplicate monitoring tools in istio-system!"
echo ""

echo "========================================="
echo "Access Kiali"
echo "========================================="
echo ""
echo "kubectl port-forward -n istio-system svc/kiali 20001:20001"
echo "http://localhost:20001"
echo ""
