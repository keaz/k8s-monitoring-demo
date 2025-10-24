# Traffic Simulation & Demo - Complete Guide

## Overview

You now have a complete, working inter-service communication demo with full observability! This setup includes 7 microservices that communicate with each other, generating realistic metrics and distributed traces.

## What's Deployed

### Architecture

```
                    ┌─────────────────────────────────────┐
                    │      Client / Load Generator        │
                    └──────────────────┬──────────────────┘
                                       │
                         HTTP (localhost:30080)
                                       │
                                       ▼
                    ┌──────────────────────────────────────┐
                    │       gateway-service (2 pods)       │
                    │  Entry point for all requests        │
                    └──────────────────┬───────────────────┘
                                       │
                    ┌──────────────────┼───────────────────┐
                    │                  │                   │
                    ▼                  ▼                   ▼
         ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
         │  user-service   │  │ product-service │  │  order-service  │
         │    (2 pods)     │  │    (2 pods)     │  │    (2 pods)     │
         └─────────────────┘  └────────┬────────┘  └────────┬────────┘
                                       │                    │
                                       ▼                    ├───┐
                            ┌──────────────────┐            │   │
                            │ inventory-service│            │   │
                            │    (2 pods)      │◄───────────┘   │
                            └──────────────────┘                │
                                                                ▼
                                                     ┌─────────────────┐
                                                     │ payment-service │
                                                     │    (2 pods)     │
                                                     └────────┬────────┘
                                                              │
                                                              ▼
                                                  ┌───────────────────────┐
                                                  │ notification-service  │
                                                  │      (1 pod)          │
                                                  └───────────────────────┘
```

### Services Summary

| Service | Pods | Role | Instrumentation |
|---------|------|------|-----------------|
| gateway-service | 2 | API Gateway | ✅ Prometheus ✅ OTEL |
| user-service | 2 | User Management | ✅ Prometheus ✅ OTEL |
| product-service | 2 | Product Catalog | ✅ Prometheus ✅ OTEL |
| inventory-service | 2 | Inventory Mgmt | ✅ Prometheus ✅ OTEL |
| order-service | 2 | Order Processing | ✅ Prometheus ✅ OTEL |
| payment-service | 2 | Payment Processing | ✅ Prometheus ✅ OTEL |
| notification-service | 1 | Notifications | ✅ Prometheus ✅ OTEL |

**Total: 13 pods providing 7 services**

## Quick Start

### 1. Verify Everything is Running

```bash
# Check services
kubectl get pods -n services

# All pods should be Running
```

### 2. Test the Services

```bash
./scripts/test-services.sh
```

Expected: All 4 tests pass ✓

### 3. Generate Traffic

```bash
# Start traffic generation (runs for 5 minutes)
./scripts/generate-traffic.sh
```

This simulates realistic user behavior with varying request patterns.

### 4. View the Results

