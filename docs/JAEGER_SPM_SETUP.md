# Jaeger Service Performance Monitoring (SPM) - Production Setup

## Overview

This guide explains the production-ready Jaeger configuration with Service Performance Monitoring (SPM) enabled. SPM generates RED metrics (Rate, Errors, Duration) from trace data, providing service-level performance insights.

## Architecture

### Production Jaeger Setup

```
Applications (instrumented with OTEL)
        ↓
OpenTelemetry Collector
        ↓ (OTLP gRPC/HTTP)
Jaeger All-in-One (Production Mode)
├─ Collector (ingests traces)
├─ Query UI (trace visualization)
├─ Badger Storage (persistent)
└─ SPM Metrics → Prometheus
        ↓
   Grafana Dashboards
```

### Key Features

✅ **Persistent Storage**: Badger backend with 7-day TTL
✅ **Service Performance Monitoring**: RED metrics from traces
✅ **Multiple Protocols**: OTLP (gRPC/HTTP), Jaeger native, Zipkin
✅ **Prometheus Integration**: SPM metrics scraped by Prometheus
✅ **Production-Ready**: Health checks, resource limits, persistent volumes

## Components

### Jaeger All-in-One

- **Image**: `jaegertracing/all-in-one:1.50`
- **Storage**: Badger (persistent, 7-day retention)
- **SPM**: Enabled with Prometheus metrics backend
- **Replicas**: 1 (Badger limitation - single writer)

**Why All-in-One for Production?**

For small-to-medium production workloads (< 10k spans/sec), the all-in-one deployment with persistent storage is:
- ✅ Simpler to manage
- ✅ Lower resource overhead
- ✅ Fully featured (collector, query, SPM)
- ✅ Sufficient for most use cases

For large-scale production (> 10k spans/sec), consider:
- Elasticsearch/Cassandra backend
- Separate collector/query components
- Horizontal scaling

## Deployment Files

### Main Configuration

**`kubernetes/base/jaeger/jaeger-production.yaml`**
- Jaeger all-in-one deployment with SPM
- Persistent volume for badger storage
- Health/readiness probes
- Resource limits

**`kubernetes/base/jaeger/jaeger-config.yaml`**
- Sampling strategies per service
- UI configuration with links
- Service-specific sampling rates

### Services Exposed

| Service | Type | Port | Purpose |
|---------|------|------|---------|
| **jaeger-query** | NodePort | 30002 | Web UI access |
| **jaeger-collector** | ClusterIP | 4317, 4318 | OTLP ingestion |
| **jaeger-collector** | ClusterIP | 14250, 14268 | Jaeger native |
| **jaeger-collector** | ClusterIP | 9411 | Zipkin compatible |
| **jaeger-collector** | ClusterIP | 14269 | Admin/metrics |

## Service Performance Monitoring (SPM)

### What is SPM?

SPM generates metrics from trace spans, providing:

**Rate (R)**
- Requests per second by service
- Operation-level call rates
- Traffic patterns

**Errors (E)**
- Error rates by service
- Failed operations
- Status code distribution

**Duration (D)**
- Latency percentiles (P50, P95, P99)
- Slowest operations
- Performance degradation

### SPM Configuration

```yaml
env:
- name: METRICS_STORAGE_TYPE
  value: "prometheus"
```

This enables Jaeger to export span metrics in Prometheus format.

### SPM Metrics Generated

Jaeger exposes these metrics at `http://jaeger:14269/metrics`:

```promql
# Call rates
calls_total{service_name="gateway", operation="GET /api/users"}

# Call duration histogram
duration_bucket{service_name="user-service", operation="findUser", le="100000000"}  # nanoseconds

# Span metrics
jaeger_tracer_started_spans_total
jaeger_tracer_finished_spans_total
```

## Prometheus Integration

### Scrape Configuration

Prometheus is configured to scrape Jaeger metrics via pod annotations:

```yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "14269"
  prometheus.io/path: "/metrics"
```

Prometheus job: `kubernetes-pods` automatically discovers and scrapes Jaeger.

### Verify Prometheus Scraping

```bash
# Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus 9090:9090 &
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.app=="jaeger")'

# Query SPM metrics
curl 'http://localhost:9090/api/v1/query?query=calls_total'
```

