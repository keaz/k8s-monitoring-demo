#!/bin/bash

# Install Istio on Kubernetes cluster
# This script downloads and installs Istio with the demo profile
# and enables automatic sidecar injection for the services namespace

set -e

echo "========================================="
echo "Installing Istio Service Mesh"
echo "========================================="

# Check if istioctl is installed
if ! command -v istioctl &> /dev/null; then
    echo "istioctl not found. Installing Istio..."

    # Download Istio
    ISTIO_VERSION=1.24.0
    curl -L https://istio.io/downloadIstio | ISTIO_VERSION=$ISTIO_VERSION sh -

    # Add istioctl to PATH
    cd istio-$ISTIO_VERSION
    export PATH=$PWD/bin:$PATH
    cd ..

    echo "Istio downloaded. Please add istioctl to your PATH:"
    echo "export PATH=\$PWD/istio-$ISTIO_VERSION/bin:\$PATH"
else
    echo "istioctl already installed: $(istioctl version --short 2>/dev/null || echo 'version check failed')"
fi

# Install Istio with demo profile
echo ""
echo "Installing Istio with demo configuration profile..."
istioctl install --set profile=demo -y

# Wait for Istio to be ready
echo ""
echo "Waiting for Istio control plane to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/istiod -n istio-system

# Install Istio observability addons
echo ""
echo "========================================="
echo "Observability Addons"
echo "========================================="
echo ""
echo "You already have Prometheus, Grafana, and Jaeger in the 'monitoring' namespace."
echo ""
echo "Options:"
echo "  1) Install only Kiali (recommended - no duplicates)"
echo "  2) Install all addons (Kiali, Prometheus, Grafana, Jaeger - creates duplicates)"
echo "  3) Skip (install addons later)"
echo ""
read -p "Choose option (1/2/3): " -n 1 -r
echo ""

ADDONS_CHOICE=$REPLY

# Determine Istio samples directory
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

if [[ $ADDONS_CHOICE == "1" ]]; then
    echo "Installing Kiali only..."
    if [ -n "$ADDONS_DIR" ] && [ -d "$ADDONS_DIR" ]; then
        kubectl apply -f "$ADDONS_DIR/kiali.yaml"
    else
        echo "Downloading Kiali from GitHub..."
        kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.24/samples/addons/kiali.yaml
    fi
    echo "Waiting for Kiali to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/kiali -n istio-system || true
    echo ""
    echo "Note: Kiali will be configured to use your existing Prometheus, Grafana, and Jaeger"

elif [[ $ADDONS_CHOICE == "2" ]]; then
    echo "Installing all addons (this will create duplicates)..."
    if [ -n "$ADDONS_DIR" ] && [ -d "$ADDONS_DIR" ]; then
        kubectl apply -f "$ADDONS_DIR/prometheus.yaml"
        kubectl apply -f "$ADDONS_DIR/grafana.yaml"
        kubectl apply -f "$ADDONS_DIR/jaeger.yaml"
        kubectl apply -f "$ADDONS_DIR/kiali.yaml"
    else
        echo "Downloading addons from GitHub..."
        kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.24/samples/addons/prometheus.yaml
        kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.24/samples/addons/grafana.yaml
        kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.24/samples/addons/jaeger.yaml
        kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.24/samples/addons/kiali.yaml
    fi
    echo "Waiting for Kiali to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/kiali -n istio-system || true
    echo ""
    echo "Warning: You now have duplicate monitoring tools in istio-system"
    echo "Consider running ./scripts/cleanup-istio-duplicates.sh later"

else
    echo "Skipping addon installation"
    echo "You can install later with: ./scripts/install-kiali-only.sh"
fi

# Enable automatic sidecar injection for services namespace
echo ""
echo "Enabling automatic Istio sidecar injection for 'services' namespace..."
kubectl label namespace services istio-injection=enabled --overwrite

# Enable sidecar injection for monitoring namespace (optional, for Istio's own telemetry)
echo "Enabling automatic Istio sidecar injection for 'monitoring' namespace..."
kubectl label namespace monitoring istio-injection=enabled --overwrite

# Verify installation
echo ""
echo "========================================="
echo "Istio Installation Complete!"
echo "========================================="
echo ""
echo "Installed components:"
kubectl get pods -n istio-system

echo ""
echo "Namespaces with sidecar injection enabled:"
kubectl get namespace -L istio-injection

echo ""
echo "========================================="
echo "Next Steps:"
echo "========================================="
echo "1. Deploy or restart your services to inject Istio sidecars"
echo "2. Apply Istio Gateway and VirtualService configurations"
echo "3. Access Kiali dashboard: kubectl port-forward svc/kiali -n istio-system 20001:20001"
echo "4. Access Istio Prometheus: kubectl port-forward svc/prometheus -n istio-system 9090:9090"
echo "5. Access Istio Grafana: kubectl port-forward svc/grafana -n istio-system 3000:3000"
echo "6. Access Istio Jaeger: kubectl port-forward svc/tracing -n istio-system 16686:16686"
echo ""
