#!/bin/bash

set -e

echo "=== Cleaning up Kubernetes cluster (preserving PVCs and data) ==="
echo ""
echo "This script will:"
echo "  - Delete all deployments, services, configmaps, secrets, etc."
echo "  - PRESERVE all PVCs and their data"
echo "  - Keep namespaces for redeployment"
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

# Function to delete resources in a namespace, excluding PVCs
cleanup_namespace() {
    local namespace=$1
    echo "=== Cleaning namespace: $namespace ==="

    # Delete deployments
    echo "  Deleting deployments..."
    kubectl delete deployments --all -n $namespace --ignore-not-found=true

    # Delete statefulsets
    echo "  Deleting statefulsets..."
    kubectl delete statefulsets --all -n $namespace --ignore-not-found=true

    # Delete daemonsets
    echo "  Deleting daemonsets..."
    kubectl delete daemonsets --all -n $namespace --ignore-not-found=true

    # Delete services (excluding kubernetes default service)
    echo "  Deleting services..."
    kubectl delete services --all -n $namespace --ignore-not-found=true

    # Delete configmaps (excluding kube-root-ca.crt which is auto-generated)
    echo "  Deleting configmaps..."
    kubectl delete configmaps --all -n $namespace --ignore-not-found=true

    # Delete secrets (excluding default service account token)
    echo "  Deleting secrets..."
    kubectl delete secrets --all -n $namespace --ignore-not-found=true

    # Delete service accounts (excluding default)
    echo "  Deleting service accounts..."
    kubectl get serviceaccounts -n $namespace -o name | grep -v "default" | xargs -r kubectl delete -n $namespace --ignore-not-found=true

    # Delete roles and rolebindings
    echo "  Deleting roles and rolebindings..."
    kubectl delete roles --all -n $namespace --ignore-not-found=true
    kubectl delete rolebindings --all -n $namespace --ignore-not-found=true

    # Delete ingresses
    echo "  Deleting ingresses..."
    kubectl delete ingresses --all -n $namespace --ignore-not-found=true

    # Delete HPA (Horizontal Pod Autoscalers)
    echo "  Deleting HPAs..."
    kubectl delete hpa --all -n $namespace --ignore-not-found=true

    # Delete network policies
    echo "  Deleting network policies..."
    kubectl delete networkpolicies --all -n $namespace --ignore-not-found=true

    echo "  ✓ Namespace $namespace cleaned (PVCs preserved)"
    echo ""
}

# Clean up monitoring namespace
if kubectl get namespace monitoring &>/dev/null; then
    cleanup_namespace "monitoring"
else
    echo "Namespace 'monitoring' does not exist, skipping..."
fi

# Clean up services namespace
if kubectl get namespace services &>/dev/null; then
    cleanup_namespace "services"
else
    echo "Namespace 'services' does not exist, skipping..."
fi

# Delete cluster-wide resources created by the demo
echo "=== Cleaning cluster-wide resources ==="

# Delete ClusterRoles and ClusterRoleBindings created by the demo
echo "  Deleting prometheus-related ClusterRoles and ClusterRoleBindings..."
kubectl delete clusterrole prometheus --ignore-not-found=true
kubectl delete clusterrolebinding prometheus --ignore-not-found=true

echo "  Deleting kiali-related ClusterRoles and ClusterRoleBindings..."
kubectl delete clusterrole kiali --ignore-not-found=true
kubectl delete clusterrole kiali-viewer --ignore-not-found=true
kubectl delete clusterrolebinding kiali --ignore-not-found=true

# Wait for pods to terminate
echo ""
echo "Waiting for pods to terminate..."
kubectl wait --for=delete pod --all -n monitoring --timeout=120s 2>/dev/null || true
kubectl wait --for=delete pod --all -n services --timeout=120s 2>/dev/null || true

echo ""
echo "=== Cleanup Summary ==="
echo ""

# Show preserved PVCs
echo "Preserved PVCs:"
echo ""
kubectl get pvc -n monitoring 2>/dev/null || echo "  No PVCs in monitoring namespace"
echo ""
kubectl get pvc -n services 2>/dev/null || echo "  No PVCs in services namespace"

echo ""
echo "=== Cleanup Complete ==="
echo ""
echo "All services and deployments have been removed."
echo "PVCs and their data have been preserved."
echo ""
echo "To redeploy with preserved data, run:"
echo "  ./scripts/build-and-deploy.sh"
echo ""
