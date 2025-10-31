#!/bin/bash

# Generate Kafka traffic for testing
DURATION=${DURATION:-60}
NAMESPACE="${NAMESPACE:-services}"

# Service URL (internal cluster URL)
SERVICE_A_URL="http://service-a.${NAMESPACE}.svc.cluster.local:80"

echo "=== Generating Kafka Traffic ==="
echo "Duration: ${DURATION} seconds"
echo "Target: ${SERVICE_A_URL}/api/kafka/send/"
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "ERROR: kubectl not found. Please install kubectl."
    exit 1
fi

# Check if services are running
echo "Checking if services are running..."
if ! kubectl get deployment service-a -n $NAMESPACE &> /dev/null; then
    echo "ERROR: service-a not found in namespace $NAMESPACE"
    echo "Please deploy the services first:"
    echo "  ./scripts/build-and-deploy.sh"
    exit 1
fi

echo "✓ Services are running"
echo ""

START_TIME=$(date +%s)
COUNT=0

while true; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))

    if [ $ELAPSED -ge $DURATION ]; then
        break
    fi

    MESSAGE="Message-$(date +%s%N)"

    # Use kubectl exec to make request from inside the cluster
    RESPONSE=$(kubectl exec -n $NAMESPACE deploy/service-a -- wget -q -O- "${SERVICE_A_URL}/api/kafka/send/${MESSAGE}" 2>&1)

    if [ $? -eq 0 ]; then
        COUNT=$((COUNT + 1))
        echo "[$COUNT] Sent: $MESSAGE - Response: $RESPONSE"
    else
        echo "[$COUNT] Failed to send message"
    fi

    sleep 1
done

echo ""
echo "=== Traffic Generation Complete ==="
echo "Total messages sent: $COUNT"
echo ""
echo "View the traces in Jaeger: http://localhost:16686"
echo "  1. Select 'service-a' from the Service dropdown"
echo "  2. Click 'Find Traces'"
echo "  3. Click on any trace to see the full Kafka flow"
