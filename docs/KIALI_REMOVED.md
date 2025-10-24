# Why Kiali Was Removed

## Summary

Kiali was initially added to this monitoring stack but has been **removed** because it **requires Istio service mesh** to function properly.

## The Problem

When accessing Kiali UI without Istio, you would see errors like:

```
Danger alert: Could not fetch apps list: istio APIs and resources are not present in cluster [Kubernetes]
```

This is not a configuration issue - **Kiali fundamentally cannot work without Istio**. It relies on:
- Istio Custom Resource Definitions (CRDs)
- Istio service registry for discovering services
- Envoy proxy telemetry for traffic data
- Istio APIs for workload information

## What You Already Have (Better Alternatives)

Your monitoring stack already provides **complete observability** without Kiali:

### 1. Service Dependency Visualization

**Use: Jaeger System Architecture**

```bash
# Access Jaeger
open http://localhost:30002

# Navigate to: System Architecture tab
# Shows: Full service dependency graph derived from distributed traces
```

**Features:**
- ✅ Real-time service dependencies
- ✅ Call volumes between services
- ✅ Derived from actual trace data
- ✅ No Istio required!

**How it works:**
- OpenTelemetry Collector has `servicegraph` connector
- Analyzes parent-child span relationships
- Builds dependency graph automatically
- Updates as traffic flows

### 2. Service Performance Monitoring (SPM)

**Use: Jaeger Monitor Tab**

```bash
# Access Jaeger
open http://localhost:30002

# Navigate to: Monitor tab
# Select a service
```

**Features:**
- ✅ Request rates (R)
- ✅ Error rates (E)
- ✅ Latency percentiles (D) - P50, P95, P99
- ✅ RED metrics per service
- ✅ Operation-level breakdown

**How it works:**
- OpenTelemetry Collector has `spanmetrics` connector
- Generates Prometheus metrics from trace spans
- Jaeger queries Prometheus for SPM data
- Real-time performance insights

### 3. Distributed Tracing

**Use: Jaeger Traces**

```bash
# Access Jaeger
open http://localhost:30002

# Search by:
# - Service
# - Operation
# - Tags
# - Duration
```

**Features:**
- ✅ End-to-end request traces
- ✅ Service-to-service call chains
- ✅ Latency breakdown per span
- ✅ Error propagation
- ✅ Timeline visualization

### 4. Metrics Dashboards

**Use: Grafana**

```bash
# Access Grafana
open http://localhost:3000
# Username: admin
# Password: admin
```

**Features:**
- ✅ Custom dashboards
- ✅ Service metrics visualization
- ✅ Infrastructure metrics
- ✅ Container metrics (cAdvisor)
- ✅ Node metrics (Node Exporter)

**Pre-built dashboards:**
- Jaeger SPM Dashboard: `grafana-dashboards/jaeger-spm-dashboard.json`

### 5. Metrics Queries

**Use: Prometheus**

```bash
# Access Prometheus
open http://localhost:9090
```

**Query examples:**

```promql
# Service call graph
traces_service_graph_request_total

# Request rates
rate(calls_total[5m])

# Latency P95
histogram_quantile(0.95, rate(duration_bucket[5m]))

# Error rates
sum by (service_name) (rate(calls_total{status_code=~"5.."}[5m]))
```

## Service Visualization Comparison

| Feature | Kiali (Istio Required) | Jaeger (Your Stack) |
|---------|------------------------|---------------------|
| Service graph | ✅ Real-time with traffic animation | ✅ Real-time from traces |
| Service dependencies | ✅ From Istio service mesh | ✅ From OTEL servicegraph |
| Request rates | ✅ From Envoy proxies | ✅ From spanmetrics |
| Error rates | ✅ From Envoy proxies | ✅ From spanmetrics |
| Latency metrics | ✅ From Envoy proxies | ✅ From spanmetrics |
| Distributed traces | ✅ Integration with Jaeger | ✅ Native in Jaeger |
| Traffic management | ✅ Istio VirtualServices | ❌ N/A |
| mTLS visualization | ✅ Istio security | ❌ N/A |
| **Istio Required** | ❌ **YES** | ✅ **NO** |

## How to Use Jaeger for Service Visualization

### Step 1: Generate Traffic

```bash
# Generate traffic to create traces
./scripts/generate-traffic.sh

# Or manually:
for i in {1..100}; do
  curl -s -X POST http://localhost:30080/api/action > /dev/null &
done
wait
```

### Step 2: View Service Dependencies

```bash
# Open Jaeger
open http://localhost:30002

# Click: System Architecture (or Dependencies) tab
```

You'll see a graph showing:
```
gateway-service → order-service → user-service
                                → product-service
                                → payment-service → notification-service
                → user-service
                → product-service → inventory-service
```

