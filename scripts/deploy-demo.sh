#!/bin/bash

# Complete Demo Deployment Script
# Builds and deploys all mock services for monitoring demo

set -e

export PATH="$HOME/.local/bin:$PATH"

echo "=== K8s Monitoring Demo - Complete Setup ==="
echo

# Check prerequisites
echo "Checking prerequisites..."
command -v docker >/dev/null 2>&1 || { echo "ERROR: docker not found"; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "ERROR: kubectl not found"; exit 1; }
command -v kind >/dev/null 2>&1 || { echo "ERROR: kind not found"; exit 1; }

echo "✓ All prerequisites found"
echo

# Check if cluster exists
if ! kubectl cluster-info --context kind-monitoring-demo >/dev/null 2>&1; then
    echo "ERROR: Cluster 'monitoring-demo' not found"
    echo "Please run the cluster setup first"
    exit 1
fi

echo "✓ Cluster is running"
echo

# Build mock service image
echo "Step 1: Building mock service Docker image..."
cd services/mock-services

if docker build -t mock-service:latest . ; then
    echo "✓ Docker image built successfully"
else
    echo "ERROR: Failed to build Docker image"
    exit 1
fi

echo

# Load image into kind cluster
echo "Step 2: Loading image into kind cluster..."
if kind load docker-image mock-service:latest --name monitoring-demo; then
    echo "✓ Image loaded into cluster"
else
    echo "ERROR: Failed to load image into cluster"
    exit 1
fi

cd ../..
echo

# Build Java services
echo "Step 3: Building Java service Docker images..."
java_services=("service-a" "service-b" "service-c")

for service in "${java_services[@]}"; do
    echo "Building $service..."
    cd services/java/$service
    if docker build -t $service:latest . ; then
        echo "✓ $service image built successfully"
    else
        echo "ERROR: Failed to build $service image"
        exit 1
    fi
    cd ../../..
done

echo

# Load Java service images into kind cluster
echo "Step 4: Loading Java service images into kind cluster..."
for service in "${java_services[@]}"; do
    echo "Loading $service..."
    if kind load docker-image $service:latest --name monitoring-demo; then
        echo "✓ $service image loaded into cluster"
    else
        echo "ERROR: Failed to load $service image into cluster"
        exit 1
    fi
done

echo

# Deploy services
echo "Step 5: Deploying mock services..."
if kubectl apply -f kubernetes/base/services/mock-services.yaml; then
    echo "✓ Mock services deployed"
else
    echo "ERROR: Failed to deploy mock services"
    exit 1
fi

echo

# Deploy Java services
echo "Step 6: Deploying Java services..."
for service in "${java_services[@]}"; do
    echo "Deploying $service..."
    if kubectl apply -f kubernetes/base/services/$service.yaml; then
        echo "✓ $service deployed"
    else
        echo "ERROR: Failed to deploy $service"
        exit 1
    fi
done

echo

# Wait for deployments to be ready
echo "Step 7: Waiting for services to be ready..."
echo "This may take a minute..."

services=(
    "user-service"
    "product-service"
    "inventory-service"
    "order-service"
    "payment-service"
    "notification-service"
    "gateway-service"
    "service-a"
    "service-b"
    "service-c"
)

all_ready=true
for service in "${services[@]}"; do
    echo -n "  Waiting for $service..."
    if kubectl wait --for=condition=available --timeout=120s \
        deployment/$service -n services >/dev/null 2>&1; then
        echo " ✓"
    else
        echo " ✗ (timeout)"
        all_ready=false
    fi
done

echo

if [ "$all_ready" = "false" ]; then
    echo "⚠ Some services did not become ready in time"
    echo "Check status with: kubectl get pods -n services"
    echo
fi

# Show deployment status
echo "Step 8: Deployment Status"
echo
echo "Services in cluster:"
kubectl get pods -n services
echo

echo "Service endpoints:"
kubectl get svc -n services
echo

# Instructions
echo "=== ✅ Demo Environment Ready! ==="
echo
echo "Service Architecture:"
echo "  gateway-service → order-service → user-service"
echo "                                 → product-service → inventory-service"
echo "                                 → payment-service → notification-service"
echo
echo "Access Points:"
echo "  Gateway Service: http://localhost:30080"
echo "  Prometheus:      http://localhost:9090"
echo "  Grafana:         http://localhost:3000 (admin/admin)"
echo "  Jaeger:          http://localhost:16686"
echo
echo "Test the services:"
echo "  curl http://localhost:30080/health"
echo "  curl http://localhost:30080/api/data"
echo "  curl -X POST http://localhost:30080/api/action"
echo
echo "Generate traffic for demo:"
echo "  ./scripts/generate-traffic.sh"
echo
echo "View metrics in Prometheus:"
echo "  rate(http_requests_total[1m])"
echo "  histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))"
echo
echo "View traces in Jaeger:"
echo "  1. Open http://localhost:16686"
echo "  2. Select 'gateway-service' from dropdown"
echo "  3. Click 'Find Traces'"
echo "  4. Explore the distributed traces!"
echo
echo "Happy Monitoring! 🎉"
