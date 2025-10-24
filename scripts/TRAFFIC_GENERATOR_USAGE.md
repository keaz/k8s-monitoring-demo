# Traffic Generator Usage Guide

The `generate-traffic.sh` script simulates realistic traffic patterns to your Java services for testing monitoring, tracing, and metrics collection.

## Overview

The script generates traffic to three Java services:
- **service-a** (port 80): Primary service that chains to service-b
- **service-b** (port 8081): Middle service that chains to service-c
- **service-c** (port 8082): Leaf service with database connections

## Quick Start

### Run with default settings (5 minutes, 5 concurrent users)
```bash
./scripts/generate-traffic.sh
```

### Run with custom duration
```bash
DURATION=600 ./scripts/generate-traffic.sh  # Run for 10 minutes
```

### Run with more concurrent users
```bash
CONCURRENT_USERS=10 ./scripts/generate-traffic.sh  # 10 simulated users
```

### Run indefinitely (until Ctrl+C)
```bash
DURATION=0 ./scripts/generate-traffic.sh
```

### Combine options
```bash
DURATION=300 CONCURRENT_USERS=20 ./scripts/generate-traffic.sh
```

## Traffic Patterns

The script generates the following types of requests:

### Service Chain Requests (20%)
Creates distributed traces across multiple services:
- `/api/users/{id}` - Service A → B → C (with database)
- `/api/orders/{id}` - Service A → B → C (with database)

### Simple Requests (17%)
- `/api/hello` - Fast response endpoints
- `/actuator/health` - Health check endpoints

### CPU-Intensive Requests (20%)
- `/api/compute/primes/{limit}` - Prime number calculation
- `/api/compute/hash/{iterations}` - Hash computation

### Memory-Intensive Requests (20%)
- `/api/memory/allocate/{sizeMb}` - Memory allocation
- `/api/memory/process/{itemCount}` - Large collection processing

### Slow Requests (10%)
- `/api/slow/database/{delayMs}` - Simulated database delays

### Error Simulation (13%)
- `/api/simulate/error` - Random errors for testing

## Traffic Phases

1. **Warm-up Burst** - Initial burst to populate caches and warm up services
2. **Steady Traffic** - Continuous load with variable delays between requests
3. **Random Distribution** - Realistic mix of different request types

## Viewing Results

After running the traffic generator, check:

### Prometheus (http://localhost:9090)
Query examples:
```promql
# Request rate
rate(calls_total[1m])

# 95th percentile latency
histogram_quantile(0.95, rate(duration_milliseconds_bucket[5m]))

# Error rate
rate(calls_total{status_code="STATUS_CODE_ERROR"}[5m])
```

### Jaeger (http://localhost:16686)
- Select service: `service-a`, `service-b`, or `service-c`
- View distributed traces to see service chains
- Check **Monitor** tab for Service Performance Monitoring (SPM):
  - Request rates
  - Error rates
  - Latency percentiles (P50, P95, P99)

### Grafana (http://localhost:3000)
- Username: `admin`
- Password: `admin`
- Browse pre-configured dashboards

### VictoriaMetrics (http://localhost:8428)
Alternative long-term metrics storage

## Implementation Details

The script uses `kubectl exec` to make requests from inside the cluster, avoiding the need for external ingress or NodePort configurations. Requests are executed from the `service-a` pod to simulate internal cluster traffic.

## Troubleshooting

### Services not found
```bash
kubectl get deployments -n services
# Ensure service-a, service-b, service-c are running
```

### Permission issues
```bash
kubectl auth can-i create pods/exec -n services
# Ensure you have exec permissions
```

### Check active traffic
```bash
# Watch service-a logs
kubectl logs -f -n services deploy/service-a

# Watch all pods
kubectl logs -f -n services -l app=service-a
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DURATION` | 300 | Duration in seconds (0 for infinite) |
| `CONCURRENT_USERS` | 5 | Number of concurrent simulated users |
| `NAMESPACE` | services | Kubernetes namespace |

## Examples

### Demo scenario (quick 2-minute burst)
```bash
DURATION=120 CONCURRENT_USERS=3 ./scripts/generate-traffic.sh
```

### Load testing (high concurrency)
```bash
DURATION=600 CONCURRENT_USERS=20 ./scripts/generate-traffic.sh
```

### Background continuous load
```bash
DURATION=0 CONCURRENT_USERS=5 ./scripts/generate-traffic.sh &
# Remember to kill it later: pkill -f generate-traffic
```

### Spike testing
The script includes a `spike_pattern` function that creates sudden traffic spikes. This is automatically called during normal operation but can be customized by editing the script.
