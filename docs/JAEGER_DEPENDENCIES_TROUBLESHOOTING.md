# Jaeger Service Dependencies Troubleshooting Guide

## Overview

Jaeger's System Architecture (Dependencies) view shows service-to-service relationships derived from trace data. If you see "No service dependencies found," this guide will help you diagnose and fix the issue.

## How Service Dependencies Work

### Dependency Graph Generation

Jaeger builds the service dependency graph from:

1. **Span References**: Parent-child relationships between spans
2. **Service Names**: Extracted from span tags
3. **Time Aggregation**: Dependencies are calculated over a time window

### Expected Flow

```
Application Traces
    ↓ (with parent-child span references)
OpenTelemetry Collector
    ↓
Jaeger Collector
    ↓
Jaeger Storage (Badger)
    ↓
Jaeger Query (reads traces)
    ↓
Dependencies API (aggregates relationships)
    ↓
System Architecture UI
```

## Current Configuration

### Service Call Chain

Your services are configured with these relationships:

```
gateway-service
├── order-service
│   ├── user-service
│   ├── product-service
│   └── payment-service
│       └── notification-service
├── user-service
└── product-service
    └── inventory-service
```

### OTEL Instrumentation

Services use:
- **FlaskInstrumentor**: Auto-instruments Flask endpoints
- **RequestsInstrumentor**: Auto-instruments HTTP client calls
- **OTLP Exporter**: Sends traces to OTEL Collector

## Troubleshooting Steps

### Step 1: Verify Services Are Calling Each Other

**Check service logs for downstream calls:**

```bash
# Check gateway service logs
kubectl logs -n services deployment/gateway-service | grep "Called"

# Should see output like:
# Called order-service: 200 in 0.045s
# Called user-service: 200 in 0.023s
```

**Verify environment variables:**

```bash
# Check gateway downstream services
kubectl get deployment gateway-service -n services -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="DOWNSTREAM_SERVICES")].value}'

# Should output: order-service,user-service,product-service
```

**Test downstream calls manually:**

```bash
# Call /api/action which triggers downstream calls
curl -X POST http://localhost:30080/api/action

# Response should include downstream_results:
# {
#   "service": "gateway-service",
#   "downstream_results": {
#     "order-service": "success",
#     "user-service": "success"
#   }
# }
```

### Step 2: Verify Traces Are Being Generated

**Check OTEL Collector is receiving traces:**

```bash
# Check OTEL Collector logs
kubectl logs -n monitoring deployment/otel-collector | grep -i "traces"

# Check metrics
curl http://localhost:8889/metrics | grep otelcol_receiver_accepted_spans
```

**Check Jaeger has traces:**

```bash
# Port forward Jaeger
kubectl port-forward -n monitoring svc/jaeger-query 16686:16686 &

# Query for recent traces
curl -s 'http://localhost:16686/api/traces?service=gateway-service&limit=10' | python3 -m json.tool | grep traceID
```

**Verify traces in Jaeger UI:**

1. Open http://localhost:30002
2. Select "gateway-service" from dropdown
3. Click "Find Traces"
4. You should see multiple traces
5. Click on a trace to view details

### Step 3: Check Span Structure

**Examine a trace for proper structure:**

1. Open a trace in Jaeger UI
2. Look for:
   - **Multiple services** in the trace (gateway → order → user)
   - **Parent-child relationships** (nested spans)
   - **Span references** showing connections

**Required span structure:**

```
Trace ID: abc123
├─ Span: gateway-service/POST /api/action
   ├─ Span: gateway-service → order-service
   │  └─ Span: order-service/GET /api/data
   │     ├─ Span: order-service → user-service
   │     │  └─ Span: user-service/GET /api/data
   │     └─ Span: order-service → payment-service
   │        └─ Span: payment-service/GET /api/data
   └─ Span: gateway-service → user-service
      └─ Span: user-service/GET /api/data
```

### Step 4: Verify Span Context Propagation

**Check if trace context is being propagated:**

```bash
# Enable debug logging in a service
kubectl set env deployment/gateway-service -n services LOG_LEVEL=DEBUG

# Check logs for trace context
kubectl logs -n services deployment/gateway-service | grep "trace"
```

**Ensure services use RequestsInstrumentor:**

This is already configured in `app.py`:
```python
from opentelemetry.instrumentation.requests import RequestsInstrumentor
RequestsInstrumentor().instrument()
```

This automatically propagates trace context via HTTP headers.

### Step 5: Generate Sufficient Traffic

Dependencies appear after **multiple traces** accumulate.

**Generate test traffic:**

