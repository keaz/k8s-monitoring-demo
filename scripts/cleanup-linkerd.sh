#!/bin/bash

# Remove Linkerd service mesh from the cluster
# This script completely uninstalls Linkerd including all extensions

set -e

echo "========================================="
echo "Cleanup Linkerd Service Mesh"
echo "========================================="
echo ""
echo "This will remove:"
echo "  - Linkerd control plane"
echo "  - Linkerd Viz extension"
echo "  - Linkerd namespaces"
echo "  - Linkerd CRDs"
echo "  - Sidecar injection annotations"
echo ""

read -p "Continue with Linkerd cleanup? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""
echo "Starting Linkerd cleanup..."
echo ""

# Check if linkerd CLI is available
if ! command -v linkerd &> /dev/null; then
    echo "Warning: linkerd CLI not found"
    echo "Proceeding with manual cleanup..."
    MANUAL_CLEANUP=true
else
    MANUAL_CLEANUP=false
fi

# Remove sidecar injection annotations from namespaces
echo "=== Removing sidecar injection annotations ==="
echo "  Removing from services namespace..."
kubectl annotate namespace services linkerd.io/inject- --overwrite 2>/dev/null || true

echo "  Removing from monitoring namespace..."
kubectl annotate namespace monitoring linkerd.io/inject- --overwrite 2>/dev/null || true

echo "✓ Injection annotations removed"
echo ""

# Restart services to remove sidecars
echo "=== Restarting services to remove sidecars ==="
if kubectl get deployment -n services &>/dev/null; then
    echo "  Restarting services namespace deployments..."
    kubectl rollout restart deployment -n services 2>/dev/null || true

    echo "  Waiting for pods to restart..."
    sleep 10
    kubectl wait --for=condition=ready pod --all -n services --timeout=120s 2>/dev/null || true
fi

echo "✓ Services restarted"
echo ""

# Uninstall Linkerd Viz extension
echo "=== Uninstalling Linkerd Viz extension ==="
if [ "$MANUAL_CLEANUP" = false ]; then
    linkerd viz uninstall | kubectl delete -f - 2>/dev/null || true
else
    kubectl delete namespace linkerd-viz --ignore-not-found=true
fi

echo "✓ Linkerd Viz uninstalled"
echo ""

# Uninstall Linkerd control plane
echo "=== Uninstalling Linkerd control plane ==="
if [ "$MANUAL_CLEANUP" = false ]; then
    linkerd uninstall | kubectl delete -f - 2>/dev/null || true
else
    kubectl delete namespace linkerd --ignore-not-found=true
fi

echo "✓ Linkerd control plane uninstalled"
echo ""

# Delete Linkerd CRDs
echo "=== Deleting Linkerd CRDs ==="
kubectl get crd -o name | grep 'linkerd.io' | xargs -r kubectl delete --ignore-not-found=true

echo "✓ Linkerd CRDs deleted"
echo ""

# Delete cluster-wide resources
echo "=== Cleaning cluster-wide resources ==="

echo "  Deleting Linkerd ClusterRoles..."
kubectl delete clusterrole -l linkerd.io/control-plane-ns --ignore-not-found=true
kubectl delete clusterrole linkerd-linkerd-destination --ignore-not-found=true
kubectl delete clusterrole linkerd-linkerd-identity --ignore-not-found=true
kubectl delete clusterrole linkerd-linkerd-proxy-injector --ignore-not-found=true

echo "  Deleting Linkerd ClusterRoleBindings..."
kubectl delete clusterrolebinding -l linkerd.io/control-plane-ns --ignore-not-found=true
kubectl delete clusterrolebinding linkerd-linkerd-destination --ignore-not-found=true
kubectl delete clusterrolebinding linkerd-linkerd-identity --ignore-not-found=true
kubectl delete clusterrolebinding linkerd-linkerd-proxy-injector --ignore-not-found=true

echo "  Deleting Linkerd ValidatingWebhookConfigurations..."
kubectl delete validatingwebhookconfiguration linkerd-policy-validator --ignore-not-found=true
kubectl delete validatingwebhookconfiguration linkerd-sp-validator --ignore-not-found=true

echo "  Deleting Linkerd MutatingWebhookConfigurations..."
kubectl delete mutatingwebhookconfiguration linkerd-proxy-injector --ignore-not-found=true

echo "✓ Cluster-wide resources cleaned"
echo ""

# Wait for pods to terminate
echo "Waiting for pods to terminate..."
kubectl wait --for=delete pod --all -n linkerd --timeout=120s 2>/dev/null || true
kubectl wait --for=delete pod --all -n linkerd-viz --timeout=120s 2>/dev/null || true

echo ""
echo "=== Cleanup Summary ==="
echo ""

# Check what's left
echo "Remaining Linkerd resources:"
echo ""

LINKERD_NAMESPACES=$(kubectl get namespace -o name | grep 'linkerd' | wc -l)
if [ "$LINKERD_NAMESPACES" -eq 0 ]; then
    echo "  ✓ No Linkerd namespaces remaining"
else
    echo "  ⚠ Found $LINKERD_NAMESPACES Linkerd namespace(s):"
    kubectl get namespace | grep 'linkerd'
fi

LINKERD_CRDS=$(kubectl get crd -o name | grep 'linkerd.io' | wc -l)
if [ "$LINKERD_CRDS" -eq 0 ]; then
    echo "  ✓ No Linkerd CRDs remaining"
else
    echo "  ⚠ Found $LINKERD_CRDS Linkerd CRD(s):"
    kubectl get crd | grep 'linkerd.io'
fi

echo ""
echo "Services (should now show 1/1 containers):"
kubectl get pods -n services 2>/dev/null || echo "  No services namespace"

echo ""
echo "=== Cleanup Complete ==="
echo ""
echo "Linkerd has been removed from the cluster."
echo ""
echo "To reinstall Linkerd, run:"
echo "  ./scripts/install-linkerd.sh"
echo "  or"
echo "  ./scripts/deploy-with-linkerd.sh"
echo ""
