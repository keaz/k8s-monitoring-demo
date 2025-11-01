#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=== Deploying Monitoring Namespace Resources ==="

if ! command -v kubectl >/dev/null 2>&1; then
    echo "Error: kubectl is not installed or not in PATH" >&2
    exit 1
fi

CURRENT_CONTEXT="$(kubectl config current-context 2>/dev/null || echo "unknown")"
echo "Using kube context: $CURRENT_CONTEXT"

echo "Ensuring monitoring namespace exists..."
if ! kubectl get namespace monitoring >/dev/null 2>&1; then
    kubectl create namespace monitoring
else
    echo "Namespace monitoring already present"
fi

MANIFESTS=(
    "kubernetes/base/storage/monitoring-pvcs.yaml"
    "kubernetes/base/prometheus/prometheus-rbac.yaml"
    "kubernetes/base/prometheus/prometheus-config.yaml"
    "kubernetes/base/prometheus/prometheus-deployment.yaml"
    "kubernetes/base/grafana/grafana-config.yaml"
    "kubernetes/base/grafana/grafana-deployment.yaml"
    "kubernetes/base/jaeger/jaeger-config.yaml"
    "kubernetes/base/jaeger/jaeger-production.yaml"
    "kubernetes/base/victoriametrics/victoriametrics.yaml"
    "kubernetes/base/victoriametrics/victoriatraces.yaml"
    "kubernetes/base/otel-collector/otel-collector-config.yaml"
    "kubernetes/base/otel-collector/otel-collector-deployment.yaml"
    "kubernetes/base/node-exporter/node-exporter.yaml"
)

echo "Applying monitoring manifests..."
for manifest in "${MANIFESTS[@]}"; do
    echo "kubectl apply -f $manifest"
    kubectl apply -f "$PROJECT_ROOT/$manifest"
    echo ""
done

DEPLOYMENTS=(
    "deployment/prometheus"
    "deployment/grafana"
    "deployment/otel-collector"
    "deployment/jaeger"
    "deployment/victoriametrics"
    "deployment/victoriatraces"
)

echo "Waiting for monitoring workloads to become available..."
for target in "${DEPLOYMENTS[@]}"; do
    resource_name="${target#*/}"
    echo "Waiting for $resource_name..."
    if ! kubectl wait --for=condition=available --timeout=300s "$target" -n monitoring; then
        echo "Warning: $resource_name did not report ready within 300s" >&2
    fi
    echo ""
done

echo "=== Monitoring stack deployed ==="
echo "Resources deployed in namespace 'monitoring'."
echo "Use 'kubectl get pods -n monitoring' to verify status."
