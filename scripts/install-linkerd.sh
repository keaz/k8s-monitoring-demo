#!/bin/bash

# Install Linkerd Service Mesh - Production Ready
# This script installs Linkerd control plane and Viz extension
# Linkerd is a lightweight, secure, and simple service mesh

set -e

echo "========================================="
echo "Installing Linkerd Service Mesh"
echo "========================================="
echo ""

# Check if linkerd CLI is installed
if ! command -v linkerd &> /dev/null; then
    echo "Linkerd CLI not found. Installing..."

    # Detect OS and architecture
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)

    case $ARCH in
        x86_64)
            ARCH="amd64"
            ;;
        aarch64|arm64)
            ARCH="arm64"
            ;;
        armv7l)
            ARCH="arm"
            ;;
    esac

    echo "Detected: $OS/$ARCH"
    echo ""

    # Install Linkerd CLI
    curl -fsL https://run.linkerd.io/install | sh

    # Add to PATH for this session
    export PATH=$HOME/.linkerd2/bin:$PATH

    echo ""
    echo "Linkerd CLI installed. Add to your PATH:"
    echo "export PATH=\$HOME/.linkerd2/bin:\$PATH"
    echo ""
else
    echo "Linkerd CLI already installed: $(linkerd version --client --short 2>/dev/null || echo 'version check failed')"
    echo ""
fi

# Install Gateway API CRDs (required by Linkerd 2.12+)
echo "Installing Gateway API CRDs..."
if ! kubectl get crd gateways.gateway.networking.k8s.io &>/dev/null; then
    kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml
    echo "✓ Gateway API CRDs installed"
else
    echo "✓ Gateway API CRDs already installed"
fi
echo ""

# Pre-installation checks
echo "Running pre-installation checks..."
linkerd check --pre

if [ $? -ne 0 ]; then
    echo ""
    echo "Pre-installation checks failed!"
    echo "Please fix the issues above before proceeding."
    exit 1
fi

echo ""
echo "✓ Pre-installation checks passed"
echo ""

# Ask for production or dev configuration
echo "========================================="
echo "Configuration Options"
echo "========================================="
echo ""
echo "Choose configuration:"
echo "  1) Production (HA mode, 3 replicas, resource limits)"
echo "  2) Development (single replica, minimal resources)"
echo ""
read -p "Choose option (1/2) [1]: " -n 1 -r
echo ""

CONFIG_CHOICE=${REPLY:-1}

# Install Linkerd CRDs
echo "Installing Linkerd CRDs..."
linkerd install --crds | kubectl apply -f -

echo ""
echo "Waiting for CRDs to be established..."
sleep 5

# Install Linkerd control plane
echo ""
echo "Installing Linkerd control plane..."

if [[ $CONFIG_CHOICE == "1" ]]; then
    echo "Using production configuration (HA mode)..."
    linkerd install \
        --ha \
        --identity-trust-anchors-file="" \
        --identity-issuance-lifetime=24h \
        --set proxyInit.runAsRoot=false \
        | kubectl apply -f -
else
    echo "Using development configuration..."
    linkerd install | kubectl apply -f -
fi

# Wait for Linkerd to be ready
echo ""
echo "Waiting for Linkerd control plane to be ready..."
linkerd check

if [ $? -ne 0 ]; then
    echo ""
    echo "Linkerd control plane installation failed!"
    exit 1
fi

echo ""
echo "✓ Linkerd control plane installed successfully"
echo ""

# Install Linkerd Viz extension
echo "========================================="
echo "Installing Linkerd Viz Extension"
echo "========================================="
echo ""
echo "Linkerd Viz provides:"
echo "  - Real-time service topology dashboard"
echo "  - Golden metrics (success rate, RPS, latency)"
echo "  - Live traffic tap"
echo "  - Grafana integration"
echo ""

linkerd viz install | kubectl apply -f -

echo ""
echo "Waiting for Viz extension to be ready..."
linkerd viz check

if [ $? -ne 0 ]; then
    echo ""
    echo "Warning: Viz extension installation had issues"
    echo "You can continue, but visualization may not work properly"
fi

echo ""
echo "✓ Linkerd Viz extension installed"
echo ""

# Enable automatic injection for services namespace
echo "========================================="
echo "Enabling Sidecar Injection"
echo "========================================="
echo ""

echo "Enabling automatic Linkerd sidecar injection for 'services' namespace..."
kubectl annotate namespace services linkerd.io/inject=enabled --overwrite

echo "Enabling automatic Linkerd sidecar injection for 'monitoring' namespace..."
kubectl annotate namespace monitoring linkerd.io/inject=enabled --overwrite

echo ""
echo "✓ Sidecar injection enabled"
echo ""

# Verify installation
echo "========================================="
echo "Installation Complete!"
echo "========================================="
echo ""

echo "Linkerd components:"
kubectl get pods -n linkerd
echo ""
kubectl get pods -n linkerd-viz

echo ""
echo "Namespaces with sidecar injection enabled:"
kubectl get namespace -o json | jq -r '.items[] | select(.metadata.annotations."linkerd.io/inject" == "enabled") | .metadata.name'

echo ""
echo "========================================="
echo "Linkerd Resource Usage"
echo "========================================="
echo ""

# Show resource usage
kubectl top pods -n linkerd 2>/dev/null || echo "Install metrics-server to see resource usage"

echo ""
echo "========================================="
echo "Next Steps"
echo "========================================="
echo ""
echo "1. Restart your services to inject Linkerd sidecars:"
echo "   kubectl rollout restart deployment -n services"
echo ""
echo "2. Access Linkerd dashboard:"
echo "   linkerd viz dashboard"
echo "   or"
echo "   kubectl port-forward -n linkerd-viz svc/web 8084:8084"
echo "   http://localhost:8084"
echo ""
echo "3. View live traffic:"
echo "   linkerd viz tap deployment/service-a -n services"
echo ""
echo "4. Check service mesh status:"
echo "   linkerd viz stat deployments -n services"
echo ""
echo "5. Apply traffic management policies:"
echo "   kubectl apply -f kubernetes/linkerd/service-profiles.yaml"
echo ""
echo "========================================="
echo "Useful Commands"
echo "========================================="
echo ""
echo "# Check overall status"
echo "linkerd check"
echo ""
echo "# View dashboard"
echo "linkerd viz dashboard"
echo ""
echo "# See golden metrics"
echo "linkerd viz stat deploy -n services"
echo ""
echo "# Live traffic tap"
echo "linkerd viz tap deploy/service-a -n services"
echo ""
echo "# View routes (after ServiceProfile applied)"
echo "linkerd viz routes deploy/service-a -n services"
echo ""
echo "# Check mTLS status"
echo "linkerd viz edges deployment -n services"
echo ""

echo "Documentation:"
echo "  - LINKERD_SETUP.md - Detailed setup guide"
echo "  - LINKERD_OBSERVABILITY.md - Observability features"
echo "  - LINKERD_TRAFFIC_MANAGEMENT.md - Traffic management"
echo "  - LINKERD_QUICK_START.md - Quick start guide"
echo ""
