# Demo Guide - Inter-Service Communication Monitoring

This guide walks you through demonstrating the complete monitoring stack with inter-service communication.

## What's Running

### Microservices Architecture

```
Client Request
      ↓
┌──────────────────┐
│ gateway-service  │ (Entry point - exposed on port 30080)
└──────────────────┘
      ↓
      ├─→ user-service
      ├─→ product-service → inventory-service
      └─→ order-service → user-service
                       → product-service → inventory-service
                       → payment-service → notification-service
```

### Deployed Services

| Service | Replicas | Purpose | Downstream Services |
|---------|----------|---------|---------------------|
| **gateway-service** | 2 | API Gateway | order, user, product |
| **user-service** | 2 | User management | none |
| **product-service** | 2 | Product catalog | inventory |
| **inventory-service** | 2 | Stock management | none |
| **order-service** | 2 | Order processing | user, product, payment |
| **payment-service** | 2 | Payment processing | notification |
| **notification-service** | 1 | Notifications | none |

Total: 13 pods across 7 services

## Quick Test

### 1. Test Individual Service

```bash
# Run the test script
./scripts/test-services.sh
```

Expected output:
- ✓ Health check returns service status
- ✓ Data endpoint returns service-specific data
- ✓ Action endpoint triggers inter-service calls
- ✓ Metrics endpoint shows Prometheus metrics

### 2. Manual API Tests

```bash
# Health check
curl http://localhost:30080/health

# Get data (may call downstream services)
curl http://localhost:30080/api/data

# Perform action (creates distributed trace)
curl -X POST http://localhost:30080/api/action

# View Prometheus metrics
curl http://localhost:30080/metrics
```

## Generate Traffic for Demo

### Option 1: Automated Traffic Generator

```bash
# Run for 5 minutes with 5 concurrent users
./scripts/generate-traffic.sh

# Run for 10 minutes with 10 concurrent users
DURATION=600 CONCURRENT_USERS=10 ./scripts/generate-traffic.sh

# Run continuously (Ctrl+C to stop)
DURATION=0 ./scripts/generate-traffic.sh
```

The traffic generator simulates realistic user behavior:
- 40% - Regular data fetches
- 20% - Complex actions (multi-service traces)
- 20% - Health checks
- 10% - Slow operations
- 10% - Error scenarios

### Option 2: Manual Traffic Generation

```bash
# Generate 100 requests
for i in {1..100}; do
    curl -s http://localhost:30080/api/data > /dev/null
    sleep 0.1
done

# Generate requests with errors
for i in {1..50}; do
    curl -s http://localhost:30080/api/error > /dev/null
    sleep 0.2
done

# Generate slow requests
for i in {1..20}; do
    curl -s http://localhost:30080/api/slow > /dev/null &
done
wait
```

### Option 3: Load Testing with Apache Bench

```bash
# Install apache bench
sudo dnf install httpd-tools

# 1000 requests, 10 concurrent
ab -n 1000 -c 10 http://localhost:30080/api/data

# POST requests
ab -n 500 -c 5 -p /dev/null -T application/json \
   http://localhost:30080/api/action
```

## View Metrics in Prometheus

### 1. Access Prometheus

Open http://localhost:9090

### 2. Try These Queries

**Request Rate:**
```promql
# Requests per second
rate(http_requests_total[1m])

# Requests per second by service
sum by (service_name) (rate(http_requests_total[1m]))

# Requests per second by endpoint
sum by (endpoint) (rate(http_requests_total[1m]))
```

**Request Duration:**
```promql
# P95 latency across all services
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))

# P95 latency by service
histogram_quantile(0.95,
  sum by (le, service_name) (rate(http_request_duration_seconds_bucket[5m]))
)

# Average request duration
rate(http_request_duration_seconds_sum[5m]) /
rate(http_request_duration_seconds_count[5m])
```

**Error Rate:**
```promql
# Error rate (5xx responses)
rate(http_requests_total{status=~"5.."}[1m])

# Error percentage
sum(rate(http_requests_total{status=~"5.."}[1m])) /
sum(rate(http_requests_total[1m])) * 100
```

