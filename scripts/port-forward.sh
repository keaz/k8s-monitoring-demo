#!/bin/bash

echo "=== Starting Port Forwarding for Monitoring Services ==="
echo ""
echo "This will forward the following services to localhost:"
echo "  - Prometheus:     http://localhost:9090"
echo "  - Grafana:        http://localhost:3000 (admin/admin)"
echo "  - Jaeger UI:      http://localhost:16686"
echo "  - Service-A:      http://localhost:8080"
echo ""
echo "Press Ctrl+C to stop all port forwards"
echo ""

# Function to cleanup background processes on exit
cleanup() {
    echo ""
    echo "Stopping all port forwards..."
    jobs -p | xargs -r kill
    exit 0
}

trap cleanup EXIT INT TERM

# Start port forwards in background
kubectl port-forward -n monitoring svc/prometheus 9090:9090 > /dev/null 2>&1 &
echo "✓ Prometheus port-forward started (9090)"

kubectl port-forward -n monitoring svc/grafana 3000:3000 > /dev/null 2>&1 &
echo "✓ Grafana port-forward started (3000)"

kubectl port-forward -n monitoring svc/jaeger-query 16686:16686 > /dev/null 2>&1 &
echo "✓ Jaeger UI port-forward started (16686)"

kubectl port-forward -n services svc/service-a 8080:80 > /dev/null 2>&1 &
echo "✓ Service-A port-forward started (8080)"

echo ""
echo "All port forwards are running. Access the services at:"
echo "  - Prometheus:     http://localhost:9090"
echo "  - Grafana:        http://localhost:3000 (admin/admin)"
echo "  - Jaeger UI:      http://localhost:16686"
echo "  - Service-A:      http://localhost:8080"
echo ""
echo "Press Ctrl+C to stop..."

# Wait indefinitely
wait
