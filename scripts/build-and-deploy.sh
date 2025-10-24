#!/bin/bash

set -e

echo "=== Building and Deploying K8s Monitoring Demo ==="

# Export PATH to include kind
export PATH="$HOME/.local/bin:$PATH"

# Build Java services
echo "Discovering Java services..."
JAVA_SERVICES=()
for dir in services/java/*/; do
    [ -d "$dir" ] || continue
    if [ -f "${dir%/}/pom.xml" ]; then
        JAVA_SERVICES+=("$(basename "$dir")")
    fi
done

IFS=$'\n' JAVA_SERVICES=($(printf "%s\n" "${JAVA_SERVICES[@]}" | sort))
unset IFS

if [ ${#JAVA_SERVICES[@]} -eq 0 ]; then
    echo "ERROR: No Java services found under services/java"
    exit 1
fi

echo "Building Java services: ${JAVA_SERVICES[*]}"

for service in "${JAVA_SERVICES[@]}"; do
    echo "Building $service..."
    pushd "services/java/$service" >/dev/null
    docker build -t "$service:latest" .
    kind load docker-image "$service:latest" --name monitoring-demo
    popd >/dev/null
done

# Deploy using kustomize
echo "Deploying services to Kubernetes..."
kubectl apply -k kubernetes/overlays/dev/

echo "Waiting for deployments to be ready..."
kubectl wait --for=condition=ready pod -l app=prometheus -n monitoring --timeout=300s
kubectl wait --for=condition=ready pod -l app=grafana -n monitoring --timeout=300s
kubectl wait --for=condition=ready pod -l app=jaeger -n monitoring --timeout=300s
for service in "${JAVA_SERVICES[@]}"; do
    kubectl wait --for=condition=available deployment/"$service" -n services --timeout=300s
done

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "Access the services:"
echo "  Prometheus:            http://localhost:9090"
echo "  Grafana:               http://localhost:3000 (admin/admin)"
echo "  Jaeger UI:             http://localhost:16686"
echo "  Service A example:     http://localhost:30080/api/hello"
echo "  OTEL metrics endpoint: http://<pod-ip>:9464/metrics"
echo ""
echo "Monitor pods:"
echo "  kubectl get pods -n monitoring"
echo "  kubectl get pods -n services"
