#!/bin/bash

# Complete deployment script with Linkerd service mesh
# This script deploys the monitoring stack, services, and Linkerd service mesh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "========================================="
echo "K8s Monitoring Demo with Linkerd"
echo "Complete Deployment Script"
echo "========================================="
echo ""

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
echo "Checking prerequisites..."
if ! command_exists kubectl; then
    echo "Error: kubectl is not installed"
    exit 1
fi

if ! command_exists docker; then
    echo "Error: docker is not installed"
    exit 1
fi

echo "✓ Prerequisites check passed"
echo ""

# Clean up any conflicting service mesh configurations
echo "========================================="
echo "Cleaning up conflicting configurations"
echo "========================================="
echo ""

# Remove Istio injection labels
echo "Removing Istio injection labels..."
kubectl label namespace services istio-injection- 2>/dev/null || true
kubectl label namespace monitoring istio-injection- 2>/dev/null || true

# Remove Istio webhooks that might block pod creation
echo "Removing Istio webhooks..."
kubectl delete mutatingwebhookconfiguration istio-revision-tag-default 2>/dev/null || true
kubectl delete mutatingwebhookconfiguration istio-sidecar-injector 2>/dev/null || true
kubectl delete validatingwebhookconfiguration istio-validator-istio-system 2>/dev/null || true

echo "✓ Cleanup complete"
echo ""

# Ask user if they want to install Linkerd
read -p "Do you want to install Linkerd service mesh? (y/n) " -n 1 -r
echo
INSTALL_LINKERD=$REPLY

# Step 1: Build and deploy services
echo "========================================="
echo "Step 1: Building and deploying services"
echo "========================================="
echo ""

cd "$PROJECT_ROOT"

# Build services
echo "Building service images..."
if [ -f "./scripts/build-and-deploy.sh" ]; then
    ./scripts/build-and-deploy.sh
else
    echo "Running manual build..."

    # Build service-a
    cd services/java/service-a
    mvn clean package -DskipTests
    docker build -t service-a:latest .

    # Build service-b
    cd ../service-b
    mvn clean package -DskipTests
    docker build -t service-b:latest .

    # Build service-c
    cd ../service-c
    mvn clean package -DskipTests
    docker build -t service-c:latest .

    cd "$PROJECT_ROOT"

    # Load images to kind (if using kind)
    if command_exists kind; then
        echo "Loading images to kind cluster..."
        kind load docker-image service-a:latest service-b:latest service-c:latest
    fi

    # Deploy base monitoring and services
    kubectl apply -k kubernetes/base
fi

echo ""
echo "Waiting for services to be ready..."
kubectl wait --for=condition=ready pod -l app=service-a -n services --timeout=300s || true
kubectl wait --for=condition=ready pod -l app=service-b -n services --timeout=300s || true
kubectl wait --for=condition=ready pod -l app=service-c -n services --timeout=300s || true

echo "✓ Services deployed"
echo ""