**Downstream Service Calls:**
```promql
# Downstream request rate
rate(downstream_requests_total[1m])

# Downstream errors
rate(downstream_requests_total{status="error"}[1m])

# Downstream requests by service
sum by (service) (rate(downstream_requests_total[1m]))
```

**Business Metrics:**
```promql
# Business events
rate(business_events_total[1m])

# Success vs error events
sum by (status) (rate(business_events_total[1m]))

# Events by type
sum by (event_type) (rate(business_events_total[1m]))
```

### 3. Explore Targets

1. Go to Status → Targets
2. See all services being scraped
3. Verify all targets are "UP"

## Create Grafana Dashboards

### 1. Access Grafana

Open http://localhost:3000 (admin/admin)

### 2. Create Request Rate Dashboard

1. Click "+" → Dashboard → Add visualization
2. Select "Prometheus" datasource
3. Enter query:
   ```promql
   sum by (service_name) (rate(http_requests_total[1m]))
   ```
4. Panel title: "Request Rate by Service"
5. Visualization: Time series
6. Add more panels:
   - P95 Latency
   - Error Rate
   - Active Services

### 3. Import Community Dashboards

1. Click "+" → Import
2. Enter dashboard ID:
   - **3662** - Prometheus 2.0 Stats
   - **1860** - Node Exporter Full
3. Select Prometheus datasource
4. Click Import

### 4. Sample Dashboard JSON

Create a custom dashboard:

```json
{
  "dashboard": {
    "title": "Microservices Overview",
    "panels": [
      {
        "title": "Request Rate",
        "targets": [{
          "expr": "sum by (service_name) (rate(http_requests_total[1m]))"
        }]
      },
      {
        "title": "P95 Latency",
        "targets": [{
          "expr": "histogram_quantile(0.95, sum by (le, service_name) (rate(http_request_duration_seconds_bucket[5m])))"
        }]
      }
    ]
  }
}
```

## View Distributed Traces in Jaeger

### 1. Access Jaeger

Open http://localhost:16686

### 2. Explore Traces

1. **Select Service**: Choose "gateway-service" from dropdown
2. **Set Time Range**: Last 1 hour
3. **Click "Find Traces"**
4. **Select a Trace**: Click on any trace to see details

### 3. What to Look For

**Trace Structure:**
```
gateway-service
  ├── order-service
  │   ├── user-service
  │   ├── product-service
  │   │   └── inventory-service
  │   └── payment-service
  │       └── notification-service
  ├── user-service
  └── product-service
      └── inventory-service
```

**Trace Details:**
- Span duration (how long each call took)
- Service dependencies
- Error spans (red highlights)
- Tags and logs

### 4. Filter Traces

- **By duration**: Look for slow requests (>1s)
- **By tags**: Filter by specific operations
- **By errors**: Find failed requests

### 5. Service Dependencies

1. Click "System Architecture" tab
2. See visual representation of service calls
3. Identify bottlenecks

## Demo Scenarios

### Scenario 1: Normal Operations

```bash
# Generate steady traffic
DURATION=180 CONCURRENT_USERS=5 ./scripts/generate-traffic.sh
```

**Show in Prometheus:**
- Steady request rate
- Consistent latency
- Low error rate

**Show in Jaeger:**
- Successful traces
- Service communication patterns

### Scenario 2: Load Spike

```bash
# Generate burst traffic
for i in {1..200}; do
    curl -s -X POST http://localhost:30080/api/action > /dev/null &
done
wait
```

**Show in Prometheus:**
- Spike in request rate
- Increase in latency
- Resource usage spike

**Show in Grafana:**
- Request rate graph shows spike
- Latency percentiles increase

### Scenario 3: Error Conditions

```bash
# Generate errors
for i in {1..100}; do
    curl -s http://localhost:30080/api/error > /dev/null
    sleep 0.1
done
```

**Show in Prometheus:**
```promql
# Error rate increase
rate(http_requests_total{status="500"}[1m])
```