```bash
# Quick burst
for i in {1..100}; do
  curl -s -X POST http://localhost:30080/api/action > /dev/null &
done
wait

# Continuous traffic
./scripts/generate-traffic.sh
```

**Monitor trace generation:**

```bash
# Watch Jaeger collector metrics
watch -n 5 'kubectl logs -n monitoring deployment/jaeger --tail=20 | grep "spans"'
```

### Step 6: Check Dependencies API

**Query dependencies directly:**

```bash
# Get current timestamp in milliseconds
END_TS=$(python3 -c "import time; print(int(time.time() * 1000))")

# Query last hour of dependencies
curl -s "http://localhost:30002/api/dependencies?endTs=${END_TS}&lookback=3600000" | python3 -m json.tool

# Expected output:
# {
#   "data": [
#     {
#       "parent": "gateway-service",
#       "child": "order-service",
#       "callCount": 42
#     },
#     ...
#   ]
# }
```

**If empty:**
- Wait 5-10 minutes after generating traffic
- Dependencies are calculated asynchronously
- May require cache refresh

### Step 7: Check Jaeger Configuration

**Verify SPM and dependencies settings:**

```bash
# Check Jaeger environment variables
kubectl get deployment jaeger -n monitoring -o yaml | grep -A 2 "PROMETHEUS"
```

**Should include:**
```yaml
- name: PROMETHEUS_SERVER_URL
  value: http://prometheus.monitoring.svc.cluster.local:9090
- name: PROMETHEUS_QUERY_SUPPORT_SPANMETRICS_CONNECTOR
  value: "true"
```

### Step 8: Restart Components

**If all else fails, restart the stack:**

```bash
# Restart OTEL Collector
kubectl rollout restart deployment/otel-collector -n monitoring

# Restart Jaeger
kubectl rollout restart deployment/jaeger -n monitoring

# Restart services
kubectl rollout restart deployment -n services

# Wait for pods to be ready
kubectl wait --for=condition=ready pod -l app=jaeger -n monitoring --timeout=60s
kubectl wait --for=condition=ready pod -n services --all --timeout=60s

# Generate new traffic
for i in {1..50}; do curl -s -X POST http://localhost:30080/api/action > /dev/null & done; wait
```

## Common Issues and Solutions

### Issue 1: No Downstream Services Called

**Symptom**: Traces show only single service
**Cause**: DOWNSTREAM_SERVICES environment variable empty
**Solution**:

```bash
# Check current config
kubectl get deployment gateway-service -n services -o jsonpath='{.spec.template.spec.containers[0].env}'

# Update if needed (already configured in mock-services.yaml)
kubectl set env deployment/gateway-service -n services DOWNSTREAM_SERVICES=order-service,user-service,product-service
```

### Issue 2: Traces Not Showing Parent-Child Relationships

**Symptom**: Traces are flat (no nesting)
**Cause**: Trace context not propagated
**Solution**:

Verify RequestsInstrumentor is used (already configured):
```python
from opentelemetry.instrumentation.requests import RequestsInstrumentor
RequestsInstrumentor().instrument()
```

### Issue 3: Dependencies Show After Long Delay

**Symptom**: Dependencies appear only after 10-15 minutes
**Cause**: Normal behavior - Jaeger aggregates over time
**Solution**:
- Be patient
- Generate continuous traffic
- Dependencies update periodically

### Issue 4: Only Some Dependencies Appear

**Symptom**: Only gateway→order visible, others missing
**Cause**: Not enough traffic to all service paths
**Solution**:

```bash
# Test specific service paths
curl -X POST http://localhost:30080/api/action  # Triggers all downstream calls
curl http://localhost:30080/api/data           # May trigger some calls

# Check which paths trigger downstream
kubectl logs -n services deployment/gateway-service | grep "downstream"
```

### Issue 5: Dependencies Disappear

**Symptom**: Dependencies visible, then gone
**Cause**: Time window selection in Jaeger UI
**Solution**:
- Adjust time range in Jaeger UI
- Select "Last Hour" or "Last 6 Hours"
- Dependencies only show for selected time range

## Verification Checklist

Use this checklist to verify everything is configured:

- [ ] Services deployed and running
  ```bash
  kubectl get pods -n services
  ```

- [ ] DOWNSTREAM_SERVICES configured for gateway
  ```bash
  kubectl get deployment gateway-service -n services -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="DOWNSTREAM_SERVICES")].value}'
  ```

- [ ] OTEL Collector running
  ```bash
  kubectl get pods -n monitoring -l app=otel-collector
  ```

- [ ] Jaeger running
  ```bash
  kubectl get pods -n monitoring -l app=jaeger
  ```

- [ ] Services calling each other
  ```bash
  kubectl logs -n services deployment/gateway-service | grep "Called"
  ```

