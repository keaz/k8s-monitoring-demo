# Traffic Generator for K8s Monitoring Demo

This script generates realistic traffic patterns to both Python mock services and Java microservices for testing monitoring, metrics, and distributed tracing.

## Overview

The `generate-traffic.sh` script creates traffic to:
- **Python Mock Services**: `/api/data`, `/api/action`, `/api/slow`, `/api/error`, `/health`
- **Java Microservices**: `/api/hello`, `/api/users/{id}`, `/api/orders/{id}`, `/actuator/health`

Traffic flows through the gateway service which routes requests to the appropriate backends, creating distributed traces across multiple services.

## Prerequisites

1. **Kubernetes cluster running** with services deployed
2. **Gateway service accessible** (via NodePort or port-forward)
3. **Java services deployed**: service-a, service-b, service-c

## Running the Traffic Generator

### Option 1: Using NodePort (Recommended)

If you're using Kind or a cluster that supports NodePort:

```bash
# The gateway is already exposed on NodePort 30080
./scripts/generate-traffic.sh
```

Default settings:
- Gateway URL: `http://localhost:30080`
- Duration: 300 seconds (5 minutes)
- Concurrent users: 5

### Option 2: With Port-Forward

If NodePort is not accessible:

```bash
# In terminal 1: Port-forward the gateway service
kubectl port-forward -n services svc/gateway-service 30080:80

# In terminal 2: Run the traffic generator
./scripts/generate-traffic.sh
```

### Option 3: Direct to Java Services

To send traffic directly to Java Service-A (bypassing gateway):

```bash
# In terminal 1: Port-forward Service-A
kubectl port-forward -n services svc/service-a 8080:80

# In terminal 2: Run traffic generator
GATEWAY_URL=http://localhost:8080 ./scripts/generate-traffic.sh
```

## Customization

### Environment Variables

```bash
# Custom gateway URL
GATEWAY_URL=http://my-cluster-ip:30080 ./scripts/generate-traffic.sh

# Run for 10 minutes
DURATION=600 ./scripts/generate-traffic.sh

# Continuous mode (runs forever)
DURATION=0 ./scripts/generate-traffic.sh

# More concurrent users (higher load)
CONCURRENT_USERS=10 ./scripts/generate-traffic.sh

# Combine multiple options
GATEWAY_URL=http://localhost:8080 DURATION=600 CONCURRENT_USERS=20 ./scripts/generate-traffic.sh
```

## Traffic Distribution

The script simulates realistic user behavior with the following distribution:

| Endpoint | Traffic % | Description |
|----------|-----------|-------------|
| `/api/data` | 19% | Python mock service data endpoint |
| `/api/users/{id}` | 12% | Java service chain (A→B→C) for user info |
| `/api/orders/{id}` | 12% | Java service chain (A→B→C) for orders |
| `/api/hello` | 6% | Simple Java endpoint |
| `/api/action` | 12% | Python service with downstream calls |
| `/health` | 12% | Python health checks |
| `/actuator/health` | 12% | Java health checks |
| `/api/slow` | 6% | Slow endpoint (0.5-2s latency) |
| `/api/error` | 6% | Error endpoint (500 status) |

## Traffic Patterns

### 1. Warm-up Burst
Initial burst of 50 requests across different endpoints

### 2. Steady Traffic
Simulates concurrent users with variable delays (0.1-2s) between requests

### 3. Traffic Spike (available via spike_pattern function)
Sudden spike of 100 concurrent requests

## What Gets Generated

### Distributed Traces
- **Gateway → Service-A → Service-B → Service-C** (Java microservices)
- **Gateway → Mock Services** (Python services with downstream calls)
- Traces are sent to Jaeger via OTLP

### Metrics
- HTTP request counts by endpoint and status code
- Request duration histograms
- Downstream service call metrics
- Business event counters

### Logs
- Structured logs from all services
- Request/response logging
- Error tracking

## Verifying Traffic

### Check Prometheus Metrics
```bash
# Port-forward Prometheus
kubectl port-forward -n monitoring svc/prometheus 9090:9090

# Open browser to http://localhost:9090
# Query: rate(http_requests_total[1m])
```

### Check Jaeger Traces
```bash
# Port-forward Jaeger
kubectl port-forward -n monitoring svc/jaeger-query 16686:16686

# Open browser to http://localhost:16686
# Select 'gateway-service' or 'service-a' to see traces
```

### Check Grafana Dashboards
```bash
# Port-forward Grafana
kubectl port-forward -n monitoring svc/grafana 3000:3000

# Open browser to http://localhost:3000
# Create dashboards with request rates and latencies
```

## Troubleshooting

### Gateway Not Accessible
```bash
# Check if gateway service is running
kubectl get svc -n services gateway-service

# Check if pods are ready
kubectl get pods -n services -l app=gateway-service

# Check gateway logs
kubectl logs -n services -l app=gateway-service --tail=50
```

### Java Services Not Responding
```bash
# Check Java service status
kubectl get pods -n services -l app=service-a

# Check service-a logs
kubectl logs -n services -l app=service-a --tail=50

# Test direct access to service-a
kubectl port-forward -n services svc/service-a 8080:80
curl http://localhost:8080/api/hello
```

### No Traffic Showing in Monitoring
```bash
# Verify OTEL collector is running
kubectl get pods -n monitoring -l app=otel-collector

# Check OTEL collector logs
kubectl logs -n monitoring -l app=otel-collector --tail=50

# Verify Jaeger is receiving traces
kubectl logs -n monitoring -l app=jaeger-collector --tail=50
```

## Advanced Usage

### Custom Traffic Pattern

Edit the script to create custom patterns:

```bash
# Create a specific test scenario
custom_pattern() {
    echo "Running custom test..."
    for i in {1..100}; do
        make_request "/api/users/42" "GET" true &
    done
    wait
}
```

### Load Testing

For higher load testing, increase concurrent users and reduce delays:

```bash
CONCURRENT_USERS=50 DURATION=300 ./scripts/generate-traffic.sh
```

## Rebuilding Gateway with Java Proxy

After updating the gateway to proxy Java services:

```bash
# Rebuild the gateway image
cd services/mock-services
docker build -t mock-service:latest .

# Load into Kind (if using Kind)
kind load docker-image mock-service:latest

# Restart gateway pods
kubectl rollout restart deployment/gateway-service -n services
```

## Expected Results

After running for 5 minutes with default settings, you should see:
- **~2000-3000 total requests** across all endpoints
- **Distributed traces** showing service-to-service calls
- **Metrics** showing request rates, latencies, and error rates
- **Some errors** (intentional, ~10% on /api/action endpoint)
- **Variable latencies** on /api/slow endpoint

## Notes

- The script uses `curl` for simplicity and observability
- Random delays simulate realistic user behavior
- Random user IDs (1-1000) and order IDs (1-5000) are generated
- Error endpoints are included for testing error tracking
- All traffic is instrumented with OpenTelemetry