**Show in Jaeger:**
- Red error spans
- Failed traces

### Scenario 4: Slow Operations

```bash
# Generate slow requests
for i in {1..30}; do
    curl -s http://localhost:30080/api/slow > /dev/null &
done
```

**Show in Prometheus:**
```promql
# P99 latency increase
histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))
```

**Show in Jaeger:**
- Long-duration traces
- Identify slow spans

## Monitoring Best Practices Demo

### 1. Service Health

```promql
# Service availability
up{job="kubernetes-pods"}

# Request success rate
sum(rate(http_requests_total{status=~"2.."}[5m])) /
sum(rate(http_requests_total[5m]))
```

### 2. Golden Signals

**Latency:**
```promql
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))
```

**Traffic:**
```promql
sum(rate(http_requests_total[1m]))
```

**Errors:**
```promql
sum(rate(http_requests_total{status=~"5.."}[1m]))
```

**Saturation:**
```promql
# Pod CPU usage
sum(rate(container_cpu_usage_seconds_total{namespace="services"}[5m]))

# Pod memory usage
sum(container_memory_working_set_bytes{namespace="services"})
```

### 3. RED Method

**Rate:**
```promql
sum by (service_name) (rate(http_requests_total[1m]))
```

**Errors:**
```promql
sum by (service_name) (rate(http_requests_total{status=~"5.."}[1m]))
```

**Duration:**
```promql
sum by (service_name) (rate(http_request_duration_seconds_sum[1m])) /
sum by (service_name) (rate(http_request_duration_seconds_count[1m]))
```

## Troubleshooting Services

### Check Service Status

```bash
# All pods
kubectl get pods -n services

# Specific service
kubectl get pods -n services -l app=gateway-service

# Service endpoints
kubectl get svc -n services

# Pod logs
kubectl logs -n services deployment/gateway-service --tail=50

# Follow logs
kubectl logs -n services deployment/order-service -f
```

### Common Issues

**Services not responding:**
```bash
# Check pod status
kubectl describe pod -n services <pod-name>

# Check service logs
kubectl logs -n services <pod-name>

# Port forward for direct access
kubectl port-forward -n services svc/gateway-service 8080:80
curl http://localhost:8080/health
```

**Prometheus not scraping:**
```bash
# Check pod annotations
kubectl get pod -n services <pod-name> -o yaml | grep annotations -A 5

# Check Prometheus targets
# Open http://localhost:9090/targets
```

**Traces not appearing:**
```bash
# Check OTEL Collector logs
kubectl logs -n monitoring deployment/otel-collector

# Verify OTEL endpoint
kubectl get svc -n monitoring otel-collector
```

## Cleanup

```bash
# Remove all services
kubectl delete -f kubernetes/base/services/mock-services.yaml

# Or delete the entire services namespace
kubectl delete namespace services
kubectl create namespace services

# Redeploy
./scripts/deploy-demo.sh
```

## Advanced Demo Features

### 1. Service Mesh Observability

The traces show:
- Request propagation across services
- Parent-child span relationships
- Timing breakdown per service

### 2. Cascading Failures

```bash
# Watch what happens when one service has issues
kubectl scale deployment inventory-service -n services --replicas=0

# Generate traffic
./scripts/generate-traffic.sh

# Observe in Prometheus/Jaeger
```

### 3. Auto-scaling Demo

```bash
# Install metrics server
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Create HPA
kubectl autoscale deployment gateway-service -n services \
  --cpu-percent=50 --min=2 --max=10

# Generate load and watch scaling
kubectl get hpa -n services -w
```

## Summary

You now have a fully functional microservices demo with:
- ✅ 7 services with inter-service communication
- ✅ Prometheus metrics collection
- ✅ Distributed tracing with OpenTelemetry
- ✅ Grafana dashboards
- ✅ Traffic generation scripts
- ✅ Realistic error scenarios

Use this to demonstrate:
- Service mesh observability
- Distributed tracing
- Metrics collection and visualization
- Performance monitoring
- Error tracking and debugging
