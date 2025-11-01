# Kubernetes Cluster Monitoring with CNCF Tools

A comprehensive, production-ready demonstration of Kubernetes monitoring, observability, and service mesh using Cloud Native Computing Foundation (CNCF) tools. This project showcases a complete monitoring stack with distributed tracing, metrics collection, and service mesh capabilities.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Quick Start](#quick-start)
- [Deployment Options](#deployment-options)
- [Components](#components)
- [Service Mesh Options](#service-mesh-options)
- [Access Dashboards](#access-dashboards)
- [Testing and Traffic Generation](#testing-and-traffic-generation)
- [Documentation](#documentation)
- [Troubleshooting](#troubleshooting)

---

## Architecture Overview

This demo implements a complete cloud-native monitoring solution with the following components:

### Monitoring & Observability Stack

- **Prometheus**: Metrics collection and storage (7-day retention)
- **Grafana**: Metrics visualization and dashboards
- **Jaeger**: Distributed tracing with Service Performance Monitoring (SPM)
- **OpenTelemetry Collector**: Unified telemetry collection with spanmetrics and servicegraph connectors
- **VictoriaMetrics**: Long-term metrics storage (14-day retention)
- **VictoriaTraces**: Distributed tracing backend
- **Node Exporter**: Node-level system metrics
- **cAdvisor**: Container metrics (built into kubelet)

### Infrastructure Components

- **Apache Kafka**: Message broker with full monitoring and tracing
  - Kafka Exporter: Topic and consumer group metrics
  - JMX Exporter: Kafka broker metrics
  - Zookeeper: Cluster coordination

- **PostgreSQL**: Database with monitoring
  - PostgreSQL Exporter: Database performance metrics
  - Supports both in-cluster and external databases

### Service Mesh Options

Choose one based on your needs:

- **Istio**: Feature-rich service mesh with Kiali dashboard
  - Advanced traffic management (canary, A/B testing)
  - Automatic mTLS and security policies
  - Comprehensive observability

- **Linkerd**: Lightweight, ultra-fast service mesh
  - 8x lighter than Istio (~10MB vs ~80MB per sidecar)
  - <1ms latency overhead
  - Automatic mTLS
  - Built-in golden metrics

### Microservices

- **Java Services** (3): Spring Boot applications with Prometheus and OpenTelemetry
  - service-a: Producer service (Kafka integration)
  - service-b: Consumer service
  - service-c: Consumer service

- **Rust Services** (5): Actix-web applications with full instrumentation
  - product-service, inventory-service, notification-service
  - analytics-service, gateway-service

---

## Quick Start

### Prerequisites

- Docker
- kubectl
- kind (Kubernetes in Docker)
- Maven (for Java services)
- Rust and Cargo (for Rust services, optional)

### Installation

#### Option 1: Full Deployment with Build (Recommended for First Time)

Deploy everything including building services and monitoring stack:

```bash
# Create Kind cluster (if not exists)
kind create cluster --name monitoring-demo --config kind-config.yaml

# Build and deploy all components
./scripts/build-and-deploy.sh
```

#### Option 2: Deploy with Istio Service Mesh

```bash
# Deploy everything with Istio
./scripts/deploy-with-istio.sh

# When prompted, choose option 1 (Kiali only - no duplicates)
```

#### Option 3: Deploy with Linkerd Service Mesh (Lightweight)

```bash
# Deploy everything with Linkerd
./scripts/deploy-with-linkerd.sh

# When asked about Prometheus: Choose option 2 (External - RECOMMENDED)
# Saves ~70m CPU and ~150Mi RAM while providing unified metrics
```

#### Option 4: Monitoring Stack Only

```bash
# Deploy only monitoring components
./scripts/deploy-monitoring.sh
```

### Verify Deployment

```bash
# Check monitoring components
kubectl get pods -n monitoring

# Check services
kubectl get pods -n services

# Check service mesh (if deployed)
kubectl get pods -n istio-system   # For Istio
kubectl get pods -n linkerd        # For Linkerd
```

Expected output:
```
NAMESPACE     NAME                              READY   STATUS    RESTARTS   AGE
monitoring    prometheus-xxx                    1/1     Running   0          5m
monitoring    grafana-xxx                       1/1     Running   0          5m
monitoring    jaeger-xxx                        1/1     Running   0          5m
monitoring    otel-collector-xxx                1/1     Running   0          5m
monitoring    kafka-0                           2/2     Running   0          5m
monitoring    postgres-exporter-xxx             1/1     Running   0          5m
services      service-a-xxx                     1/1     Running   0          5m
services      service-b-xxx                     1/1     Running   0          5m
services      service-c-xxx                     1/1     Running   0          5m
```

---

## Deployment Options

This project provides multiple deployment scripts for different scenarios:

| Script | Use Case | What It Does |
|--------|----------|--------------|
| `build-and-deploy.sh` | **First deployment** | Builds services + deploys monitoring |
| `deploy-with-istio.sh` | **Istio mesh** | Full deployment with Istio + Kiali |
| `deploy-with-linkerd.sh` | **Linkerd mesh** | Full deployment with lightweight Linkerd |
| `deploy-monitoring.sh` | **Monitoring only** | Deploys only monitoring stack |
| `install-istio.sh` | **Add Istio later** | Adds Istio to existing deployment |
| `install-linkerd.sh` | **Add Linkerd later** | Adds Linkerd to existing deployment |

### Choosing Between Service Meshes

| Feature | Linkerd | Istio |
|---------|---------|-------|
| **Resource Usage** | Ultra-light (~10MB/sidecar) | Heavy (~80MB/sidecar) |
| **Complexity** | Simple, minimal config | Feature-rich, complex |
| **Latency** | <1ms p99 overhead | ~2-5ms p99 overhead |
| **Learning Curve** | Easy | Steep |
| **Dashboard** | Linkerd Viz | Kiali (advanced) |
| **Best For** | Production, resource-constrained | Advanced traffic management |

**Recommendation**:
- Use **Linkerd** for resource-constrained environments (like Kind) and production simplicity
- Use **Istio** if you need Kiali dashboard or advanced traffic management features

See [LINKERD_VS_ISTIO.md](LINKERD_VS_ISTIO.md) for detailed comparison.

---

## Components

### Monitoring Stack Details

#### Prometheus Configuration

**Scrape Configurations**:
- Kubernetes service discovery (API Server, kubelet, nodes)
- Pod annotations (`prometheus.io/scrape`, `prometheus.io/port`, `prometheus.io/path`)
- Kafka metrics (JMX Exporter, Kafka Exporter)
- PostgreSQL metrics (PostgreSQL Exporter)
- Service mesh metrics (Istio/Linkerd)

**Key Metrics Available**:
- `http_server_requests_seconds`: Request duration and counts
- `jvm_memory_used_bytes`: JVM memory usage
- `kafka_server_brokertopicmetrics_*`: Kafka broker metrics
- `kafka_consumergroup_lag`: Consumer group lag
- `pg_stat_*`: PostgreSQL statistics
- Custom application metrics

#### OpenTelemetry Pipeline

```
Applications → OTEL Collector → Jaeger (traces)
                              → Prometheus (metrics via spanmetrics)
                              → VictoriaTraces (traces)
```

**Features**:
- Automatic trace context propagation
- Span metrics generation (RED metrics from traces)
- Service graph generation
- Kafka message tracing

#### Jaeger Tracing

**Components**:
- All-in-one deployment (collector + query + UI)
- OTLP receiver for OpenTelemetry
- In-memory storage (configurable for production)

**Features**:
- Distributed traces with full request context
- Service Performance Monitoring (SPM) - RED metrics from traces
- Service dependency graphs
- Trace correlation with logs and metrics

### Infrastructure Components

#### Kafka Integration

- **Single-broker cluster** with Zookeeper
- **Full distributed tracing** for producer and consumer operations
- **Comprehensive metrics**:
  - JMX Exporter: Broker internals, JVM metrics
  - Kafka Exporter: Topic metrics, consumer group lag
- **Auto-configured topics** with retention policies

See [KAFKA_SETUP.md](KAFKA_SETUP.md) for detailed setup.

#### PostgreSQL Monitoring

- **PostgreSQL Exporter** for database metrics
- Supports **external databases** (typical production scenario)
- **Comprehensive metrics**:
  - Connection pool statistics
  - Query performance
  - Table and index statistics
  - Replication lag

See [EXTERNAL_POSTGRES.md](EXTERNAL_POSTGRES.md) for external database configuration.

---

## Service Mesh Options

### Istio Service Mesh

Istio provides enterprise-grade service mesh capabilities:

**Quick Start**:
```bash
./scripts/deploy-with-istio.sh
# Choose option 1: Kiali only (recommended - no duplicates)
```

**What You Get**:
- Kiali dashboard for service visualization
- Advanced traffic management (canary, A/B testing, fault injection)
- Automatic mTLS between all services
- Authorization policies and security
- Enhanced observability with service-level metrics

**Access Kiali**:
```bash
kubectl port-forward svc/kiali -n istio-system 20001:20001
```
Open: http://localhost:20001

**Documentation**:
- [ISTIO_QUICK_START.md](ISTIO_QUICK_START.md) - 5-minute guide
- [ISTIO_SETUP.md](ISTIO_SETUP.md) - Complete setup guide
- [ISTIO_TRAFFIC_MANAGEMENT.md](ISTIO_TRAFFIC_MANAGEMENT.md) - Traffic patterns
- [ISTIO_OBSERVABILITY.md](ISTIO_OBSERVABILITY.md) - Kiali and metrics
- [DEPLOYMENT_OPTIONS.md](DEPLOYMENT_OPTIONS.md) - Avoid duplicate monitoring tools

### Linkerd Service Mesh (Lightweight Alternative)

Linkerd provides production-ready service mesh with minimal overhead:

**Quick Start**:
```bash
./scripts/deploy-with-linkerd.sh
# When asked about Prometheus: Choose option 2 (External - RECOMMENDED)
```

**What You Get**:
- Automatic mTLS with zero configuration
- Golden metrics (success rate, RPS, latency p50/p95/p99)
- Live traffic tap for real-time request inspection
- Service profiles for per-route metrics
- Traffic splitting for canary deployments

**Access Linkerd Dashboard**:
```bash
export PATH=$HOME/.linkerd2/bin:$PATH
linkerd viz dashboard
```
Or manually:
```bash
kubectl port-forward -n linkerd-viz svc/web 8084:8084
```
Open: http://localhost:8084

**Prometheus Integration**:
This demo offers two Prometheus options for Linkerd:

1. **Embedded Prometheus** (default)
   - Separate Prometheus in `linkerd-viz` namespace
   - Quick setup, good for demos

2. **External Prometheus** (RECOMMENDED)
   - Uses existing Prometheus in `monitoring` namespace
   - Saves ~70m CPU, ~150Mi RAM (20% reduction!)
   - Unified metrics in one place
   - Fully automated in deployment script

**Documentation**:
- [LINKERD_QUICK_START.md](LINKERD_QUICK_START.md) - 5-minute guide
- [LINKERD_SETUP.md](LINKERD_SETUP.md) - Complete setup guide
- [LINKERD_TRAFFIC_MANAGEMENT.md](LINKERD_TRAFFIC_MANAGEMENT.md) - Canary deployments
- [LINKERD_OBSERVABILITY.md](LINKERD_OBSERVABILITY.md) - Metrics and tap
- [LINKERD_PROMETHEUS_OPTIONS.md](LINKERD_PROMETHEUS_OPTIONS.md) - Embedded vs External
- [LINKERD_VISUALIZATION.md](LINKERD_VISUALIZATION.md) - Dashboard guide

**Important**: Don't run both Istio and Linkerd in the same namespace! Choose one per namespace.

See [TROUBLESHOOTING_MESHES.md](TROUBLESHOOTING_MESHES.md) for conflict resolution.

---

## Access Dashboards

### Using Port Forwarding (Recommended for Kind)

Since Kind doesn't provide external LoadBalancer IPs, use port forwarding:

**Automated Port Forwarding**:
```bash
# Start all port forwards (runs in foreground)
./scripts/port-forward.sh
```

**Manual Port Forwarding**:
```bash
# Prometheus
kubectl port-forward -n monitoring svc/prometheus 9090:9090

# Grafana
kubectl port-forward -n monitoring svc/grafana 3000:3000

# Jaeger UI
kubectl port-forward -n monitoring svc/jaeger-query 16686:16686

# Service-A (for testing)
kubectl port-forward -n services svc/service-a 8888:80

# Kiali (if using Istio)
kubectl port-forward -n istio-system svc/kiali 20001:20001

# Linkerd Dashboard (if using Linkerd)
kubectl port-forward -n linkerd-viz svc/web 8084:8084
```

### Dashboard Access URLs

| Service | URL | Credentials | Description |
|---------|-----|-------------|-------------|
| **Prometheus** | http://localhost:9090 | - | Query metrics, view targets |
| **Grafana** | http://localhost:3000 | admin / admin | Dashboards and visualization |
| **Jaeger UI** | http://localhost:16686 | - | Distributed traces and SPM |
| **VictoriaMetrics** | http://localhost:8428 | - | Long-term metrics storage |
| **Kiali** (Istio) | http://localhost:20001 | - | Service mesh topology |
| **Linkerd Viz** | http://localhost:8084 | - | Service mesh metrics |
| **Service-A** | http://localhost:8888 | - | Test service endpoint |

### Dashboard Features

#### Prometheus (http://localhost:9090)
- Query and explore all metrics
- View scrape targets and service discovery
- Monitor recording rules and alerts
- Prometheus-compatible PromQL queries

#### Grafana (http://localhost:3000)
- Pre-configured with datasources:
  - Prometheus (monitoring namespace)
  - Jaeger (trace correlation)
  - VictoriaMetrics (long-term storage)
- Create custom dashboards
- Import community dashboards
- Explore logs, metrics, and traces together

#### Jaeger (http://localhost:16686)
- **Traces Tab**: View distributed traces across services
- **Monitor Tab**: Service Performance Monitoring (RED metrics)
- **System Architecture**: Service dependency graph
- Trace search with filters (service, operation, tags, duration)
- Trace comparison and analysis

---

## Testing and Traffic Generation

### Generate Kafka Traffic

```bash
# Generate traffic for 60 seconds (default)
./scripts/generate-kafka-traffic.sh

# Custom duration (30 seconds)
DURATION=30 ./scripts/generate-kafka-traffic.sh
```

### Generate HTTP Traffic

```bash
# Generate HTTP traffic to services
./scripts/generate-traffic.sh

# Custom duration
DURATION=120 ./scripts/generate-traffic.sh
```

### Manual Testing

#### Test Kafka Integration

```bash
# Send a message to Kafka
curl http://localhost:8888/api/kafka/send/TestMessage

# Check consumer logs
kubectl logs -n services deploy/service-b -f | grep Kafka
kubectl logs -n services deploy/service-c -f | grep Kafka
```

#### Test Service Communication

```bash
# Call service-a
curl http://localhost:8888/api/hello

# View traces in Jaeger
# 1. Open http://localhost:16686
# 2. Select "service-a" from dropdown
# 3. Click "Find Traces"
# 4. Explore the distributed trace
```

### View Metrics in Prometheus

Open http://localhost:9090 and try these queries:

```promql
# Request rate
rate(http_server_requests_seconds_count[5m])

# P95 latency
histogram_quantile(0.95, rate(http_server_requests_seconds_bucket[5m]))

# Error rate
rate(http_server_requests_seconds_count{status=~"5.."}[5m])

# Kafka message rate
rate(kafka_server_brokertopicmetrics_messagesin_total[1m])

# Consumer lag
kafka_consumergroup_lag

# PostgreSQL connections
pg_stat_database_numbackends
```

---

## Project Structure

```
k8s-monitoring-demo/
├── kind-config.yaml                    # Kind cluster configuration
├── kubernetes/
│   ├── base/                          # Base Kubernetes manifests
│   │   ├── namespaces.yaml
│   │   ├── storage/                   # Persistent volume claims
│   │   ├── prometheus/                # Prometheus stack (7-day retention)
│   │   ├── grafana/                   # Grafana dashboards
│   │   ├── jaeger/                    # Jaeger tracing (SPM enabled)
│   │   ├── otel-collector/            # OpenTelemetry Collector
│   │   ├── node-exporter/             # Node metrics exporter
│   │   ├── victoriametrics/           # VictoriaMetrics and VictoriaTraces
│   │   ├── kafka/                     # Kafka with Zookeeper
│   │   ├── postgres/                  # PostgreSQL with exporter
│   │   ├── istio/                     # Istio configurations
│   │   ├── linkerd/                   # Linkerd configurations
│   │   └── services/                  # Microservice deployments
│   ├── overlays/
│   │   └── dev/                       # Development overlays
│   └── linkerd/                       # Linkerd-specific configs
├── services/
│   ├── java/                          # Java microservices
│   │   ├── service-a/                 # Kafka producer
│   │   ├── service-b/                 # Kafka consumer
│   │   └── service-c/                 # Kafka consumer
│   └── rust/                          # Rust microservices (5 services)
├── scripts/
│   ├── build-and-deploy.sh           # Build and deploy everything
│   ├── deploy-with-istio.sh          # Deploy with Istio mesh
│   ├── deploy-with-linkerd.sh        # Deploy with Linkerd mesh
│   ├── deploy-monitoring.sh          # Deploy monitoring only
│   ├── install-istio.sh              # Add Istio to existing setup
│   ├── install-linkerd.sh            # Add Linkerd to existing setup
│   ├── generate-kafka-traffic.sh     # Kafka traffic generator
│   ├── generate-traffic.sh           # HTTP traffic generator
│   ├── port-forward.sh               # Setup all port forwards
│   └── cleanup-*.sh                  # Cleanup scripts
└── docs/
    ├── MONITORING_SETUP.md           # Detailed monitoring guide
    ├── PROMETHEUS.md                 # Prometheus configuration
    ├── GRAFANA.md                    # Grafana dashboard guide
    ├── OTEL_TRACING.md               # OpenTelemetry guide
    └── JAEGER_SPM_SETUP.md           # Jaeger SPM guide
```

---

## Documentation

### Getting Started
- [QUICK_START.md](QUICK_START.md) - Fastest way to get running
- [DEPLOYMENT_OPTIONS.md](DEPLOYMENT_OPTIONS.md) - All deployment scenarios

### Monitoring & Observability
- [docs/MONITORING_SETUP.md](docs/MONITORING_SETUP.md) - Complete monitoring setup
- [docs/PROMETHEUS.md](docs/PROMETHEUS.md) - Prometheus configuration details
- [docs/GRAFANA.md](docs/GRAFANA.md) - Grafana dashboards guide
- [docs/OTEL_TRACING.md](docs/OTEL_TRACING.md) - OpenTelemetry tracing
- [docs/JAEGER_SPM_SETUP.md](docs/JAEGER_SPM_SETUP.md) - Service Performance Monitoring
- [VICTORIA_DASHBOARD_GUIDE.md](VICTORIA_DASHBOARD_GUIDE.md) - VictoriaMetrics guide

### Infrastructure
- [KAFKA_SETUP.md](KAFKA_SETUP.md) - Kafka integration and monitoring
- [EXTERNAL_POSTGRES.md](EXTERNAL_POSTGRES.md) - PostgreSQL external DB setup
- [POSTGRES_EXPORTER_SUMMARY.md](POSTGRES_EXPORTER_SUMMARY.md) - PostgreSQL metrics

### Service Mesh - Istio
- [ISTIO_QUICK_START.md](ISTIO_QUICK_START.md) - Get started in 5 minutes
- [ISTIO_SETUP.md](ISTIO_SETUP.md) - Complete installation guide
- [ISTIO_TRAFFIC_MANAGEMENT.md](ISTIO_TRAFFIC_MANAGEMENT.md) - Traffic patterns
- [ISTIO_OBSERVABILITY.md](ISTIO_OBSERVABILITY.md) - Kiali and monitoring
- [ISTIO_ARCHITECTURE.md](ISTIO_ARCHITECTURE.md) - Architecture details
- [ISTIO_FEATURES_DEMO.md](ISTIO_FEATURES_DEMO.md) - Feature demonstrations

### Service Mesh - Linkerd
- [LINKERD_QUICK_START.md](LINKERD_QUICK_START.md) - Get started in 5 minutes
- [LINKERD_SETUP.md](LINKERD_SETUP.md) - Complete installation guide
- [LINKERD_TRAFFIC_MANAGEMENT.md](LINKERD_TRAFFIC_MANAGEMENT.md) - Canary deployments
- [LINKERD_OBSERVABILITY.md](LINKERD_OBSERVABILITY.md) - Metrics and tap
- [LINKERD_PROMETHEUS_OPTIONS.md](LINKERD_PROMETHEUS_OPTIONS.md) - Prometheus choices
- [LINKERD_VISUALIZATION.md](LINKERD_VISUALIZATION.md) - Dashboard guide
- [LINKERD_VS_ISTIO.md](LINKERD_VS_ISTIO.md) - Comparison guide

### Troubleshooting
- [TROUBLESHOOTING_MESHES.md](TROUBLESHOOTING_MESHES.md) - Service mesh issues
- [docs/JAEGER_DEPENDENCIES_TROUBLESHOOTING.md](docs/JAEGER_DEPENDENCIES_TROUBLESHOOTING.md) - Jaeger dependencies
- [AUTOMATED_FIXES.md](AUTOMATED_FIXES.md) - What's been automated

---

## Troubleshooting

### Common Issues

#### Pods Not Starting

```bash
# Check pod status
kubectl get pods -n monitoring
kubectl get pods -n services

# View pod logs
kubectl logs -n services <pod-name>

# Describe pod for events
kubectl describe pod -n services <pod-name>
```

#### Prometheus Not Scraping Services

Check service annotations:
```yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8080"
  prometheus.io/path: "/metrics"
```

Verify targets in Prometheus:
- Open http://localhost:9090/targets
- All targets should show "UP" status

#### Jaeger Not Receiving Traces

```bash
# Check OTEL Collector logs
kubectl logs -n monitoring deployment/otel-collector

# Verify service configuration
kubectl get deployment service-a -n services -o yaml | grep OTEL_EXPORTER

# Should show: http://otel-collector.monitoring.svc.cluster.local:4317
```

#### Port Forwarding Issues

```bash
# Kill existing port forwards
pkill -f "kubectl port-forward"

# Restart port forwards
./scripts/port-forward.sh
```

#### Service Mesh Conflicts

```bash
# If running both Istio and Linkerd (not recommended)
./scripts/cleanup-mesh-conflicts.sh

# Remove Istio
kubectl delete namespace istio-system

# Remove Linkerd
linkerd viz uninstall | kubectl delete -f -
linkerd uninstall | kubectl delete -f -
```

#### Kafka Issues

```bash
# Check Kafka broker status
kubectl logs -n services kafka-0 -c kafka

# Check Zookeeper
kubectl logs -n services zookeeper-0

# Verify metrics endpoints
kubectl exec -n services kafka-0 -c kafka -- \
  curl -s http://localhost:5556/metrics | head -20
```

### Resource Issues

If running on resource-constrained environments:

1. **Use Linkerd instead of Istio**: Saves ~70MB per pod
2. **Use external Prometheus for Linkerd**: Saves ~70m CPU, ~150Mi RAM
3. **Reduce retention periods**: Edit Prometheus and VictoriaMetrics configs
4. **Scale down replicas**: Adjust in `kubernetes/overlays/dev/kustomization.yaml`

---

## Service Communication Flow

```
User Request
    ↓
gateway-service (Rust)
    ↓
service-a (Java) ──▶ Kafka ──▶ service-b (Java)
    │                   │
    │                   └──▶ service-c (Java)
    │
    ├─▶ product-service (Rust)
    ├─▶ inventory-service (Rust)
    └─▶ analytics-service (Rust)

Monitoring Flow:
Services ──▶ OTEL Collector ──▶ Jaeger (traces)
                            └──▶ Prometheus (metrics)

Service Mesh (if enabled):
Sidecar Proxies ──▶ Prometheus (mesh metrics)
                └──▶ Kiali/Linkerd Viz (visualization)
```

---

## Cleanup

### Delete Specific Components

```bash
# Delete services only
kubectl delete -k kubernetes/overlays/dev/

# Delete Istio
kubectl delete namespace istio-system

# Delete Linkerd
linkerd viz uninstall | kubectl delete -f -
linkerd uninstall | kubectl delete -f -
```

### Delete Entire Cluster

```bash
# Delete the Kind cluster (removes everything)
kind delete cluster --name monitoring-demo
```

### Cleanup While Preserving Data

```bash
# Remove components but keep PVCs
./scripts/cleanup-preserve-data.sh
```

---

## Kubernetes Deployment with Kustomize

This project uses Kustomize for managing Kubernetes configurations:

### Base Configuration
Located in `kubernetes/base/`, contains:
- Core monitoring stack components
- Service definitions
- Common configurations

### Overlays
Located in `kubernetes/overlays/dev/`, provides:
- Environment-specific customizations
- Resource limits/requests adjustments
- Replica counts

### Deploy Using Kustomize

```bash
# Deploy everything
kubectl apply -k kubernetes/overlays/dev/

# View what will be applied (dry-run)
kubectl kustomize kubernetes/overlays/dev/

# Delete deployment
kubectl delete -k kubernetes/overlays/dev/
```

### Customize for Your Environment

Create a new overlay for production:

```bash
mkdir -p kubernetes/overlays/production
```

Create `kubernetes/overlays/production/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: monitoring

resources:
- ../../base/namespaces.yaml
- ../../base/prometheus
- ../../base/grafana
- ../../base/jaeger
- ../../base/otel-collector
- ../../base/node-exporter

patchesStrategicMerge:
- prometheus-patch.yaml  # Adjust resources, retention
- grafana-patch.yaml     # Add persistent storage
```

Apply to your cluster:

```bash
kubectl apply -k kubernetes/overlays/production/
```

---

## Next Steps

1. **Service Mesh**: Try Istio or Linkerd features with the guides above
2. **Custom Dashboards**: Create application-specific Grafana dashboards
3. **Persistent Storage**: Configure PVCs for production (see [docs/PERSISTENT_STORAGE.md](docs/PERSISTENT_STORAGE.md))
4. **Alerting**: Set up Alertmanager with Prometheus
5. **Log Aggregation**: Add Loki or ELK stack for logs
6. **SLOs**: Define and monitor Service Level Objectives
7. **External Databases**: Connect PostgreSQL exporter to your databases
8. **Production Hardening**: Review security policies and resource limits

---

## References

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [OpenTelemetry Documentation](https://opentelemetry.io/docs/)
- [Jaeger Documentation](https://www.jaegertracing.io/docs/)
- [Istio Documentation](https://istio.io/latest/docs/)
- [Linkerd Documentation](https://linkerd.io/docs/)
- [Apache Kafka Documentation](https://kafka.apache.org/documentation/)
- [Kustomize Documentation](https://kustomize.io/)

---

## Contributing

This is a demonstration project for educational purposes. Feel free to:
- Experiment with configurations
- Add new services
- Create custom dashboards
- Test different deployment scenarios
- Extend monitoring capabilities

---

## License

This is a demonstration project for educational purposes.

---

**Built with love for the Cloud Native community** ☁️
