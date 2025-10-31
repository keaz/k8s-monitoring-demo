#!/bin/bash

# Remove duplicate monitoring tools from istio-system namespace
# Keep only Kiali, remove Prometheus, Grafana, and Jaeger duplicates
# since you already have these in the monitoring namespace

set -e

echo "========================================="
echo "Cleaning Up Duplicate Monitoring Tools"
echo "========================================="
echo ""

echo "This will remove duplicate Prometheus, Grafana, and Jaeger from istio-system"
echo "You already have these tools in the 'monitoring' namespace"
echo "Kiali will be configured to use your existing monitoring stack"
echo ""

read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "Removing duplicate Prometheus from istio-system..."
kubectl delete deployment prometheus -n istio-system --ignore-not-found=true
kubectl delete service prometheus -n istio-system --ignore-not-found=true
kubectl delete serviceaccount prometheus -n istio-system --ignore-not-found=true
kubectl delete configmap prometheus -n istio-system --ignore-not-found=true
kubectl delete clusterrole prometheus --ignore-not-found=true
kubectl delete clusterrolebinding prometheus --ignore-not-found=true

echo "Removing duplicate Grafana from istio-system..."
kubectl delete deployment grafana -n istio-system --ignore-not-found=true
kubectl delete service grafana -n istio-system --ignore-not-found=true
kubectl delete serviceaccount grafana -n istio-system --ignore-not-found=true
kubectl delete configmap grafana -n istio-system --ignore-not-found=true
kubectl delete configmap istio-grafana-dashboards -n istio-system --ignore-not-found=true
kubectl delete configmap istio-services-grafana-dashboards -n istio-system --ignore-not-found=true

echo "Removing duplicate Jaeger from istio-system..."
kubectl delete deployment jaeger -n istio-system --ignore-not-found=true
kubectl delete service tracing -n istio-system --ignore-not-found=true
kubectl delete service zipkin -n istio-system --ignore-not-found=true
kubectl delete service jaeger-collector -n istio-system --ignore-not-found=true

echo ""
echo "✓ Cleanup complete!"
echo ""

echo "Remaining components in istio-system:"
kubectl get deployments,services -n istio-system

echo ""
echo "========================================="
echo "Next Steps"
echo "========================================="
echo ""
echo "Kiali is now configured to use your existing monitoring stack:"
echo "  - Prometheus: monitoring namespace"
echo "  - Grafana: monitoring namespace"
echo "  - Jaeger: monitoring namespace"
echo ""
echo "Access Kiali:"
echo "  kubectl port-forward -n istio-system svc/kiali 20001:20001"
echo "  http://localhost:20001"
echo ""