**Prometheus** (http://localhost:9090):
```promql
rate(http_requests_total[1m])
```

**Grafana** (http://localhost:3000):
- Login: admin/admin
- Explore → Select Prometheus
- Build dashboards

**Jaeger** (http://localhost:16686):
- Select "gateway-service"
- Click "Find Traces"
- Explore distributed traces!

## Traffic Generation Options

### Option 1: Automated Script (Recommended)

```bash
# Default: 5 minutes, 5 concurrent users
./scripts/generate-traffic.sh

# Custom duration and users
DURATION=600 CONCURRENT_USERS=10 ./scripts/generate-traffic.sh

# Continuous mode (run until Ctrl+C)
DURATION=0 ./scripts/generate-traffic.sh
```

**Traffic Pattern:**
- 40% Normal data fetches
- 20% Complex multi-service actions
- 20% Health checks
- 10% Slow operations
- 10% Error scenarios

### Option 2: Manual Commands

```bash
# Simple request
curl http://localhost:30080/api/data

# Complex request (creates deep trace)
curl -X POST http://localhost:30080/api/action

# Generate 100 requests
for i in {1..100}; do
  curl -s http://localhost:30080/api/data > /dev/null
  sleep 0.1
done
```

### Option 3: Continuous Background Traffic

```bash
# Run in background
nohup ./scripts/generate-traffic.sh > /tmp/traffic.log 2>&1 &

# Check it's running
tail -f /tmp/traffic.log

# Stop it
pkill -f generate-traffic.sh
```

## Available Endpoints

### Gateway Service (localhost:30080)

| Endpoint | Method | Purpose | Creates Traces |
|----------|--------|---------|----------------|
| `/health` | GET | Health check | ❌ |
| `/api/data` | GET | Fetch data, may call downstream | ✅ |
| `/api/action` | POST | Complex operation, calls multiple services | ✅✅✅ |
| `/api/slow` | GET | Slow operation (0.5-2s delay) | ✅ |
| `/api/error` | GET | Returns error (for demo) | ✅ |
| `/metrics` | GET | Prometheus metrics | ❌ |

## Monitoring the Demo

### Prometheus Queries

**Request Rate:**
```promql
# Total requests/sec
sum(rate(http_requests_total[1m]))

# By service
sum by (service_name) (rate(http_requests_total[1m]))

# By endpoint
sum by (endpoint) (rate(http_requests_total[1m]))
```

**Latency:**
```promql
# P95 latency
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))

# By service
histogram_quantile(0.95,
  sum by (le, service_name) (rate(http_request_duration_seconds_bucket[5m]))
)
```

**Errors:**
```promql
# Error rate
rate(http_requests_total{status="500"}[1m])

# Error percentage
sum(rate(http_requests_total{status="500"}[1m])) /
sum(rate(http_requests_total[1m])) * 100
```

**Inter-Service Communication:**
```promql
# Downstream call rate
rate(downstream_requests_total[1m])

# By target service
sum by (service) (rate(downstream_requests_total[1m]))

# Downstream errors
rate(downstream_requests_total{status="error"}[1m])
```

### Jaeger Trace Analysis

1. **Open Jaeger**: http://localhost:16686

2. **Find Traces**:
   - Service: gateway-service
   - Operation: All
   - Lookback: 1 hour
   - Click "Find Traces"

3. **Explore a Trace**:
   - Click any trace
   - See span hierarchy
   - Check timings
   - View tags and logs

4. **Look for**:
   - Deep traces (gateway → order → product → inventory)
   - Slow spans (highlighted)
   - Error spans (red)
   - Service dependencies

### Grafana Dashboards

1. **Access**: http://localhost:3000 (admin/admin)

2. **Create Dashboard**:
   - Click "+" → Dashboard
   - Add visualization
   - Select Prometheus
   - Add queries

3. **Suggested Panels**:

**Request Rate:**
```promql
sum by (service_name) (rate(http_requests_total[1m]))
```

**Latency Distribution:**
```promql
histogram_quantile(0.50, rate(http_request_duration_seconds_bucket[5m]))
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))
histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))
```

**Error Rate:**
```promql
sum(rate(http_requests_total{status="500"}[1m]))
```

**Service Map** (use Prometheus query):
```promql
sum by (service, downstream_service) (rate(downstream_requests_total[1m]))
```

## Demo Scenarios

### Scenario 1: Normal Load

```bash
# Generate moderate traffic
DURATION=180 CONCURRENT_USERS=5 ./scripts/generate-traffic.sh
```

**Show**:
- Steady metrics in Prometheus
- Distributed traces in Jaeger
- Service dependencies
- Normal latency

### Scenario 2: Traffic Spike

```bash
# Burst of requests
for i in {1..200}; do
  curl -s -X POST http://localhost:30080/api/action > /dev/null &
done
```

**Show**:
- Spike in request rate graph
- Increased latency
- Resource usage (if monitoring enabled)

### Scenario 3: Error Injection

```bash
# Generate errors
for i in {1..100}; do
  curl -s http://localhost:30080/api/error > /dev/null
  sleep 0.1
done
```

**Show**:
- Error rate increase in Prometheus
- Red error spans in Jaeger
- Error percentage calculation

### Scenario 4: Service Degradation

```bash
# Reduce inventory service replicas
kubectl scale deployment inventory-service -n services --replicas=1

# Generate traffic
./scripts/generate-traffic.sh
```

**Show**:
- Increased latency to product-service
- Traces showing slow inventory-service spans
- Impact on upstream services

## Understanding the Data Flow

### API Call: GET /api/data

**Request Flow:**
```
Client
  → gateway-service
    → product-service (70% chance)
      → inventory-service
```

**Metrics Generated:**
- `http_requests_total` (gateway, product, inventory)
- `http_request_duration_seconds` (all services)
- `downstream_requests_total` (gateway→product, product→inventory)

**Traces Created:**
- 1 trace with 1-3 spans

### API Call: POST /api/action

**Request Flow:**
```
Client
  → gateway-service
    → order-service
      → user-service
      → product-service
        → inventory-service
      → payment-service
        → notification-service
    → user-service
    → product-service
      → inventory-service
```

**Metrics Generated:**
- Multiple `http_requests_total` counters
- Latency histograms for each service
- `downstream_requests_total` for each hop
- `business_events_total` counters

**Traces Created:**
- 1 trace with up to 10 spans showing full service mesh

## Metrics Explained

### Standard HTTP Metrics

```python
http_requests_total{method="GET",endpoint="/api/data",status="200"}
```
- Counter: Total requests
- Labels: method, endpoint, status
- Use: Calculate request rate

```python
http_request_duration_seconds_bucket{le="0.5"}
```
- Histogram: Request duration distribution
- Use: Calculate percentiles (P50, P95, P99)

### Inter-Service Metrics

```python
downstream_requests_total{service="product-service",status="200"}
```
- Counter: Downstream service calls
- Labels: target service, status
- Use: Track service dependencies

### Business Metrics

```python
business_events_total{event_type="action",status="success"}
```
- Counter: Business events
- Labels: event type, status
- Use: Business-level monitoring

## Troubleshooting

### Services Not Responding

```bash
# Check pod status
kubectl get pods -n services

# Check logs
kubectl logs -n services deployment/gateway-service

# Describe pod
kubectl describe pod -n services <pod-name>
```

### No Traffic Reaching Services

```bash
# Port forward to gateway
kubectl port-forward -n services svc/gateway-service 8080:80

# Test directly
curl http://localhost:8080/health
```

### Prometheus Not Scraping

```bash
# Check annotations
kubectl get pod -n services <pod-name> -o yaml | grep -A 5 annotations

# Check Prometheus targets
# Open http://localhost:9090/targets
# Look for services namespace
```

### No Traces in Jaeger

```bash
# Check OTEL Collector
kubectl logs -n monitoring deployment/otel-collector

# Check Jaeger
kubectl logs -n monitoring deployment/jaeger

# Verify OTEL endpoint
kubectl get svc -n monitoring otel-collector
```

## Cleanup and Rebuild

### Remove Services Only

```bash
kubectl delete -f kubernetes/base/services/mock-services.yaml
```

### Rebuild and Redeploy

```bash
# Make changes to services/mock-services/app.py
# Rebuild and deploy
./scripts/deploy-demo.sh
```

### Complete Cleanup

```bash
# Delete everything
kind delete cluster --name monitoring-demo

# Start fresh (run all setup from beginning)
```

## Advanced Topics

### Custom Metrics

Add to `app.py`:
```python
CUSTOM_COUNTER = Counter('my_custom_metric', 'Description')
CUSTOM_COUNTER.inc()
```

### Custom Spans

Add to `app.py`:
```python
with tracer.start_as_current_span("custom_operation") as span:
    span.set_attribute("key", "value")
    # Your code here
```

### Scale Services

```bash
# Scale up
kubectl scale deployment gateway-service -n services --replicas=5

# Scale down
kubectl scale deployment notification-service -n services --replicas=0
```

### View Real-Time Logs

```bash
# All services
stern -n services '.*'

# Specific service
kubectl logs -f -n services deployment/order-service
```

## Summary

You have a complete, production-like microservices demo with:

✅ **7 Services** with realistic inter-service communication
✅ **13 Pods** distributed across workers
✅ **Prometheus Metrics** on all services
✅ **Distributed Tracing** with OpenTelemetry
✅ **Traffic Generator** for realistic load
✅ **Full Observability** - metrics, traces, logs

**Use this to demonstrate:**
- Microservices architecture
- Service mesh patterns
- Distributed tracing
- Metrics collection
- Performance monitoring
- Error tracking
- Service dependencies

**Access Points:**
- Services: http://localhost:30080
- Prometheus: http://localhost:9090
- Grafana: http://localhost:3000
- Jaeger: http://localhost:16686

For detailed demo walkthrough, see **DEMO_GUIDE.md**
