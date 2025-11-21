#!/bin/bash

# Traffic Generation Script for Monitoring Demo via Istio Gateway
# This script sends traffic through the Istio ingress gateway to demonstrate service mesh observability

set -e

# Configuration
DURATION="${DURATION:-300}"  # Run for 5 minutes by default
CONCURRENT_USERS="${CONCURRENT_USERS:-5}"
NAMESPACE="${NAMESPACE:-services}"

echo "=== Traffic Generator for K8s Monitoring Demo (via Istio Gateway) ==="

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "ERROR: kubectl not found. Please install kubectl."
    exit 1
fi

# Check if curl is available
if ! command -v curl &> /dev/null; then
    echo "ERROR: curl not found. Please install curl."
    exit 1
fi

# Get Istio ingress gateway address
echo "Detecting Istio ingress gateway..."
INGRESS_HOST=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
if [ -z "$INGRESS_HOST" ]; then
    INGRESS_HOST=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
fi

# If LoadBalancer is not available, try to use NodePort
if [ -z "$INGRESS_HOST" ]; then
    echo "LoadBalancer not available, trying NodePort..."
    INGRESS_HOST=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
    INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}')
else
    INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].port}')
fi

if [ -z "$INGRESS_HOST" ]; then
    echo "ERROR: Could not determine Istio ingress gateway address"
    echo "Please ensure Istio is installed and the ingress gateway is running:"
    echo "  kubectl get svc -n istio-system istio-ingressgateway"
    exit 1
fi

GATEWAY_URL="http://${INGRESS_HOST}:${INGRESS_PORT}"

echo "Gateway URL: $GATEWAY_URL"
echo "Duration: ${DURATION}s"
echo "Concurrent Users: $CONCURRENT_USERS"
echo

# Check if services are running
echo "Checking if services are running..."
if ! kubectl get deployment service-a -n $NAMESPACE &> /dev/null; then
    echo "ERROR: service-a not found in namespace $NAMESPACE"
    echo "Please deploy the services first:"
    echo "  ./scripts/build-and-deploy.sh"
    exit 1
fi

# Test gateway connectivity
echo "Testing gateway connectivity..."
if curl -s -f -m 5 "${GATEWAY_URL}/api/hello" > /dev/null 2>&1; then
    echo "✓ Gateway is accessible"
else
    echo "WARNING: Gateway test failed. Continuing anyway..."
    echo "If you encounter issues, check that:"
    echo "  1. Istio gateway is running: kubectl get gateway -n services"
    echo "  2. VirtualService is configured: kubectl get virtualservice -n services"
fi
echo

# Function to make a request via Istio gateway
make_request() {
    local path=$1
    local quiet=${2:-false}
    local url="${GATEWAY_URL}${path}"

    if [ "$quiet" = "true" ]; then
        curl -s -f -m 10 "$url" > /dev/null 2>&1
        return $?
    else
        if curl -s -f -m 10 "$url" > /dev/null 2>&1; then
            echo "[$(date +%H:%M:%S)] GET $path -> SUCCESS"
        else
            echo "[$(date +%H:%M:%S)] GET $path -> FAILED"
        fi
    fi
}

# Simulate user behavior
simulate_user() {
    local user_id=$1
    local requests=0

    while true; do
        # Random action and service selection
        action=$((RANDOM % 30))

        # All traffic goes through the gateway and routes to service-a
        # Service-a will call service-b and service-c as needed
        case $action in
            0|1|2)    # 10% - Get user info (creates service chain A->B->C)
                random_user_id=$((RANDOM % 1000 + 1))
                make_request "/api/users/${random_user_id}" true
                ;;
            3|4|5)    # 10% - Get order info (creates service chain A->B->C)
                random_order_id=$((RANDOM % 5000 + 1))
                make_request "/api/orders/${random_order_id}" true
                ;;
            6|7)      # 7% - Simple hello endpoint
                make_request "/api/hello" true
                ;;
            8|9)      # 7% - Health checks
                make_request "/actuator/health" true
                ;;
            10|11)    # 7% - CPU: Prime calculation (light load)
                random_limit=$((RANDOM % 5000 + 1000))
                make_request "/api/compute/primes/${random_limit}" true
                ;;
            12)       # 3% - CPU: Prime calculation (heavy load)
                random_limit=$((RANDOM % 20000 + 10000))
                make_request "/api/compute/primes/${random_limit}" true
                ;;
            13|14)    # 7% - CPU: Hash computation (light)
                random_iterations=$((RANDOM % 5000 + 1000))
                make_request "/api/compute/hash/${random_iterations}" true
                ;;
            15)       # 3% - CPU: Hash computation (heavy)
                random_iterations=$((RANDOM % 20000 + 10000))
                make_request "/api/compute/hash/${random_iterations}" true
                ;;
            16|17)    # 7% - Memory: Small allocation (5-20MB)
                random_mb=$((RANDOM % 16 + 5))
                make_request "/api/memory/allocate/${random_mb}" true
                ;;
            18)       # 3% - Memory: Large allocation (20-50MB)
                random_mb=$((RANDOM % 31 + 20))
                make_request "/api/memory/allocate/${random_mb}" true
                ;;
            19|20)    # 7% - Memory: Process collection (small)
                random_items=$((RANDOM % 5000 + 1000))
                make_request "/api/memory/process/${random_items}" true
                ;;
            21)       # 3% - Memory: Process collection (large)
                random_items=$((RANDOM % 20000 + 10000))
                make_request "/api/memory/process/${random_items}" true
                ;;
            22|23)    # 7% - Slow: Database simulation (short)
                random_delay=$((RANDOM % 1000 + 100))
                make_request "/api/slow/database/${random_delay}" true
                ;;
            24)       # 3% - Slow: Database simulation (long)
                random_delay=$((RANDOM % 3000 + 1000))
                make_request "/api/slow/database/${random_delay}" true
                ;;
            25|26)    # 7% - Error simulation
                make_request "/api/simulate/error" true
                ;;
            27|28|29) # 10% - Simple hello to maintain good request rate
                make_request "/api/hello" true
                ;;
        esac

        requests=$((requests + 1))

        # Variable delay to simulate realistic traffic
        sleep_time=$(awk -v min=0.1 -v max=2.0 'BEGIN{srand(); print min+rand()*(max-min)}')
        sleep "$sleep_time"

        # Check if duration exceeded
        if [ -n "$END_TIME" ] && [ "$(date +%s)" -ge "$END_TIME" ]; then
            echo "[User $user_id] Completed $requests requests"
            break
        fi
    done
}

