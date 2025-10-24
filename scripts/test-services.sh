#!/bin/bash

# Quick test script for mock services

echo "=== Testing Mock Services ==="
echo

# Get the control plane container IP
NODE_IP=$(docker inspect monitoring-demo-control-plane | grep '"IPAddress"' | head -1 | awk -F'"' '{print $4}')

if [ -z "$NODE_IP" ]; then
    echo "ERROR: Could not find cluster node IP"
    echo "Using port-forward instead..."
    echo

    # Use port-forward as fallback
    echo "Starting port-forward to gateway-service..."
    kubectl port-forward -n services svc/gateway-service 30080:80 &
    PF_PID=$!
    sleep 3

    GATEWAY_URL="http://localhost:30080"
else
    GATEWAY_URL="http://$NODE_IP:30080"
fi

echo "Gateway URL: $GATEWAY_URL"
echo

# Test health endpoint
echo "1. Testing health endpoint..."
if response=$(curl -s "$GATEWAY_URL/health"); then
    echo "✓ Health check:"
    echo "$response" | python3 -m json.tool 2>/dev/null || echo "$response"
else
    echo "✗ Health check failed"
fi

echo

# Test data endpoint
echo "2. Testing data endpoint..."
if response=$(curl -s "$GATEWAY_URL/api/data"); then
    echo "✓ Data endpoint:"
    echo "$response" | python3 -m json.tool 2>/dev/null | head -30 || echo "$response" | head -30
else
    echo "✗ Data endpoint failed"
fi

echo

# Test action endpoint (creates distributed traces)
echo "3. Testing action endpoint (creates traces)..."
if response=$(curl -s -X POST "$GATEWAY_URL/api/action"); then
    echo "✓ Action endpoint:"
    echo "$response" | python3 -m json.tool 2>/dev/null || echo "$response"
else
    echo "✗ Action endpoint failed"
fi

echo

# Test metrics endpoint
echo "4. Testing metrics endpoint..."
if response=$(curl -s "$GATEWAY_URL/metrics" | head -20); then
    echo "✓ Metrics endpoint (first 20 lines):"
    echo "$response"
else
    echo "✗ Metrics endpoint failed"
fi

echo

echo "=== Service Test Complete ==="
echo
echo "Generate continuous traffic:"
echo "  ./scripts/generate-traffic.sh"
echo
echo "View in monitoring tools:"
echo "  Prometheus: http://localhost:9090"
echo "  Grafana:    http://localhost:3000"
echo "  Jaeger:     http://localhost:16686"

# Cleanup port-forward if we started one
if [ -n "$PF_PID" ]; then
    kill $PF_PID 2>/dev/null
fi
