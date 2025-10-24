# Gateway Service Setup

## Overview

The gateway service acts as a unified entry point for both Python mock services and Java microservices. It routes HTTP traffic and creates distributed traces across the entire service mesh.

## Architecture

```
Traffic Generator → Gateway Service (NodePort 30080)
                         ↓
                    ┌────┴────┐
                    ↓         ↓
            Python Services  Java Services
            ├─ user-service   ├─ service-a
            ├─ product-service│    ↓
            ├─ order-service  └─ service-b
            ├─ inventory      │    ↓
            └─ payment        └─ service-c
```

## Endpoints

### Python Mock Service Endpoints
- `GET /health` - Health check
- `GET /api/data` - Get service data
- `POST /api/action` - Perform action with downstream calls
- `GET /api/slow` - Slow endpoint (0.5-2s latency)
- `GET /api/error` - Error endpoint (returns 500)
- `GET /metrics` - Prometheus metrics

### Java Service Proxy Endpoints
- `GET /api/hello` → service-a `/api/hello`
- `GET /api/users/{userId}` → service-a `/api/users/{userId}` → service-b → service-c
- `GET /api/orders/{orderId}` → service-a `/api/orders/{orderId}` → service-b → service-c
- `GET /actuator/health` → service-a `/actuator/health`

## Distributed Tracing

### Java Service Chain
```
Gateway → Service-A → Service-B → Service-C
```

Example trace for `/api/users/123`:
1. Gateway receives request
2. Gateway forwards to Service-A at `http://service-a.services.svc.cluster.local/api/users/123`
3. Service-A processes and calls Service-B at `http://service-b.services.svc.cluster.local/api/user/123`
4. Service-B processes and calls Service-C at `http://service-c.services.svc.cluster.local/api/data/user/123`
5. Service-C returns data → Service-B → Service-A → Gateway → Client

All spans are exported to Jaeger via OTLP.

## Service Configuration

### Gateway Service
- **Type**: NodePort
- **Port**: 80 (internal), 30080 (external)
- **Image**: `mock-service:latest`
- **Replicas**: 2
- **Resources**:
  - CPU: 50m request, 100m limit
  - Memory: 64Mi request, 128Mi limit

### Java Services
Each Java service is instrumented with OpenTelemetry Java agent:
- **Service-A**: Entry point (port 8080)
- **Service-B**: Middle tier (port 8081)
- **Service-C**: Data layer (port 8082)

## Accessing the Gateway

### From Outside Cluster (localhost)
```bash
# Using NodePort (default for Kind)
curl http://localhost:30080/api/hello

# Test Java user endpoint
curl http://localhost:30080/api/users/123

# Test Java order endpoint
curl http://localhost:30080/api/orders/456
```

### From Inside Cluster
```bash
# Using service DNS
curl http://gateway-service.services.svc.cluster.local/api/hello

# Short form from same namespace
curl http://gateway-service/api/hello
```

## Rebuilding the Gateway

After modifying `services/mock-services/app.py`:

```bash
# 1. Build the Docker image
cd services/mock-services
docker build -t mock-service:latest .

# 2. Load into Kind cluster (all nodes)
docker save mock-service:latest | docker exec -i monitoring-demo-control-plane ctr -n k8s.io images import -
docker save mock-service:latest | docker exec -i monitoring-demo-worker ctr -n k8s.io images import -
docker save mock-service:latest | docker exec -i monitoring-demo-worker2 ctr -n k8s.io images import -

# 3. Restart gateway pods
kubectl rollout restart deployment/gateway-service -n services

# 4. Wait for rollout to complete
kubectl rollout status deployment/gateway-service -n services

# 5. Verify
curl http://localhost:30080/api/hello
```

## Troubleshooting

### Gateway Returns 404 for Java Endpoints

**Check if Java services are running:**
```bash
kubectl get pods -n services | grep service-
```

**Test direct access to Service-A:**
```bash
kubectl run curl-test --image=curlimages/curl:latest --rm -i --restart=Never -n services -- \
  curl -s http://service-a/api/hello
```