# Step 2: Install Linkerd (if requested)
if [[ $INSTALL_LINKERD =~ ^[Yy]$ ]]; then
    echo "========================================="
    echo "Step 2: Installing Linkerd Service Mesh"
    echo "========================================="
    echo ""

    # Ask user about Prometheus configuration
    echo "Prometheus Configuration Options:"
    echo "  1) Embedded Prometheus (Default - separate Prometheus for Linkerd)"
    echo "  2) External Prometheus (Recommended - use existing Prometheus)"
    echo ""
    echo "External Prometheus saves ~70m CPU and ~150Mi RAM by reusing your"
    echo "existing Prometheus in the monitoring namespace."
    echo ""
    read -p "Choose option (1/2) [2]: " -n 1 -r
    echo
    PROMETHEUS_OPTION=${REPLY:-2}
    echo ""

    if [[ $PROMETHEUS_OPTION == "2" ]]; then
        echo "Installing Linkerd with external Prometheus integration..."
        if [ -f "$SCRIPT_DIR/install-linkerd-no-prometheus.sh" ]; then
            "$SCRIPT_DIR/install-linkerd-no-prometheus.sh"
        else
            echo "Error: install-linkerd-no-prometheus.sh not found"
            exit 1
        fi

        # Apply updated Prometheus config and restart Prometheus
        echo ""
        echo "Applying Prometheus configuration for Linkerd metrics..."
        kubectl apply -f "$PROJECT_ROOT/kubernetes/base/prometheus/prometheus-config.yaml"

        echo "Restarting Prometheus to apply new configuration..."
        kubectl rollout restart deployment/prometheus -n monitoring
        kubectl wait --for=condition=available deployment/prometheus -n monitoring --timeout=120s

        echo "✓ Prometheus configured to scrape Linkerd metrics"
        echo ""
    else
        echo "Installing Linkerd with embedded Prometheus..."
        if [ -f "$SCRIPT_DIR/install-linkerd.sh" ]; then
            "$SCRIPT_DIR/install-linkerd.sh"
        else
            echo "Error: install-linkerd.sh not found"
            exit 1
        fi
    fi

    echo ""
    echo "Waiting for Linkerd control plane to be ready..."

    # Ensure linkerd CLI is in PATH
    export PATH=$HOME/.linkerd2/bin:$PATH

    linkerd check

    echo "✓ Linkerd installed"
    echo ""

    # Step 3: Apply Linkerd configurations
    echo "========================================="
    echo "Step 3: Applying Linkerd Configurations"
    echo "========================================="
    echo ""

    echo "Applying Linkerd ServiceProfiles..."
    # Use simplified ServiceProfiles compatible with latest Linkerd
    if [ -f "$PROJECT_ROOT/kubernetes/linkerd/service-profiles-simple.yaml" ]; then
        kubectl apply -f "$PROJECT_ROOT/kubernetes/linkerd/service-profiles-simple.yaml"
    elif [ -f "$PROJECT_ROOT/kubernetes/linkerd/service-profiles.yaml" ]; then
        # Try the original file, but it might fail with newer Linkerd versions
        kubectl apply -f "$PROJECT_ROOT/kubernetes/linkerd/service-profiles.yaml" || echo "Warning: ServiceProfiles may be incompatible with this Linkerd version"
    else
        echo "Note: ServiceProfiles not found, skipping..."
    fi

    echo "Applying Linkerd authorization policies..."
    if [ -f "$PROJECT_ROOT/kubernetes/linkerd/authorization-policy.yaml" ]; then
        kubectl apply -f "$PROJECT_ROOT/kubernetes/linkerd/authorization-policy.yaml"
    else
        echo "Note: Authorization policies not found, skipping..."
    fi

    echo "✓ Linkerd configurations applied"
    echo ""

    # Step 4: Restart services to inject sidecars
    echo "========================================="
    echo "Step 4: Restarting Services for Sidecar Injection"
    echo "========================================="
    echo ""

    echo "Restarting service deployments..."
    kubectl rollout restart deployment/service-a -n services
    kubectl rollout restart deployment/service-b -n services
    kubectl rollout restart deployment/service-c -n services

    echo "Waiting for services with sidecars to be ready..."
    kubectl wait --for=condition=ready pod -l app=service-a -n services --timeout=300s
    kubectl wait --for=condition=ready pod -l app=service-b -n services --timeout=300s
    kubectl wait --for=condition=ready pod -l app=service-c -n services --timeout=300s

    echo "✓ Services restarted with Linkerd sidecars"
    echo ""
fi

# Step 5: Display deployment status
echo "========================================="
echo "Deployment Complete!"
echo "========================================="
echo ""

echo "Namespaces:"
kubectl get namespaces | grep -E "(services|monitoring|linkerd)"
echo ""

echo "Services (services namespace):"
kubectl get pods -n services
echo ""

echo "Monitoring Stack (monitoring namespace):"
kubectl get pods -n monitoring
echo ""

if [[ $INSTALL_LINKERD =~ ^[Yy]$ ]]; then
    # Ensure linkerd CLI is in PATH
    export PATH=$HOME/.linkerd2/bin:$PATH

    echo "Linkerd Control Plane (linkerd namespace):"
    kubectl get pods -n linkerd
    echo ""

    echo "Linkerd Viz (linkerd-viz namespace):"
    kubectl get pods -n linkerd-viz
    echo ""

    echo "Linkerd Injection Status:"
    kubectl get namespace -o json | jq -r '.items[] | select(.metadata.annotations."linkerd.io/inject" == "enabled") | .metadata.name' 2>/dev/null || echo "  services"
    echo ""

    # Verify sidecars
    echo "Verifying sidecar injection (pods should have 2/2 containers):"
    kubectl get pods -n services -o wide
    echo ""

    # Check mesh status
    echo "Linkerd Mesh Status:"
    linkerd viz stat deployments -n services 2>/dev/null || echo "  Run: export PATH=\$HOME/.linkerd2/bin:\$PATH && linkerd viz stat deployments -n services"
    echo ""
