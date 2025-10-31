#!/bin/bash

# Complete deployment script with Istio service mesh
# This script deploys the monitoring stack, services, and Istio service mesh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "========================================="
echo "K8s Monitoring Demo with Istio"
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

# Ask user if they want to install Istio
read -p "Do you want to install Istio service mesh? (y/n) " -n 1 -r
echo
INSTALL_ISTIO=$REPLY

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

# Step 2: Install Istio (if requested)
if [[ $INSTALL_ISTIO =~ ^[Yy]$ ]]; then
    echo "========================================="
    echo "Step 2: Installing Istio Service Mesh"
    echo "========================================="
    echo ""

    if [ -f "$SCRIPT_DIR/install-istio.sh" ]; then
        "$SCRIPT_DIR/install-istio.sh"
    else
        echo "Error: install-istio.sh not found"
        exit 1
    fi

    echo ""
    echo "Waiting for Istio control plane to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/istiod -n istio-system

    echo "✓ Istio installed"
    echo ""

    # Step 3: Apply Istio configurations
    echo "========================================="
    echo "Step 3: Applying Istio Configurations"
    echo "========================================="
    echo ""

    echo "Applying Istio gateway and virtual services..."
    kubectl apply -f "$PROJECT_ROOT/kubernetes/base/istio/istio-gateway.yaml"

    echo "Applying destination rules..."
    kubectl apply -f "$PROJECT_ROOT/kubernetes/base/istio/destination-rules.yaml"

    echo "Applying telemetry integration..."
    kubectl apply -f "$PROJECT_ROOT/kubernetes/base/istio/telemetry-integration.yaml"

    echo "Applying Kiali custom configuration..."
    kubectl apply -f "$PROJECT_ROOT/kubernetes/base/istio/kiali-custom-config.yaml"

    echo "Checking if Kiali is deployed..."
    if kubectl get deployment kiali -n istio-system &> /dev/null; then
        echo "Restarting Kiali to pick up custom config..."
        kubectl rollout restart deployment/kiali -n istio-system
        kubectl wait --for=condition=available --timeout=120s deployment/kiali -n istio-system || echo "Warning: Kiali restart timeout"
    else
        echo "Note: Kiali deployment not found. It will be created by install-istio.sh"
        echo "The custom configuration will be picked up on next Kiali restart."
    fi

    echo "✓ Istio configurations applied"
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

    echo "✓ Services restarted with Istio sidecars"
    echo ""
fi

# Step 5: Display deployment status
echo "========================================="
echo "Deployment Complete!"
echo "========================================="
echo ""

echo "Namespaces:"
kubectl get namespaces | grep -E "(services|monitoring|istio-system)"
echo ""

echo "Services (services namespace):"
kubectl get pods -n services
echo ""

echo "Monitoring Stack (monitoring namespace):"
kubectl get pods -n monitoring
echo ""

if [[ $INSTALL_ISTIO =~ ^[Yy]$ ]]; then
    echo "Istio Control Plane (istio-system namespace):"
    kubectl get pods -n istio-system
    echo ""

    echo "Istio Sidecar Injection Status:"
    kubectl get namespace -L istio-injection
    echo ""

    # Verify sidecars
    echo "Verifying sidecar injection (pods should have 2/2 containers):"
    kubectl get pods -n services -o wide
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

if [[ $INSTALL_ISTIO =~ ^[Yy]$ ]]; then
    echo "Istio Tools:"
    echo "------------"
    echo "Kiali:       kubectl port-forward -n istio-system svc/kiali 20001:20001"
    echo "             http://localhost:20001"
    echo ""
    echo "Istio Gateway:"
    INGRESS_HOST=$(kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
    if [ -z "$INGRESS_HOST" ]; then
        INGRESS_HOST=$(kubectl get po -l istio=ingressgateway -n istio-system -o jsonpath='{.items[0].status.hostIP}' 2>/dev/null)
        INGRESS_PORT=$(kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}' 2>/dev/null)
        echo "Gateway URL: http://$INGRESS_HOST:$INGRESS_PORT"
    else
        echo "Gateway URL: http://$INGRESS_HOST"
    fi
    echo ""

    echo "Test service:"
    echo "  curl http://$INGRESS_HOST${INGRESS_PORT:+:$INGRESS_PORT}/api/hello"
    echo ""
fi

echo "========================================="
echo "Next Steps"
echo "========================================="
echo ""

if [[ $INSTALL_ISTIO =~ ^[Yy]$ ]]; then
    echo "1. View service mesh in Kiali: kubectl port-forward -n istio-system svc/kiali 20001:20001"
    echo "2. Generate traffic to see the mesh in action:"
    echo "   for i in {1..100}; do curl http://GATEWAY_URL/api/hello; sleep 0.5; done"
    echo ""
    echo "3. Explore Istio features:"
    echo "   - Traffic Management: See ISTIO_TRAFFIC_MANAGEMENT.md"
    echo "   - Observability: See ISTIO_OBSERVABILITY.md"
    echo "   - Security Policies: Apply kubernetes/base/istio/security-policies.yaml"
    echo ""
    echo "4. Try traffic management examples:"
    echo "   kubectl apply -f kubernetes/base/istio/traffic-management-examples.yaml"
else
    echo "1. To install Istio later, run: ./scripts/install-istio.sh"
    echo "2. Generate traffic: ./scripts/generate-traffic.sh"
    echo "3. View metrics in Grafana: kubectl port-forward -n monitoring svc/grafana 3000:3000"
fi

echo ""
echo "Documentation:"
echo "  - ISTIO_SETUP.md - Complete Istio setup guide"
echo "  - ISTIO_TRAFFIC_MANAGEMENT.md - Traffic management examples"
echo "  - ISTIO_OBSERVABILITY.md - Observability and monitoring guide"
echo ""
echo "========================================="