**Check gateway logs:**
```bash
kubectl logs -n services -l app=gateway-service --tail=50
```

### Gateway Code Not Updated After Rebuild

**Verify image is loaded in Kind:**
```bash
docker exec monitoring-demo-control-plane crictl images | grep mock-service
```

**Check if pods are using new image:**
```bash
kubectl describe pod -n services -l app=gateway-service | grep Image:
```

**Force pod recreation:**
```bash
kubectl delete pods -n services -l app=gateway-service
```

### Java Services Can't Connect to Jaeger

**Check Jaeger collector service:**
```bash
kubectl get svc jaeger-collector -n monitoring
```

**Verify endpoint:**
```bash
kubectl get endpoints jaeger-collector -n monitoring
```

**Test connectivity from Java pod:**
```bash
kubectl exec -n services deploy/service-a -- \
  nc -zv jaeger-collector.monitoring.svc.cluster.local 4317
```

### No Traces Appearing in Jaeger

**Check OTLP endpoint in Java services:**
```bash
kubectl get deployment service-a -n services -o yaml | grep OTEL_EXPORTER
```

Should show:
```yaml
- name: OTEL_EXPORTER_OTLP_TRACES_ENDPOINT
  value: "http://jaeger-collector.monitoring.svc.cluster.local:4317"
```

**Check Jaeger collector logs:**
```bash
kubectl logs -n monitoring -l app=jaeger --tail=50 | grep -i span
```

## Monitoring Gateway

### Prometheus Metrics

Gateway exposes metrics at `/metrics`:

```bash
# Scrape metrics
curl http://localhost:30080/metrics

# Key metrics:
# - http_requests_total{method, endpoint, status}
# - http_request_duration_seconds{method, endpoint}
# - downstream_requests_total{service, status}
# - business_events_total{event_type, status}
```

### Prometheus Configuration

Gateway service has annotations for automatic discovery:
```yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8080"
  prometheus.io/path: "/metrics"
```

### View in Prometheus

```
# Request rate
rate(http_requests_total{app="gateway-service"}[1m])

# Latency percentiles
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))

# Error rate
rate(http_requests_total{app="gateway-service",status=~"5.."}[1m])
```

## Environment Variables

Gateway service supports:
- `SERVICE_NAME`: Service identifier (default: "gateway-service")
- `SERVICE_PORT`: HTTP port (default: 8080)
- `OTEL_EXPORTER_OTLP_ENDPOINT`: OTLP collector endpoint
- `DOWNSTREAM_SERVICES`: Comma-separated list of downstream services to call

## Health Checks

```bash
# Gateway health
curl http://localhost:30080/health

# Java service health (through gateway)
curl http://localhost:30080/actuator/health

# Direct Java service health
kubectl exec -n services deploy/service-a -- \
  wget -qO- http://localhost:8080/actuator/health
```

## Load Testing

Generate load with the traffic generator:

```bash
# Default: 5 concurrent users, 5 minutes
./scripts/generate-traffic.sh

# High load: 20 concurrent users, 10 minutes
CONCURRENT_USERS=20 DURATION=600 ./scripts/generate-traffic.sh

# Continuous load
DURATION=0 ./scripts/generate-traffic.sh
```

Traffic distribution includes:
- 19% to Python `/api/data`
- 12% to Java `/api/users/{id}`
- 12% to Java `/api/orders/{id}`
- 6% to Java `/api/hello`
- 12% to Java `/actuator/health`
- Plus other endpoints

## Viewing Distributed Traces

1. Open Jaeger UI: http://localhost:16686
2. Select service: **gateway-service** or **service-a**
3. Click "Find Traces"
4. Look for traces with multiple spans showing:
   - gateway-service → service-a → service-b → service-c

Example trace:
```
gateway-service: GET /api/users/123 (total: 150ms)
  └─ service-a: GET /api/users/123 (100ms)
      └─ service-b: GET /api/user/123 (80ms)
          └─ service-c: GET /api/data/user/123 (50ms)
```
