# VictoriaMetrics and VictoriaTraces Setup Guide

This guide explains how to use VictoriaMetrics and VictoriaTraces alongside your existing Prometheus and Jaeger setup, including importing the VictoriaTraces Cluster dashboard (ID: 24134).

## Overview

We've enhanced the monitoring stack with:

- **VictoriaMetrics**: High-performance, cost-effective time-series database (Prometheus-compatible)
- **VictoriaTraces**: Distributed tracing backend (Jaeger-compatible)

Both run alongside your existing Prometheus and Jaeger, giving you:
- Dual storage for metrics and traces
- Better query performance for large datasets
- Specialized dashboards like the VictoriaTraces Cluster dashboard

## Architecture

```
Application Services
        ↓
OpenTelemetry Collector
        ├→ Prometheus (metrics) ──remote write──→ VictoriaMetrics
        ├→ Jaeger (traces)
        └→ VictoriaTraces (traces)
                ↓
        Grafana Datasources
        ├─ Prometheus
        ├─ VictoriaMetrics
        ├─ Jaeger
        └─ VictoriaTraces
```

## Deployment

### Step 1: Deploy VictoriaMetrics and VictoriaTraces

```bash
cd /home/Kasun/Development/RnD/Monitoring/K8S/k8s-monitoring-demo

# Make script executable
chmod +x scripts/deploy-victoriametrics.sh

# Deploy
./scripts/deploy-victoriametrics.sh
```

This script will:
1. Deploy VictoriaMetrics
2. Deploy VictoriaTraces
3. Update Prometheus config for remote write
4. Update OTEL Collector to send traces to VictoriaTraces
5. Update Grafana datasources
6. Restart affected components

### Step 2: Verify Deployment

```bash
# Check all pods are running
kubectl get pods -n monitoring

# You should see:
# - victoriametrics-xxx    1/1   Running
# - victoriatraces-xxx     1/1   Running
```

### Step 3: Verify Datasources in Grafana

1. Open Grafana: http://localhost:3000
2. Login (admin/admin)
3. Go to Configuration → Data Sources
4. You should see:
   - Prometheus (default)
   - VictoriaMetrics
   - Jaeger
   - VictoriaTraces

## Accessing the Services

| Service | URL | Purpose |
|---------|-----|---------|
| VictoriaMetrics | http://localhost:30003 | Metrics storage and queries |
| VictoriaTraces | http://localhost:30004 | Trace storage and queries |

## Import the VictoriaTraces Dashboard (ID: 24134)

### Option 1: Import via Dashboard ID

1. Open Grafana: http://localhost:3000
2. Click "+" (Create) → Import
3. Enter Dashboard ID: **24134**
4. Click "Load"
5. Configure:
   - **Name**: VictoriaTraces Cluster (or customize)
   - **Folder**: Select or create a folder
   - **VictoriaMetrics**: Select "VictoriaMetrics" datasource
6. Click "Import"

### Option 2: Import via JSON

1. Download the dashboard JSON from: https://grafana.com/grafana/dashboards/24134
2. Open Grafana: http://localhost:3000
3. Click "+" → Import
4. Click "Upload JSON file"
5. Select the downloaded file
6. Configure datasource as above
7. Click "Import"

## Generate Data for the Dashboard

The dashboard needs active trace data to display meaningful information.

### Start Traffic Generation

```bash
# Generate continuous traffic
./scripts/generate-traffic.sh

# Or run in background
nohup ./scripts/generate-traffic.sh > /tmp/traffic.log 2>&1 &
```

### Wait for Data

- Wait 2-3 minutes for traces to accumulate
- VictoriaTraces will start collecting spans
- The dashboard will populate with data

## Using the VictoriaTraces Dashboard

The dashboard (ID: 24134) shows:

### Overview Section
- **Total Traces**: Number of traces stored
- **Trace Rate**: Traces per second
- **Span Rate**: Spans per second
- **Storage Size**: Disk usage

### Performance Metrics
- **Query Latency**: How fast queries execute
- **Ingestion Rate**: Incoming traces/spans per second
- **Error Rate**: Failed operations

### Resource Usage
- **CPU Usage**: VictoriaTraces CPU consumption
- **Memory Usage**: Memory utilization
- **Disk I/O**: Read/write operations

### Top Services
- Services generating most traces
- Most active endpoints
- Error rates by service

## Querying VictoriaMetrics

VictoriaMetrics uses PromQL (Prometheus Query Language):

### In Grafana

1. Create new panel
2. Select "VictoriaMetrics" datasource
3. Use same queries as Prometheus:

```promql
# Request rate
rate(http_requests_total[1m])

# P95 latency
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))
```

### Direct API Access

```bash
# Query via API
curl 'http://localhost:30003/api/v1/query?query=up'

# Range query
curl 'http://localhost:30003/api/v1/query_range?query=rate(http_requests_total[5m])&start=now-1h&end=now&step=1m'
```

## Querying VictoriaTraces

VictoriaTraces is compatible with Jaeger API:

### In Grafana

1. Go to Explore
2. Select "VictoriaTraces" datasource
3. Search for traces by:
   - Service name
   - Operation
   - Tags
   - Time range

### Direct UI Access

Open http://localhost:30004 and use the Jaeger-compatible UI

## Advantages of VictoriaMetrics

1. **Better Performance**:
   - Faster queries on large datasets
   - Lower memory usage
   - Better compression

2. **Cost-Effective**:
   - Requires less storage
   - Lower resource requirements

3. **Prometheus Compatible**:
   - Drop-in replacement
   - Same PromQL queries
   - Remote write protocol

## Advantages of VictoriaTraces

1. **Scalable**:
   - Handles high trace volumes
   - Efficient storage

