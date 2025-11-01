#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}" )" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

export PATH="$HOME/.local/bin:$PATH"

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "ERROR: '$1' command not found. Please install it before running this script." >&2
        exit 1
    fi
}

apply_manifest_if_exists() {
    local manifest="$1"
    if [ -f "$manifest" ]; then
        echo "Applying $(basename "$manifest")"
        kubectl apply -f "$manifest"
    fi
}

restart_services_for_mesh() {
    local mesh_name="$1"
    echo "Restarting services to ensure $mesh_name sidecars are injected..."
    for service in "${JAVA_SERVICES[@]}"; do
        echo "  Restarting deployment/$service"
        kubectl rollout restart deployment/"$service" -n services || true
    done

    echo "Waiting for services to become available..."
    for service in "${JAVA_SERVICES[@]}"; do
        kubectl wait --for=condition=available deployment/"$service" -n services --timeout=300s || \
            echo "Warning: deployment/$service did not become available within 300s"
    done
}

configure_istio() {
    echo "========================================="
    echo "Configuring Istio Service Mesh"
    echo "========================================="

    local istio_version="1.24.0" # Keep in sync with install-istio.sh
    local existing_istio_bin=""
    local istio_locations=(
        "$PROJECT_ROOT/istio-$istio_version/bin"
        "$SCRIPT_DIR/istio-$istio_version/bin"
    )

    for candidate in "${istio_locations[@]}"; do
        if [ -x "$candidate/istioctl" ]; then
            existing_istio_bin="$candidate"
            break
        fi
    done

    if [ -n "$existing_istio_bin" ]; then
        echo "Detected existing Istio download at ${existing_istio_bin%/bin}. Reusing it."
        export PATH="$existing_istio_bin:$PATH"
    fi

    echo "Removing Linkerd annotations to avoid conflicts (if present)..."
    kubectl annotate namespace services linkerd.io/inject- --overwrite 2>/dev/null || true
    kubectl annotate namespace monitoring linkerd.io/inject- --overwrite 2>/dev/null || true

    echo "Installing Istio (if not already installed)..."
    if [ -x "$SCRIPT_DIR/install-istio.sh" ]; then
        "$SCRIPT_DIR/install-istio.sh"
    else
        echo "ERROR: install-istio.sh not found or not executable." >&2
        exit 1
    fi

    echo "Applying Istio baseline manifests..."
    apply_manifest_if_exists "$PROJECT_ROOT/kubernetes/base/istio/istio-gateway.yaml"
    apply_manifest_if_exists "$PROJECT_ROOT/kubernetes/base/istio/destination-rules.yaml"
    apply_manifest_if_exists "$PROJECT_ROOT/kubernetes/base/istio/telemetry-integration.yaml"
    apply_manifest_if_exists "$PROJECT_ROOT/kubernetes/base/istio/security-policies.yaml"
    apply_manifest_if_exists "$PROJECT_ROOT/kubernetes/base/istio/prometheus-istio-scrape.yaml"
    apply_manifest_if_exists "$PROJECT_ROOT/kubernetes/base/istio/kiali-custom-config.yaml"

    echo "Waiting for Istio control plane to report ready..."
    kubectl wait --for=condition=available deployment/istiod -n istio-system --timeout=300s || \
        echo "Warning: istiod not ready within timeout"

    if kubectl get deployment kiali -n istio-system >/dev/null 2>&1; then
        kubectl wait --for=condition=available deployment/kiali -n istio-system --timeout=300s || \
            echo "Warning: Kiali not ready within timeout"
    fi

    restart_services_for_mesh "Istio"

    echo "Istio pods (istio-system namespace):"
    kubectl get pods -n istio-system || true
    echo ""
    echo "Services namespace pods (should show 2/2 containers):"
    kubectl get pods -n services || true
}