fi

# Display access information
echo "========================================="
echo "Access Information"
echo "========================================="
echo ""

echo "Monitoring Tools:"
echo "----------------"
echo "Prometheus:  kubectl port-forward -n monitoring svc/prometheus 9090:9090"
echo "             http://localhost:9090"
echo ""
echo "Grafana:     kubectl port-forward -n monitoring svc/grafana 3000:3000"
echo "             http://localhost:3000 (admin/admin)"
echo ""
echo "Jaeger:      kubectl port-forward -n monitoring svc/jaeger-query 16686:16686"
echo "             http://localhost:16686"
echo ""

if [[ $INSTALL_LINKERD =~ ^[Yy]$ ]]; then
    echo "Linkerd Tools:"
    echo "-------------"
    echo "Dashboard:   linkerd viz dashboard"
    echo "             or"
    echo "             kubectl port-forward -n linkerd-viz svc/web 8084:8084"
    echo "             http://localhost:8084"
    echo ""
    echo "Live Tap:    linkerd viz tap deployment/service-a -n services"
    echo ""
    echo "Metrics:     linkerd viz stat deployments -n services"
    echo ""
    echo "Routes:      linkerd viz routes deployment/service-a -n services"
    echo ""
    echo "Edges:       linkerd viz edges deployment -n services"
    echo ""
fi

echo "========================================="
echo "Resource Usage Summary"
echo "========================================="
echo ""

if command_exists linkerd && [[ $INSTALL_LINKERD =~ ^[Yy]$ ]]; then
    echo "Linkerd Control Plane:"
    kubectl top pods -n linkerd 2>/dev/null || echo "Install metrics-server to see resource usage"
    echo ""

    echo "Service Sidecars:"
    kubectl top pods -n services 2>/dev/null || echo "Install metrics-server to see resource usage"
    echo ""
fi

echo "========================================="
echo "Next Steps"
echo "========================================="
echo ""

if [[ $INSTALL_LINKERD =~ ^[Yy]$ ]]; then
    echo "1. View service mesh in Linkerd dashboard:"
    echo "   linkerd viz dashboard"
    echo ""
    echo "2. Generate traffic to see the mesh in action:"
    echo "   # From inside a pod"
    echo "   kubectl exec -n services deploy/service-a -- curl http://service-b.services.svc.cluster.local:8081/api/hello"
    echo ""
    echo "3. Watch live traffic:"
    echo "   linkerd viz tap deployment/service-a -n services"
    echo ""
    echo "4. Explore Linkerd features:"
    echo "   - Traffic Management: See LINKERD_TRAFFIC_MANAGEMENT.md"
    echo "   - Observability: See LINKERD_OBSERVABILITY.md"
    echo "   - Service Profiles: Apply kubernetes/linkerd/service-profiles.yaml"
    echo ""
    echo "5. Try traffic management examples:"
    echo "   kubectl apply -f kubernetes/linkerd/traffic-split.yaml"
else
    echo "1. To install Linkerd later, run: ./scripts/install-linkerd.sh"
    echo "2. Generate traffic: kubectl exec -n services deploy/service-a -- curl http://service-b:8081"
    echo "3. View metrics in Grafana: kubectl port-forward -n monitoring svc/grafana 3000:3000"
fi

echo ""
echo "Documentation:"
echo "  - LINKERD_SETUP.md - Complete Linkerd setup guide"
echo "  - LINKERD_TRAFFIC_MANAGEMENT.md - Traffic management examples"
echo "  - LINKERD_OBSERVABILITY.md - Observability and monitoring guide"
echo "  - LINKERD_VS_ISTIO.md - Comparison between Linkerd and Istio"
echo "  - LINKERD_QUICK_START.md - Quick start guide"
echo ""
echo "========================================="
