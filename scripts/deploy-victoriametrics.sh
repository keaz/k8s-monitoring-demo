#!/bin/bash

# Deploy VictoriaMetrics and VictoriaTraces for enhanced monitoring

set -e

echo "=== Deploying VictoriaMetrics and VictoriaTraces ==="
echo

# Deploy VictoriaMetrics
echo "Step 1: Deploying VictoriaMetrics..."
kubectl apply -f kubernetes/base/victoriametrics/victoriametrics.yaml

echo "Step 2: Deploying VictoriaTraces..."
kubectl apply -f kubernetes/base/victoriametrics/victoriatraces.yaml

echo

# Update Prometheus config to enable remote write
echo "Step 3: Updating Prometheus configuration for remote write..."
kubectl apply -f kubernetes/base/victoriametrics/prometheus-remote-write.yaml

# Update OTEL Collector config
echo "Step 4: Updating OTEL Collector configuration..."
kubectl apply -f kubernetes/base/otel-collector/otel-collector-config.yaml

# Update Grafana datasources
echo "Step 5: Updating Grafana datasources..."
kubectl apply -f kubernetes/base/grafana/grafana-config.yaml

echo

# Restart deployments to pick up new configs
echo "Step 6: Restarting deployments..."
kubectl rollout restart deployment/prometheus -n monitoring
kubectl rollout restart deployment/otel-collector -n monitoring
kubectl rollout restart deployment/grafana -n monitoring

echo

# Wait for deployments
echo "Step 7: Waiting for new services to be ready..."
kubectl wait --for=condition=available --timeout=120s \
  deployment/victoriametrics -n monitoring 2>/dev/null || echo "  VictoriaMetrics starting..."

kubectl wait --for=condition=available --timeout=120s \
  deployment/victoriatraces -n monitoring 2>/dev/null || echo "  VictoriaTraces starting..."

echo

# Check status
echo "Step 8: Checking deployment status..."
kubectl get pods -n monitoring | grep -E "victoria|prometheus|otel|grafana"

echo
echo "=== Deployment Complete ==="
echo
echo "New Components:"
echo "  VictoriaMetrics: http://localhost:30003 (metrics storage)"
echo "  VictoriaTraces:  http://localhost:30004 (trace storage)"
echo
echo "Updated Components:"
echo "  Prometheus: Now sending data to VictoriaMetrics via remote write"
echo "  OTEL Collector: Now sending traces to both Jaeger and VictoriaTraces"
echo "  Grafana: New datasources added (VictoriaMetrics, VictoriaTraces)"
echo
echo "Grafana Datasources (http://localhost:3000):"
echo "  - Prometheus (default)"
echo "  - VictoriaMetrics"
echo "  - Jaeger"
echo "  - VictoriaTraces"
echo
echo "Next Steps:"
echo "  1. Wait 2-3 minutes for data to accumulate"
echo "  2. Generate some traffic: ./scripts/generate-traffic.sh"
echo "  3. Import the VictoriaTraces dashboard:"
echo "     - Open Grafana: http://localhost:3000"
echo "     - Go to Dashboards → Import"
echo "     - Enter dashboard ID: 24134"
echo "     - Select 'VictoriaMetrics' or 'VictoriaTraces' as datasource"
echo "     - Click Import"
echo
