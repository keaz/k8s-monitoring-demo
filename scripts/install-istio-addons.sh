#!/bin/bash

# Install Istio observability addons (Kiali, Prometheus, Grafana, Jaeger)
# Use this script if you already have Istio installed and just need the addons

set -e

echo "========================================="
echo "Installing Istio Observability Addons"
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
    echo "Downloading addons from GitHub..."

    ADDONS_BASE_URL="https://raw.githubusercontent.com/istio/istio/release-1.24/samples/addons"

    echo "Installing Prometheus..."
    kubectl apply -f "$ADDONS_BASE_URL/prometheus.yaml"

    echo "Installing Grafana..."
    kubectl apply -f "$ADDONS_BASE_URL/grafana.yaml"

    echo "Installing Jaeger..."
    kubectl apply -f "$ADDONS_BASE_URL/jaeger.yaml"

    echo "Installing Kiali..."
    kubectl apply -f "$ADDONS_BASE_URL/kiali.yaml"
else
    echo "Found Istio addons directory: $ADDONS_DIR"
    echo ""

    echo "Installing Prometheus..."
    kubectl apply -f "$ADDONS_DIR/prometheus.yaml"

    echo "Installing Grafana..."
    kubectl apply -f "$ADDONS_DIR/grafana.yaml"

    echo "Installing Jaeger..."
    kubectl apply -f "$ADDONS_DIR/jaeger.yaml"

    echo "Installing Kiali..."
    kubectl apply -f "$ADDONS_DIR/kiali.yaml"
fi

echo ""
echo "Waiting for deployments to be ready..."
echo "This may take a few minutes..."

# Wait for each addon (with timeout)
echo -n "Waiting for Prometheus..."
kubectl wait --for=condition=available --timeout=180s deployment/prometheus -n istio-system 2>/dev/null && echo " ✓" || echo " (timeout)"

echo -n "Waiting for Grafana..."
kubectl wait --for=condition=available --timeout=180s deployment/grafana -n istio-system 2>/dev/null && echo " ✓" || echo " (timeout)"

echo -n "Waiting for Jaeger..."
kubectl wait --for=condition=available --timeout=180s deployment/jaeger -n istio-system 2>/dev/null && echo " ✓" || echo " (timeout)"

echo -n "Waiting for Kiali..."
kubectl wait --for=condition=available --timeout=180s deployment/kiali -n istio-system 2>/dev/null && echo " ✓" || echo " (timeout)"

echo ""
echo "========================================="
echo "Installation Complete!"
echo "========================================="
echo ""

echo "Installed addons:"
kubectl get pods -n istio-system | grep -E "prometheus|grafana|jaeger|kiali"

echo ""
echo "========================================="
echo "Access the Dashboards"
echo "========================================="
echo ""
echo "Kiali (Service Mesh Visualization):"
echo "  kubectl port-forward -n istio-system svc/kiali 20001:20001"
echo "  http://localhost:20001"
echo ""
echo "Prometheus (Istio Metrics):"
echo "  kubectl port-forward -n istio-system svc/prometheus 9090:9090"
echo "  http://localhost:9090"
echo ""
echo "Grafana (Istio Dashboards):"
echo "  kubectl port-forward -n istio-system svc/grafana 3000:3000"
echo "  http://localhost:3000"
echo ""
echo "Jaeger (Distributed Tracing):"
echo "  kubectl port-forward -n istio-system svc/tracing 16686:16686"
echo "  http://localhost:16686"
echo ""

echo "Next Steps:"
echo "1. Apply custom Kiali configuration:"
echo "   kubectl apply -f kubernetes/base/istio/kiali-custom-config.yaml"
echo "   kubectl rollout restart deployment/kiali -n istio-system"
echo ""
echo "2. Generate traffic to see the service mesh in action"
echo "3. View the service graph in Kiali"
echo ""