2. **Jaeger Compatible**:
   - Same API
   - Same query language
   - Works with existing instrumentation

3. **Integrated**:
   - Works seamlessly with VictoriaMetrics
   - Unified observability platform

## Comparison: Prometheus vs VictoriaMetrics

| Feature | Prometheus | VictoriaMetrics |
|---------|-----------|-----------------|
| Query Language | PromQL | PromQL (compatible) |
| Storage | Local TSDB | Optimized storage |
| Performance | Good | Excellent |
| Resource Usage | Higher | Lower |
| Scalability | Single node | Horizontal scaling |
| Remote Write | Supported | Native support |

## Comparison: Jaeger vs VictoriaTraces

| Feature | Jaeger | VictoriaTraces |
|---------|--------|----------------|
| Protocol | OTLP, Jaeger | OTLP, Jaeger, Zipkin |
| Storage | Cassandra/Elasticsearch | Native |
| Performance | Good | Better |
| Resource Usage | Higher | Lower |
| Integration | Standalone | With VictoriaMetrics |

## Monitoring VictoriaMetrics Itself

VictoriaMetrics exposes its own metrics:

```promql
# VictoriaMetrics metrics
vm_rows{type="indexdb"}              # Indexed rows
vm_data_size_bytes                   # Storage size
vm_insert_requests_total             # Write requests
vm_select_requests_total             # Read requests
```

## Monitoring VictoriaTraces Itself

This is what dashboard 24134 is for! It shows:

- Trace ingestion rate
- Storage usage
- Query performance
- Error rates

## Troubleshooting

### VictoriaMetrics Not Receiving Data

```bash
# Check Prometheus remote write
kubectl logs -n monitoring deployment/prometheus | grep "remote"

# Check VictoriaMetrics logs
kubectl logs -n monitoring deployment/victoriametrics

# Test direct write
curl -X POST http://localhost:30003/api/v1/import/prometheus \
  -d 'test_metric{job="test"} 123'
```

### VictoriaTraces Not Receiving Traces

```bash
# Check OTEL Collector logs
kubectl logs -n monitoring deployment/otel-collector | grep victoria

# Check VictoriaTraces logs
kubectl logs -n monitoring deployment/victoriatraces

# Verify endpoint
kubectl get svc -n monitoring victoriatraces
```

### Dashboard Shows No Data

1. **Wait**: Allow 2-3 minutes for data to accumulate
2. **Generate Traffic**: Run `./scripts/generate-traffic.sh`
3. **Check Time Range**: Ensure dashboard time range includes recent data
4. **Verify Datasource**: Confirm correct datasource is selected
5. **Check Queries**: Look at panel queries for errors

### Datasources Not Available in Grafana

```bash
# Restart Grafana
kubectl rollout restart deployment/grafana -n monitoring

# Check Grafana logs
kubectl logs -n monitoring deployment/grafana

# Verify config
kubectl get configmap grafana-datasources -n monitoring -o yaml
```

## Best Practices

### For Production

1. **Persistent Storage**: Use PVCs instead of emptyDir
   ```yaml
   volumes:
   - name: storage
     persistentVolumeClaim:
       claimName: victoriametrics-storage
   ```

2. **Resource Limits**: Adjust based on load
   ```yaml
   resources:
     requests:
       cpu: 1000m
       memory: 2Gi
     limits:
       cpu: 2000m
       memory: 4Gi
   ```

3. **Retention Period**: Configure based on needs
   ```yaml
   args:
     - -retentionPeriod=30d  # Keep data for 30 days
   ```

4. **High Availability**: Run multiple replicas with shared storage

### For Development/Demo

Current configuration is optimized for demo:
- EmptyDir storage (data lost on pod restart)
- Moderate resources
- 14-day retention

## Migration Strategy

If you want to fully migrate from Prometheus to VictoriaMetrics:

1. Run both in parallel (current setup)
2. Verify VictoriaMetrics has all data
3. Update dashboards to use VictoriaMetrics
4. Gradually reduce Prometheus retention
5. Eventually remove Prometheus

## Cleanup

### Remove VictoriaMetrics/VictoriaTraces Only

```bash
kubectl delete -f kubernetes/base/victoriametrics/

# Restore Prometheus config
kubectl apply -f kubernetes/base/prometheus/prometheus-config.yaml
kubectl rollout restart deployment/prometheus -n monitoring

# Restore OTEL config (remove VictoriaTraces exporter)
# Edit kubernetes/base/otel-collector/otel-collector-config.yaml
kubectl rollout restart deployment/otel-collector -n monitoring
```

### Keep Everything

The current setup runs all four components:
- Prometheus + VictoriaMetrics (metrics)
- Jaeger + VictoriaTraces (traces)

This is useful for:
- Comparison
- Migration
- Redundancy
- Different use cases

## Additional Resources

- [VictoriaMetrics Documentation](https://docs.victoriametrics.com/)
- [VictoriaTraces Documentation](https://docs.victoriametrics.com/VictoriaTraces/)
- [Dashboard 24134](https://grafana.com/grafana/dashboards/24134)
- [PromQL Documentation](https://prometheus.io/docs/prometheus/latest/querying/basics/)

## Summary

You now have:

✅ VictoriaMetrics running alongside Prometheus
✅ VictoriaTraces running alongside Jaeger
✅ Dual-path data collection (redundancy)
✅ All datasources configured in Grafana
✅ Ready to import VictoriaTraces dashboard (24134)
✅ Better performance for large-scale monitoring

Access the dashboard:
1. Generate traffic: `./scripts/generate-traffic.sh`
2. Open Grafana: http://localhost:3000
3. Import dashboard: ID **24134**
4. Select VictoriaMetrics datasource
5. Explore the metrics!