**Interpreting the graph:**
- **Nodes**: Services
- **Edges**: Call relationships
- **Numbers**: Call counts
- **Colors**: Service health

### Step 3: View Service Performance (SPM)

```bash
# Open Jaeger
open http://localhost:30002

# Click: Monitor tab
# Select service: gateway-service
```

You'll see:
- **Request Rate**: Requests per second over time
- **Error Rate**: Percentage of failed requests
- **P95 Latency**: 95th percentile response time
- **Impact**: Which operations are slowest/most frequent

### Step 4: Drill Down to Traces

```bash
# Click on any data point in SPM charts
# Or use Search:
# - Service: gateway-service
# - Click "Find Traces"
```

You'll see:
- List of traces
- Duration, spans, depth
- Click trace to see full timeline
- See which services were called
- Identify slow operations

### Step 5: Create Grafana Dashboards

```bash
# Import Jaeger SPM dashboard
open http://localhost:3000
# Dashboards → Import
# Upload: grafana-dashboards/jaeger-spm-dashboard.json
```

Custom queries for service graph:

```promql
# Service call rates (from servicegraph)
rate(traces_service_graph_request_total[5m])

# Service latencies
histogram_quantile(0.95,
  rate(traces_service_graph_request_duration_seconds_bucket[5m])
)

# RED metrics (from spanmetrics)
rate(calls_total[5m])
histogram_quantile(0.95, rate(duration_bucket[5m]))
sum by (service_name) (rate(calls_total{status_code=~"5.."}[5m]))
```

## If You Really Need Kiali

If you want Kiali's full features, you must install Istio:

### Install Istio

```bash
# Download Istio
curl -L https://istio.io/downloadIstio | sh -
cd istio-*
export PATH=$PWD/bin:$PATH

# Install Istio (demo profile)
istioctl install --set profile=demo -y

# Enable sidecar injection
kubectl label namespace services istio-injection=enabled

# Restart services to inject sidecars
kubectl rollout restart deployment -n services
```

### Deploy Kiali

```bash
# Apply Kiali resources
kubectl apply -k kubernetes/base/

# Kiali files are still in the repo:
# - kubernetes/base/kiali/kiali-rbac.yaml
# - kubernetes/base/kiali/kiali-config.yaml
# - kubernetes/base/kiali/kiali-deployment.yaml
```

### Update Kiali Config

After Istio is installed, update `kubernetes/base/kiali/kiali-config.yaml`:

```yaml
external_services:
  istio:
    istio_api_enabled: true  # Change to true
    component_status:
      enabled: true          # Change to true

istio_namespace: "istio-system"  # Set to istio-system
```

Then restart Kiali:

```bash
kubectl rollout restart deployment/kiali -n monitoring
```

## Recommendation

**For this demo:** Use Jaeger for service visualization. It works perfectly without Istio and provides all the observability you need.

**For production with service mesh:** Install Istio first, then add Kiali for enhanced visualization.

## Complete Observability Stack (Without Istio)

Your current stack provides:

1. ✅ **Metrics**: Prometheus + VictoriaMetrics
2. ✅ **Visualization**: Grafana dashboards
3. ✅ **Distributed Tracing**: Jaeger
4. ✅ **Service Dependencies**: Jaeger System Architecture
5. ✅ **Service Performance**: Jaeger SPM (RED metrics)
6. ✅ **Service Metrics**: OTEL spanmetrics connector
7. ✅ **Service Graph**: OTEL servicegraph connector
8. ✅ **Container Metrics**: cAdvisor
9. ✅ **Node Metrics**: Node Exporter
10. ✅ **Persistent Storage**: 7-day retention (Prometheus), 14-day (VictoriaMetrics)

**You don't need Kiali!**

## References

- [Jaeger Documentation](https://www.jaegertracing.io/docs/)
- [Jaeger SPM](https://www.jaegertracing.io/docs/latest/spm/)
- [OpenTelemetry Servicegraph Connector](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/connector/servicegraphconnector)
- [OpenTelemetry Spanmetrics Connector](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/connector/spanmetricsconnector)
- [Kiali Documentation](https://kiali.io/docs/) - If you decide to install Istio

## Summary

- ❌ Kiali removed: Requires Istio, doesn't work without it
- ✅ Jaeger System Architecture: Service dependency graph
- ✅ Jaeger SPM: RED metrics from traces
- ✅ Full observability: Already complete without Kiali
- 📚 See `JAEGER_SPM_SETUP.md` for detailed Jaeger setup
- 📚 See `JAEGER_DEPENDENCIES_TROUBLESHOOTING.md` for dependencies help