- [ ] Traces in Jaeger
  - Open http://localhost:30002
  - Select gateway-service
  - Click "Find Traces"
  - Should see multiple traces

- [ ] Traces have multiple services
  - Click on a trace
  - Should see spans from gateway, order, user, etc.

- [ ] Generated sufficient traffic
  ```bash
  # At least 50-100 requests
  for i in {1..100}; do curl -s -X POST http://localhost:30080/api/action > /dev/null & done; wait
  ```

- [ ] Waited 5-10 minutes
  - Dependencies are calculated asynchronously

- [ ] Checked correct time range in Jaeger UI
  - Click on time picker
  - Select "Last Hour"

## Alternative: Manual Dependency Visualization

If Jaeger dependencies still don't appear, you can visualize using Prometheus metrics:

**ServiceGraph Metrics** (from OTEL Collector):

```promql
# Service call rates
rate(traces_service_graph_request_total[5m])

# Service latencies
histogram_quantile(0.95, rate(traces_service_graph_request_duration_seconds_bucket[5m]))
```

**Create Grafana Dashboard**:

1. Import `grafana-dashboards/jaeger-spm-dashboard.json`
2. Add panels for:
   - Call rates between services
   - Latency percentiles
   - Error rates

**Use Jaeger Trace Search**:

1. Search for traces manually
2. Examine each trace to see service calls
3. Build mental model of dependencies

## Debug Commands Summary

```bash
# 1. Check service configuration
kubectl get deployment gateway-service -n services -o jsonpath='{.spec.template.spec.containers[0].env}'

# 2. Generate traffic
for i in {1..100}; do curl -s -X POST http://localhost:30080/api/action > /dev/null & done; wait

# 3. Check service logs
kubectl logs -n services deployment/gateway-service | grep "Called"

# 4. Verify traces in Jaeger
curl -s 'http://localhost:16686/api/traces?service=gateway-service&limit=5' | python3 -m json.tool

# 5. Query dependencies API
END_TS=$(python3 -c "import time; print(int(time.time() * 1000))")
curl -s "http://localhost:30002/api/dependencies?endTs=${END_TS}&lookback=3600000" | python3 -m json.tool

# 6. Check OTEL Collector metrics
curl -s http://localhost:8889/metrics | grep otelcol_receiver

# 7. Restart everything
kubectl rollout restart deployment -n services
kubectl rollout restart deployment -n monitoring
```

## Expected Timeline

| Time | Expected State |
|------|----------------|
| T+0 | Deploy services, generate traffic |
| T+1m | Traces appearing in Jaeger |
| T+2m | Can view individual traces with multiple services |
| T+5m | Dependencies starting to appear |
| T+10m | Full dependency graph visible |

## Success Criteria

You'll know dependencies are working when:

1. ✅ Jaeger UI → System Architecture shows service graph
2. ✅ Nodes include: gateway, order, user, product, payment, inventory, notification
3. ✅ Arrows show directionality (gateway → order)
4. ✅ Clicking edges shows call volumes
5. ✅ Service graph updates with new data

## Still Having Issues?

### Check Service Mesh

If using a service mesh (Istio, Linkerd):
- Service mesh may be interfering with trace propagation
- Check mesh configuration for tracing compatibility

### Check Badger Storage

```bash
# Check Jaeger storage health
kubectl logs -n monitoring deployment/jaeger | grep -i "badger\|storage"

# Check disk space
kubectl exec -n monitoring deployment/jaeger -- df -h /badger
```

### Enable Debug Logging

**Jaeger:**
```bash
kubectl set env deployment/jaeger -n monitoring LOG_LEVEL=debug
kubectl logs -n monitoring deployment/jaeger --tail=100
```

**OTEL Collector:**
Already has debug logging enabled in configuration.

## Additional Resources

- **Jaeger Documentation**: https://www.jaegertracing.io/docs/latest/spm/
- **OpenTelemetry Context Propagation**: https://opentelemetry.io/docs/reference/specification/context/api-propagators/
- **Service Graph**: https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/connector/servicegraphconnector

## Summary

Service dependencies in Jaeger require:

1. ✅ **Proper service instrumentation** (configured)
2. ✅ **Inter-service communication** (configured)
3. ✅ **Trace context propagation** (configured)
4. ✅ **Multiple traces over time** (requires traffic generation)
5. ⏳ **Time for aggregation** (5-10 minutes)

**Most common solution**: Generate more traffic and wait 5-10 minutes!

```bash
# Run this and check back in 10 minutes:
./scripts/generate-traffic.sh
```

Then refresh the Jaeger System Architecture page and select "Last Hour" time range.