# Traffic patterns
burst_traffic() {
    echo "🔥 Generating burst traffic..."

    # Hello endpoint bursts
    for i in {1..30}; do
        make_request "/api/hello" true &
    done

    # User requests (creates service chains)
    for i in {1..10}; do
        random_user_id=$((RANDOM % 1000 + 1))
        make_request "/api/users/${random_user_id}" true &
    done

    # Order requests (creates service chains)
    for i in {1..10}; do
        random_order_id=$((RANDOM % 5000 + 1))
        make_request "/api/orders/${random_order_id}" true &
    done

    # CPU intensive
    for i in {1..5}; do
        random_limit=$((RANDOM % 5000 + 1000))
        make_request "/api/compute/primes/${random_limit}" true &
    done

    # Memory intensive
    for i in {1..5}; do
        random_items=$((RANDOM % 5000 + 1000))
        make_request "/api/memory/process/${random_items}" true &
    done

    wait
    echo "✓ Burst complete"
}

steady_traffic() {
    echo "📊 Generating steady traffic pattern..."

    # Start concurrent users
    for i in $(seq 1 "$CONCURRENT_USERS"); do
        simulate_user "$i" &
    done

    # Wait for all background jobs
    wait
}

spike_pattern() {
    echo "⚡ Generating traffic spike..."

    # Normal load
    for i in {1..10}; do
        make_request "/api/hello" true &
    done
    sleep 2

    # Spike - mix of endpoints including resource-intensive ones
    echo "  Creating service chain requests..."
    for i in {1..20}; do
        random_user_id=$((RANDOM % 1000 + 1))
        make_request "/api/users/${random_user_id}" true &
    done
    for i in {1..20}; do
        random_order_id=$((RANDOM % 5000 + 1))
        make_request "/api/orders/${random_order_id}" true &
    done

    echo "  Creating CPU-intensive requests..."
    for i in {1..15}; do
        random_limit=$((RANDOM % 10000 + 5000))
        make_request "/api/compute/primes/${random_limit}" true &
    done
    for i in {1..10}; do
        random_iterations=$((RANDOM % 10000 + 5000))
        make_request "/api/compute/hash/${random_iterations}" true &
    done

    echo "  Creating memory-intensive requests..."
    for i in {1..15}; do
        random_items=$((RANDOM % 10000 + 5000))
        make_request "/api/memory/process/${random_items}" true &
    done
    for i in {1..10}; do
        random_mb=$((RANDOM % 30 + 10))
        make_request "/api/memory/allocate/${random_mb}" true &
    done

    echo "  Creating slow requests..."
    for i in {1..10}; do
        random_delay=$((RANDOM % 1000 + 500))
        make_request "/api/slow/database/${random_delay}" true &
    done

    wait

    echo "✓ Spike complete"
}

# Main execution
echo "Starting traffic generation via Istio gateway..."
echo "Press Ctrl+C to stop"
echo

# Calculate end time
if [ "$DURATION" != "0" ]; then
    END_TIME=$(($(date +%s) + DURATION))
    export END_TIME
    echo "Will run until $(date -d "@$END_TIME" +%H:%M:%S)"
    echo
fi

# Initial burst to warm up
echo "1. Warm-up burst..."
burst_traffic
sleep 5

# Generate traffic with different patterns
if [ "$DURATION" = "0" ]; then
    echo "Running in continuous mode..."
    while true; do
        steady_traffic
    done
else
    echo "2. Starting steady traffic for ${DURATION}s..."
    echo

    # Launch background monitoring
    {
        while [ "$(date +%s)" -lt "$END_TIME" ]; do
            sleep 30
            elapsed=$(($(date +%s) - (END_TIME - DURATION)))
            remaining=$((DURATION - elapsed))
            echo "⏱  ${elapsed}s elapsed, ${remaining}s remaining..."
        done
    } &

    # Run steady traffic
    steady_traffic

    echo
    echo "✓ Traffic generation complete!"
fi

echo
echo "=== Check Your Metrics ==="
echo "Prometheus: http://localhost:9090"
echo "  Try queries:"
echo "    - rate(istio_requests_total[1m])"
echo "    - histogram_quantile(0.95, rate(istio_request_duration_milliseconds_bucket[5m]))"
echo
echo "Grafana: http://localhost:3000 (admin/admin)"
echo "  Check the Istio dashboards for service mesh metrics"
echo
echo "Kiali: Check for service topology and traffic visualization"
echo "  See distributed traces and service dependencies"
echo
echo "Jaeger: http://localhost:16686"
echo "  Select 'service-a', 'service-b', or 'service-c' to see distributed traces"
echo "  Traces now include Istio sidecar spans"
echo