configure_linkerd() {
    echo "========================================="
    echo "Configuring Linkerd Service Mesh"
    echo "========================================="

    echo "Removing Istio labels and webhooks to avoid conflicts (if present)..."
    kubectl label namespace services istio-injection- --overwrite 2>/dev/null || true
    kubectl label namespace monitoring istio-injection- --overwrite 2>/dev/null || true
    kubectl delete mutatingwebhookconfiguration istio-revision-tag-default 2>/dev/null || true
    kubectl delete mutatingwebhookconfiguration istio-sidecar-injector 2>/dev/null || true
    kubectl delete validatingwebhookconfiguration istio-validator-istio-system 2>/dev/null || true

    echo "Installing Linkerd (if not already installed)..."
    if [ -x "$SCRIPT_DIR/install-linkerd-no-prometheus.sh" ]; then
        "$SCRIPT_DIR/install-linkerd-no-prometheus.sh"
    elif [ -x "$SCRIPT_DIR/install-linkerd.sh" ]; then
        "$SCRIPT_DIR/install-linkerd.sh"
    else
        echo "ERROR: Linkerd install scripts not found." >&2
        exit 1
    fi

    echo "Applying Linkerd configuration manifests..."
    if [ -f "$PROJECT_ROOT/kubernetes/linkerd/service-profiles-simple.yaml" ]; then
        kubectl apply -f "$PROJECT_ROOT/kubernetes/linkerd/service-profiles-simple.yaml"
    else
        apply_manifest_if_exists "$PROJECT_ROOT/kubernetes/linkerd/service-profiles.yaml"
    fi
    apply_manifest_if_exists "$PROJECT_ROOT/kubernetes/linkerd/authorization-policy.yaml"
    apply_manifest_if_exists "$PROJECT_ROOT/kubernetes/linkerd/traffic-split.yaml"

    if command -v linkerd >/dev/null 2>&1; then
        echo "Running post-install Linkerd checks..."
        linkerd check || echo "Warning: linkerd check reported issues"
        linkerd viz check || echo "Warning: linkerd viz check reported issues"
    fi

    restart_services_for_mesh "Linkerd"

    echo "Linkerd control plane pods (linkerd namespace):"
    kubectl get pods -n linkerd || true
    echo ""
    echo "Linkerd Viz pods (linkerd-viz namespace):"
    kubectl get pods -n linkerd-viz || true
    echo ""
    echo "Services namespace pods (should show 2/2 containers):"
    kubectl get pods -n services || true
}

require_command kubectl

echo "=== Service Mesh Setup (No Build/Deploy) ==="

echo "Discovering Java services..."
JAVA_SERVICES=()
for dir in "$PROJECT_ROOT"/services/java/*/; do
    [ -d "$dir" ] || continue
    if [ -f "${dir%/}/pom.xml" ]; then
        JAVA_SERVICES+=("$(basename "$dir")")
    fi
done

if [ ${#JAVA_SERVICES[@]} -eq 0 ]; then
    echo "ERROR: No Java services found under services/java" >&2
    exit 1
fi

IFS=$'\n' JAVA_SERVICES=($(printf "%s\n" "${JAVA_SERVICES[@]}" | sort))
unset IFS

echo "Services detected: ${JAVA_SERVICES[*]}"
echo "Skipping build and deployment; assuming images and manifests already exist."
echo ""

MESH_CHOICE=""
if [ $# -gt 0 ]; then
    case "$1" in
        istio|Istio)
            MESH_CHOICE="istio"
            ;;
        linkerd|Linkerd)
            MESH_CHOICE="linkerd"
            ;;
        *)
            echo "Unknown mesh argument: $1" >&2
            exit 1
            ;;
    esac
fi

if [ -z "$MESH_CHOICE" ]; then
    echo "Select service mesh to configure:"
    echo "  1) Istio"
    echo "  2) Linkerd"
    echo "  0) Exit without changes"
    read -r -p "Choice [1/2/0]: " selection
    case "$selection" in
        1)
            MESH_CHOICE="istio"
            ;;
        2)
            MESH_CHOICE="linkerd"
            ;;
        0|"")
            echo "No mesh selected. Exiting."
            exit 0
            ;;
        *)
            echo "Invalid choice. Exiting." >&2
            exit 1
            ;;
    esac
else
    echo "Mesh selection provided via argument: $MESH_CHOICE"
fi

echo ""

echo "Configuring $MESH_CHOICE service mesh..."
case "$MESH_CHOICE" in
    istio)
        configure_istio
        ;;
    linkerd)
        configure_linkerd
        ;;
    *)
        echo "Unhandled mesh choice: $MESH_CHOICE" >&2
        exit 1
        ;;
esac

echo ""
echo "=== Service mesh configuration complete ==="
