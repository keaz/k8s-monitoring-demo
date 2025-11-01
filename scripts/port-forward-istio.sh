#!/bin/bash

# Helper script to port-forward core Istio observability tooling
# and the ingress gateway for local access.

cat <<"INTRO"
=== Starting Port Forwarding for Istio Observability ===

This will forward the following services to localhost:
  - Prometheus:          http://localhost:9090
  - Grafana:             http://localhost:3000 (admin/admin)
  - Jaeger UI:           http://localhost:16686
  - Istio Ingress GW:    http://localhost:8080
  - Kiali Dashboard:     http://localhost:20001

Press Ctrl+C to stop all port forwards

INTRO

cleanup() {
    echo ""
    echo "Stopping all port forwards..."
    jobs -p | xargs -r kill
    exit 0
}

trap cleanup EXIT INT TERM

kubectl port-forward -n monitoring svc/prometheus 9090:9090 > /dev/null 2>&1 &
echo "✓ Prometheus port-forward started (9090)"

kubectl port-forward -n monitoring svc/grafana 3000:3000 > /dev/null 2>&1 &
echo "✓ Grafana port-forward started (3000)"

kubectl port-forward -n monitoring svc/jaeger-query 16686:16686 > /dev/null 2>&1 &
echo "✓ Jaeger UI port-forward started (16686)"

kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80 > /dev/null 2>&1 &
echo "✓ Istio ingress gateway port-forward started (8080)"

kubectl port-forward -n istio-system svc/kiali 20001:20001 > /dev/null 2>&1 &
echo "✓ Kiali dashboard port-forward started (20001)"

echo ""
echo "All port forwards are running. Access the services at:"
echo "  - Prometheus:          http://localhost:9090"
echo "  - Grafana:             http://localhost:3000 (admin/admin)"
echo "  - Jaeger UI:           http://localhost:16686"
echo "  - Istio Ingress GW:    http://localhost:8080"
echo "  - Kiali Dashboard:     http://localhost:20001"
echo ""
echo "Press Ctrl+C to stop..."

wait