## Grafana Dashboards

### SPM Dashboard

Location: `grafana-dashboards/jaeger-spm-dashboard.json`

**Panels:**

1. **Request Rate by Service**
   - Total requests per second
   - Per-operation breakdown
   - Trend over time

2. **Error Rate by Service**
   - Error percentage
   - Failed operations
   - Error spikes

3. **Latency Percentiles**
   - P50, P95, P99 latencies
   - Per-service performance
   - SLO tracking

4. **Top Operations**
   - Highest request rates
   - Busiest endpoints
   - Performance hotspots

### Import Dashboard

**Option 1: Via UI**
1. Open Grafana: http://localhost:3000
2. Login (admin/admin)
3. Dashboards → Import
4. Upload `grafana-dashboards/jaeger-spm-dashboard.json`
5. Select "Prometheus" datasource
6. Click "Import"

**Option 2: Via API**
```bash
curl -X POST http://admin:admin@localhost:3000/api/dashboards/db \
  -H "Content-Type: application/json" \
  -d @grafana-dashboards/jaeger-spm-dashboard.json
```

## Sampling Strategies

### Configuration

File: `kubernetes/base/jaeger/jaeger-config.yaml`

```yaml
sampling.json: |
  {
    "service_strategies": [
      {
        "service": "gateway",
        "type": "probabilistic",
        "param": 1.0  # 100% sampling
      }
    ],
    "default_strategy": {
      "type": "probabilistic",
      "param": 0.1  # 10% sampling for others
    }
  }
```

### Sampling Types

**Probabilistic**
- `param: 1.0` = 100% of traces
- `param`: 0.1` = 10% of traces
- Good for: High-volume services

**Rate Limiting**
```yaml
"type": "ratelimiting"
"param": 100  # max 100 traces/second
```
- Good for: Controlling costs

**Adaptive**
- Automatically adjusts based on traffic
- Requires Jaeger Agent

### Update Sampling

```bash
# Edit config
kubectl edit configmap jaeger-sampling-config -n monitoring

# Restart Jaeger to apply
kubectl rollout restart deployment/jaeger -n monitoring
```

## Storage Configuration

### Badger Settings

```yaml
env:
- name: SPAN_STORAGE_TYPE
  value: "badger"
- name: BADGER_EPHEMERAL
  value: "false"
- name: BADGER_DIRECTORY_VALUE
  value: "/badger/data"
- name: BADGER_DIRECTORY_KEY
  value: "/badger/key"
- name: BADGER_SPAN_STORE_TTL
  value: "168h"  # 7 days
```

### Storage Volume

```yaml
volumes:
- name: badger-storage
  persistentVolumeClaim:
    claimName: jaeger-storage  # 10Gi PVC
```

### Retention Policy

- **Default**: 7 days (168 hours)
- **Configurable**: via `BADGER_SPAN_STORE_TTL`
- **Automatic cleanup**: Old spans deleted automatically

### Storage Monitoring

```bash
# Check storage usage
kubectl exec -n monitoring deployment/jaeger -- du -sh /badger

# Monitor via metrics
curl http://localhost:14269/metrics | grep badger
```

## Accessing Jaeger

### Jaeger UI

**Local Access:**
```bash
# Already exposed via NodePort
open http://localhost:30002
```

**Features:**
- Search traces by service, operation, tags
- View trace timeline
- Analyze span details
- Compare traces
- SPM metrics (Monitor tab)

### Service Performance (Monitor Tab)

In Jaeger UI:
1. Click "Monitor" in top navigation
2. Select service
3. View RED metrics:
   - Request rate
   - Error rate
   - P95 latency

## Sending Traces to Jaeger

### From Applications

**OTLP (OpenTelemetry Protocol)**
```python
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

tracer_provider = TracerProvider()
otlp_exporter = OTLPSpanExporter(
    endpoint="http://jaeger-collector:4317",
    insecure=True
)
tracer_provider.add_span_processor(BatchSpanProcessor(otlp_exporter))
trace.set_tracer_provider(tracer_provider)

tracer = trace.get_tracer(__name__)
with tracer.start_as_current_span("my-operation"):
    # your code here
    pass
