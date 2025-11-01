#!/bin/bash

# Cleanup script to fix service mesh conflicts
# Use this if pods are failing to start due to webhook errors
# or if you're switching between Istio and Linkerd

set -e

echo "========================================="
echo "Service Mesh Conflict Cleanup"
echo "========================================="
echo ""
echo "This script will:"
echo "  - Remove Istio injection labels from namespaces"
echo "  - Remove Istio webhooks that block pod creation"
echo "  - Remove Linkerd injection labels (optional)"
echo "  - Restart failed deployments"
echo ""

read -p "Continue with cleanup? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""
echo "Starting cleanup..."
echo ""

# Step 1: Remove Istio injection labels
echo "=== Removing Istio injection labels ==="
kubectl label namespace services istio-injection- 2>/dev/null && echo "  ✓ Removed from services namespace" || echo "  - Not set on services namespace"
kubectl label namespace monitoring istio-injection- 2>/dev/null && echo "  ✓ Removed from monitoring namespace" || echo "  - Not set on monitoring namespace"
echo ""

# Step 2: Remove Istio webhooks
echo "=== Removing Istio webhooks ==="

# Mutating webhooks
if kubectl get mutatingwebhookconfiguration istio-revision-tag-default &>/dev/null; then
    kubectl delete mutatingwebhookconfiguration istio-revision-tag-default
    echo "  ✓ Removed istio-revision-tag-default"
fi

if kubectl get mutatingwebhookconfiguration istio-sidecar-injector &>/dev/null; then
    kubectl delete mutatingwebhookconfiguration istio-sidecar-injector
    echo "  ✓ Removed istio-sidecar-injector"
fi

# Validating webhooks
if kubectl get validatingwebhookconfiguration istio-validator-istio-system &>/dev/null; then
    kubectl delete validatingwebhookconfiguration istio-validator-istio-system
    echo "  ✓ Removed istio-validator-istio-system"
fi

echo ""

# Step 3: Check for failed deployments
echo "=== Checking for failed deployments ==="
FAILED_DEPLOYMENTS=$(kubectl get deployments -n services -o json | jq -r '.items[] | select(.status.conditions[]? | select(.type=="ReplicaFailure" and .status=="True")) | .metadata.name' 2>/dev/null)

if [ -n "$FAILED_DEPLOYMENTS" ]; then
    echo "Found failed deployments:"
    echo "$FAILED_DEPLOYMENTS"
    echo ""

    read -p "Restart failed deployments? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        while IFS= read -r deployment; do
            if [ -n "$deployment" ]; then
                echo "  Restarting $deployment..."
                kubectl rollout restart deployment/"$deployment" -n services
            fi
        done <<< "$FAILED_DEPLOYMENTS"

        echo ""
        echo "Waiting for deployments to be ready..."
        kubectl wait --for=condition=available deployment --all -n services --timeout=300s 2>/dev/null || true
    fi
else
    echo "  No failed deployments found"
fi

echo ""

# Step 4: Optional - Remove Linkerd injection
echo "=== Linkerd injection labels ==="
read -p "Do you want to remove Linkerd injection labels? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    kubectl annotate namespace services linkerd.io/inject- 2>/dev/null && echo "  ✓ Removed from services namespace" || echo "  - Not set on services namespace"
    kubectl annotate namespace monitoring linkerd.io/inject- 2>/dev/null && echo "  ✓ Removed from monitoring namespace" || echo "  - Not set on monitoring namespace"
fi

echo ""

# Step 5: Summary
echo "========================================="
echo "Cleanup Summary"
echo "========================================="
echo ""

# Check current state
echo "Current injection labels:"
echo ""

echo "Services namespace:"
SERVICES_ISTIO=$(kubectl get namespace services -o jsonpath='{.metadata.labels.istio-injection}' 2>/dev/null)
SERVICES_LINKERD=$(kubectl get namespace services -o jsonpath='{.metadata.annotations.linkerd\.io/inject}' 2>/dev/null)

if [ -n "$SERVICES_ISTIO" ]; then
    echo "  - Istio injection: $SERVICES_ISTIO"
else
    echo "  - Istio injection: not set ✓"
fi

if [ -n "$SERVICES_LINKERD" ]; then
    echo "  - Linkerd injection: $SERVICES_LINKERD"
else
    echo "  - Linkerd injection: not set ✓"
fi

echo ""

# Check webhooks
echo "Remaining webhooks:"
ISTIO_WEBHOOKS=$(kubectl get mutatingwebhookconfiguration,validatingwebhookconfiguration 2>/dev/null | grep -i istio | wc -l)
if [ "$ISTIO_WEBHOOKS" -eq 0 ]; then
    echo "  ✓ No Istio webhooks found"
else
    echo "  ⚠ Found $ISTIO_WEBHOOKS Istio webhook(s):"
    kubectl get mutatingwebhookconfiguration,validatingwebhookconfiguration 2>/dev/null | grep -i istio
fi

echo ""

# Check pod status
echo "Current pod status (services namespace):"
kubectl get pods -n services

echo ""
echo "========================================="
echo "Cleanup Complete!"
echo "========================================="
echo ""
echo "Next steps:"
echo ""
echo "If you want to install Linkerd:"
echo "  ./scripts/install-linkerd.sh"
echo ""
echo "If you want to install Istio:"
echo "  ./scripts/install-istio.sh"
echo ""
echo "To deploy everything with a service mesh:"
echo "  ./scripts/deploy-with-linkerd.sh  (for Linkerd)"
echo "  ./scripts/deploy-with-istio.sh    (for Istio)"
echo ""
