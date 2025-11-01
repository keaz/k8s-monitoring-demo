#!/bin/bash

# Install Linkerd Service Mesh WITHOUT embedded Prometheus
# This version uses your existing Prometheus in the monitoring namespace
# Saves resources by eliminating duplication

set -e

echo "========================================="
echo "Installing Linkerd (Using Existing Prometheus)"
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

# Install Linkerd Viz extension WITHOUT embedded Prometheus
echo "========================================="
echo "Installing Linkerd Viz (External Prometheus Mode)"
echo "========================================="
echo ""
echo "Linkerd Viz will use your existing Prometheus at:"
echo "  http://prometheus.monitoring.svc.cluster.local:9090"
echo ""
echo "This eliminates the duplicate Prometheus and saves resources!"
echo ""

# Install Viz WITHOUT Prometheus
linkerd viz install \
    --set prometheus.enabled=false \
    --set prometheusUrl=http://prometheus.monitoring.svc.cluster.local:9090 \
    | kubectl apply -f -

echo ""
echo "Waiting for Viz extension to be ready..."
linkerd viz check

if [ $? -ne 0 ]; then
    echo ""
    echo "Warning: Viz extension installation had issues"
    echo "You may need to configure Prometheus scraping for Linkerd metrics"
fi

echo ""
echo "✓ Linkerd Viz extension installed (using external Prometheus)"
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

# Configure Prometheus to scrape Linkerd metrics
echo "========================================="
echo "Configuring Prometheus to Scrape Linkerd"
echo "========================================="
echo ""

cat > /tmp/linkerd-prometheus-config.yaml << 'EOF'
# Add these scrape configs to your Prometheus configuration
# File: kubernetes/base/prometheus/prometheus-config.yaml

scrape_configs:
  # Linkerd control plane metrics
  - job_name: 'linkerd-controller'
    kubernetes_sd_configs:
    - role: pod
      namespaces:
        names:
        - linkerd
        - linkerd-viz
    relabel_configs:
    - source_labels:
      - __meta_kubernetes_pod_label_linkerd_io_control_plane_component
      - __meta_kubernetes_pod_label_linkerd_io_proxy_job
      action: keep
      regex: (.*);^$
    - source_labels: [__meta_kubernetes_pod_container_port_name]
      action: keep
      regex: admin-http
    - source_labels: [__meta_kubernetes_pod_container_name]
      action: replace
      target_label: component

  # Linkerd proxy metrics (data plane)
  - job_name: 'linkerd-proxy'
    kubernetes_sd_configs:
    - role: pod
    relabel_configs:
    - source_labels:
      - __meta_kubernetes_pod_container_name
      - __meta_kubernetes_pod_container_port_name
      - __meta_kubernetes_pod_label_linkerd_io_control_plane_ns
      action: keep
      regex: ^linkerd-proxy;linkerd-admin;linkerd$
    - source_labels: [__meta_kubernetes_namespace]
      action: replace
      target_label: namespace
    - source_labels: [__meta_kubernetes_pod_name]
      action: replace
      target_label: pod
    - source_labels: [__meta_kubernetes_pod_label_linkerd_io_proxy_job]
      action: replace
      target_label: k8s_job
    - action: labeldrop
      regex: __meta_kubernetes_pod_label_linkerd_io_proxy_job
    - action: labelmap
      regex: __meta_kubernetes_pod_label_linkerd_io_proxy_(.+)
    - action: labeldrop
      regex: __meta_kubernetes_pod_label_linkerd_io_proxy_(.+)
    - action: labelmap
      regex: __meta_kubernetes_pod_label_linkerd_io_(.+)
    - action: labelmap
      regex: __meta_kubernetes_pod_label_(.+)
      replacement: __tmp_pod_label_$1
    - action: labelmap
      regex: __tmp_pod_label_linkerd_io_(.+)
      replacement: __tmp_pod_label_$1
    - action: labeldrop
      regex: __tmp_pod_label_linkerd_io_(.+)
    - action: labelmap
      regex: __tmp_pod_label_(.+)
EOF

echo "Prometheus scrape configuration saved to: /tmp/linkerd-prometheus-config.yaml"
echo ""
echo "To enable Linkerd metrics in your existing Prometheus:"
echo "1. Add the scrape configs from /tmp/linkerd-prometheus-config.yaml"
echo "   to kubernetes/base/prometheus/prometheus-config.yaml"
echo "2. Apply the updated config:"
echo "   kubectl apply -f kubernetes/base/prometheus/prometheus-config.yaml"
echo "3. Restart Prometheus:"
echo "   kubectl rollout restart deployment/prometheus -n monitoring"
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

echo "Notice: No Prometheus pod in linkerd-viz namespace!"
echo "Linkerd is using your existing Prometheus in the monitoring namespace."
echo ""

echo "Namespaces with sidecar injection enabled:"
kubectl get namespace -o json | jq -r '.items[] | select(.metadata.annotations."linkerd.io/inject" == "enabled") | .metadata.name'

echo ""
echo "========================================="
echo "Resource Savings"
echo "========================================="
echo ""
echo "By using external Prometheus, you save approximately:"
echo "  - CPU: ~50-100m"
echo "  - Memory: ~150-200Mi"
echo "  - Storage: Prometheus data duplication"
echo ""

echo "========================================="
echo "Next Steps"
echo "========================================="
echo ""
echo "1. Configure Prometheus to scrape Linkerd metrics:"
echo "   See /tmp/linkerd-prometheus-config.yaml"
echo ""
echo "2. Restart your services to inject Linkerd sidecars:"
echo "   kubectl rollout restart deployment -n services"
echo ""
echo "3. Access Linkerd dashboard:"
echo "   linkerd viz dashboard"
echo ""
echo "4. Verify metrics are flowing:"
echo "   linkerd viz stat deployments -n services"
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
echo "# Check mTLS status"
echo "linkerd viz edges deployment -n services"
echo ""