```

**Via OTEL Collector (Recommended)**
```yaml
# Already configured in otel-collector-config.yaml
exporters:
  otlp/jaeger:
    endpoint: jaeger-collector:4317
    tls:
      insecure: true

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [otlp/jaeger]
```

### Verify Traces

```bash
# Check if Jaeger is receiving traces
kubectl logs -n monitoring deployment/jaeger | grep "spans received"

# Check OTEL Collector
kubectl logs -n monitoring deployment/otel-collector | grep jaeger
```

## Troubleshooting

### No Traces Appearing

**Check 1: OTEL Collector → Jaeger connection**
```bash
kubectl logs -n monitoring deployment/otel-collector | grep -i error
```

**Check 2: Jaeger collector port**
```bash
kubectl get svc -n monitoring jaeger-collector
# Should show port 4317 (OTLP gRPC)
```

**Check 3: Application instrumentation**
```bash
# Verify app is sending to OTEL Collector
kubectl logs -n services deployment/gateway | grep -i trace
```

### SPM Metrics Not Showing

**Check 1: Prometheus scraping**
```bash
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.app=="jaeger")'
```

**Check 2: SPM enabled**
```bash
kubectl get deployment jaeger -n monitoring -o yaml | grep METRICS_STORAGE_TYPE
# Should show: value: "prometheus"
```

**Check 3: Query metrics directly**
```bash
kubectl port-forward -n monitoring deployment/jaeger 14269:14269 &
curl http://localhost:14269/metrics | grep calls_total
```

### High Memory Usage

**Solution 1: Reduce retention**
```bash
kubectl set env deployment/jaeger -n monitoring BADGER_SPAN_STORE_TTL=72h
```

**Solution 2: Reduce sampling**
```yaml
# Edit jaeger-sampling-config
"param": 0.1  # Sample only 10%
```

**Solution 3: Increase resources**
```yaml
resources:
  limits:
    memory: 2Gi  # Increase from 1Gi
```

### Storage Full

```bash
# Check disk usage
kubectl exec -n monitoring deployment/jaeger -- df -h /badger

# Option 1: Increase PVC size
kubectl edit pvc jaeger-storage -n monitoring

# Option 2: Reduce retention
kubectl set env deployment/jaeger -n monitoring BADGER_SPAN_STORE_TTL=48h
```

## Production Recommendations

### 1. Resource Planning

**Badger Storage Size:**
- **Light**: 5Gi (< 1k spans/sec, 7-day retention)
- **Medium**: 20Gi (1k-5k spans/sec, 7-day retention)
- **Heavy**: 50Gi+ (> 5k spans/sec, 7-day retention)

**Memory:**
- Base: 512Mi
- Add 100Mi per 1k spans/sec
- Add 200Mi for SPM

**CPU:**
- Base: 300m
- Add 100m per 1k spans/sec

### 2. High Availability

For production HA, consider:

**Option A: Elasticsearch Backend**
```yaml
env:
- name: SPAN_STORAGE_TYPE
  value: "elasticsearch"
- name: ES_SERVER_URLS
  value: "http://elasticsearch:9200"
```

Benefits:
- Horizontal scaling
- Multiple replicas
- Better query performance
- Distributed storage

**Option B: Cassandra Backend**
```yaml
env:
- name: SPAN_STORAGE_TYPE
  value: "cassandra"
- name: CASSANDRA_SERVERS
  value: "cassandra-0.cassandra,cassandra-1.cassandra"
```

Benefits:
- High write throughput
- Linear scalability
- Multi-datacenter

### 3. Monitoring Jaeger Itself

**Key Metrics:**
```promql
# Spans received rate
rate(jaeger_collector_spans_received_total[1m])

# Spans dropped (backpressure)
rate(jaeger_collector_spans_dropped_total[1m])

# Queue length
jaeger_collector_queue_length

# Storage latency
histogram_quantile(0.95, rate(jaeger_collector_save_latency_bucket[5m]))
```

**Alerts:**
```yaml
- alert: JaegerHighSpanDropRate
  expr: rate(jaeger_collector_spans_dropped_total[5m]) > 100
  annotations:
    summary: "Jaeger is dropping spans due to backpressure"

- alert: JaegerStorageFull
  expr: badger_disk_usage_bytes / badger_disk_size_bytes > 0.85
  annotations:
    summary: "Jaeger storage is 85% full"
```

### 4. Security

**Enable TLS:**
```yaml
env:
- name: COLLECTOR_OTLP_GRPC_TLS_ENABLED
  value: "true"
- name: COLLECTOR_OTLP_GRPC_TLS_CERT
  value: "/certs/tls.crt"
- name: COLLECTOR_OTLP_GRPC_TLS_KEY
  value: "/certs/tls.key"
```

**Authentication:**
```yaml
env:
- name: QUERY_BASE_PATH
  value: "/"
- name: QUERY_BEARER_TOKEN_PROPAGATION
  value: "true"
```

**Network Policies:**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: jaeger-network-policy
spec:
  podSelector:
    matchLabels:
      app: jaeger
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: otel-collector
    ports:
    - port: 4317
```

### 5. Backup and Disaster Recovery

**Badger Backup:**
```bash
# Create snapshot
kubectl exec -n monitoring deployment/jaeger -- \
  curl -X POST http://localhost:14269/admin/backup

# Copy to external storage
kubectl cp monitoring/jaeger-xxx:/badger/backup ./jaeger-backup-$(date +%Y%m%d).tar.gz

# Upload to S3/GCS
aws s3 cp ./jaeger-backup-*.tar.gz s3://my-backups/jaeger/
```

**Automated Backups:**
```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: jaeger-backup
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: alpine
            command:
            - sh
            - -c
            - |
              apk add curl
              curl -X POST http://jaeger:14269/admin/backup
              # Copy and upload logic
```

## Migration to Elasticsearch

When outgrowing Badger:

**Step 1: Deploy Elasticsearch**
```bash
helm install elasticsearch elastic/elasticsearch -n monitoring
```

**Step 2: Update Jaeger**
```yaml
env:
- name: SPAN_STORAGE_TYPE
  value: "elasticsearch"
- name: ES_SERVER_URLS
  value: "http://elasticsearch-master:9200"
- name: ES_NUM_SHARDS
  value: "3"
- name: ES_NUM_REPLICAS
  value: "1"
```

**Step 3: Scale horizontally**
```yaml
spec:
  replicas: 3  # Can now scale with Elasticsearch
```

## Summary

Your production-ready Jaeger setup includes:

✅ **Persistent Storage**: 10Gi Badger with 7-day retention
✅ **Service Performance Monitoring**: RED metrics from traces
✅ **Prometheus Integration**: SPM metrics scraped automatically
✅ **Multiple Protocols**: OTLP, Jaeger native, Zipkin
✅ **Grafana Dashboards**: Pre-built SPM visualization
✅ **Sampling Configuration**: Per-service sampling strategies
✅ **Health Monitoring**: Probes and metrics
✅ **Resource Limits**: Production-appropriate limits

### Access Points

| Service | URL | Purpose |
|---------|-----|---------|
| **Jaeger UI** | http://localhost:30002 | Trace search and visualization |
| **Jaeger SPM** | http://localhost:30002/monitor | Service performance metrics |
| **Grafana SPM Dashboard** | http://localhost:3000 | Custom SPM visualization |
| **Prometheus** | http://localhost:9090 | Query raw SPM metrics |

### Next Steps

1. **Import SPM Dashboard**: `grafana-dashboards/jaeger-spm-dashboard.json`
2. **Generate Traffic**: `./scripts/generate-traffic.sh`
3. **View Traces**: Open http://localhost:30002
4. **Analyze Performance**: Check Monitor tab in Jaeger UI
5. **Set up Alerts**: Create alerts on SPM metrics

## References

- [Jaeger Documentation](https://www.jaegertracing.io/docs/)
- [Service Performance Monitoring](https://www.jaegertracing.io/docs/latest/spm/)
- [Badger Storage](https://www.jaegertracing.io/docs/latest/deployment/#badger---local-storage)
- [OTLP Specification](https://opentelemetry.io/docs/reference/specification/protocol/otlp/)
- [SPM Dashboard](./jaeger-spm-dashboard.json)
