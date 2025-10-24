# Kubernetes Cluster Monitoring with CNCF Tools

A comprehensive demonstration of Kubernetes monitoring using CNCF (Cloud Native Computing Foundation) tools including Prometheus, Grafana, OpenTelemetry, and Jaeger.

## Architecture Overview

This demo includes:

### Monitoring Stack
- **Prometheus**: Metrics collection and storage (7-day retention)
- **Grafana**: Metrics visualization and dashboards
- **Node Exporter**: Node-level system metrics
- **cAdvisor**: Container metrics (built into kubelet)
- **OpenTelemetry Collector**: Traces and metrics collection with spanmetrics and servicegraph connectors
- **Jaeger**: Distributed tracing UI with Service Performance Monitoring (SPM) and dependency visualization
- **VictoriaMetrics**: Long-term metrics storage (14-day retention)
- **VictoriaTraces**: Distributed tracing backend

### Microservices
- **Java Services** (3): Spring Boot applications with Prometheus and OTEL instrumentation
  - user-service: User management
  - order-service: Order management (calls user-service)
  - payment-service: Payment processing

- **Rust Services** (5): Actix-web applications with Prometheus and OTEL instrumentation
  - product-service: Product catalog
  - inventory-service: Inventory management
  - notification-service: Event notifications
  - analytics-service: Data analytics
  - gateway-service: API gateway

## Prerequisites

- Docker
- kubectl
- kind (Kubernetes in Docker)
- Maven (for Java services)
- Rust and Cargo (for Rust services)

## Quick Start

### 1. Create the Kubernetes Cluster

The kind cluster is already created with port mappings for easy access to monitoring dashboards:

```bash
# Cluster is running at kind-monitoring-demo
kubectl cluster-info --context kind-monitoring-demo
```

### 2. Verify Monitoring Stack

Check that all monitoring components are running:

```bash
kubectl get pods -n monitoring
```

Expected output:
```
NAME                              READY   STATUS    RESTARTS   AGE
prometheus-xxx                    1/1     Running   0          5m
grafana-xxx                       1/1     Running   0          5m
jaeger-xxx                        1/1     Running   0          5m
otel-collector-xxx                1/1     Running   0          5m
node-exporter-xxx                 1/1     Running   0          5m
```

### 3. Access Monitoring Dashboards

The dashboards are exposed via NodePort and mapped to your localhost:

- **Prometheus**: http://localhost:9090
  - Query metrics, view targets, explore service discovery
  - Access: `http://localhost:30000`

- **Grafana**: http://localhost:3000
  - Username: `admin`
  - Password: `admin`
  - Pre-configured with Prometheus, Jaeger, and VictoriaMetrics datasources
  - Access: `http://localhost:30001`

- **Jaeger UI**: http://localhost:30002
  - **Traces**: View distributed traces with full request context
  - **Monitor Tab**: Service Performance Monitoring (SPM) - RED metrics from traces
  - **System Architecture**: Service dependency graph and call volumes
  - This is your primary tool for service visualization!

- **VictoriaMetrics**: http://localhost:30003
  - Long-term metrics storage
  - Prometheus-compatible query interface

- **VictoriaTraces**: http://localhost:30004
  - Alternative tracing backend

## Project Structure

```
k8s-monitoring-demo/
├── kind-config.yaml              # Kind cluster configuration
├── kubernetes/
│   ├── base/                     # Base Kubernetes manifests
│   │   ├── namespaces.yaml
│   │   ├── storage/              # Persistent volume claims
│   │   ├── prometheus/           # Prometheus stack (7-day retention)
│   │   ├── grafana/              # Grafana dashboards
│   │   ├── jaeger/               # Jaeger tracing (production setup with SPM)
│   │   ├── otel-collector/       # OpenTelemetry Collector (contrib with connectors)
│   │   ├── node-exporter/        # Node metrics exporter
│   │   ├── victoriametrics/      # VictoriaMetrics and VictoriaTraces
│   │   └── services/             # Microservice deployments
│   └── overlays/
│       └── dev/                  # Development overlays
│           └── kustomization.yaml
├── services/
│   ├── java/                     # Java microservices
│   │   ├── user-service/
│   │   ├── order-service/
│   │   └── payment-service/
│   └── rust/                     # Rust microservices
│       ├── product-service/
│       ├── inventory-service/
│       ├── notification-service/
│       ├── analytics-service/
│       └── gateway-service/
├── scripts/
│   ├── build-and-deploy.sh              # Build and deployment script
│   ├── generate-traffic.sh              # Traffic generation for testing
│   ├── deploy-demo.sh                   # Deploy mock services
│   └── test-services.sh                 # Test service endpoints
├── grafana-dashboards/
│   └── jaeger-spm-dashboard.json        # Jaeger SPM dashboard
└── docs/
    ├── MONITORING_SETUP.md              # Detailed monitoring setup guide
    ├── PROMETHEUS.md                    # Prometheus configuration guide
    ├── GRAFANA.md                       # Grafana dashboard guide
    ├── OTEL_TRACING.md                  # OpenTelemetry tracing guide
    ├── JAEGER_SPM_SETUP.md              # Jaeger Service Performance Monitoring
    ├── JAEGER_DEPENDENCIES_TROUBLESHOOTING.md  # Service dependencies troubleshooting
    └── PERSISTENT_STORAGE.md            # Production storage configuration
```

## Monitoring Features

### Prometheus Metrics

Prometheus is configured to scrape metrics from:

1. **Kubernetes Components**
   - API Server
   - Kubelet (includes cAdvisor metrics)
   - Nodes

2. **System Metrics**
   - Node Exporter: CPU, memory, disk, network

3. **Application Metrics**
   - Custom metrics from Java services (via Micrometer)
   - Custom metrics from Rust services (via prometheus crate)
   - Annotations-based service discovery

### Grafana Dashboards

Grafana is pre-configured with:
- Prometheus datasource
- Jaeger datasource for trace correlation
- Auto-provisioned dashboard providers

**Create dashboards for:**
- Cluster overview (nodes, pods, resources)
- Application metrics (request rates, latencies, errors)
- JVM metrics (for Java services)
- Custom business metrics

### Distributed Tracing

OpenTelemetry instrumentation captures:
- HTTP requests/responses
- Service-to-service calls
- Custom spans in application code
- Correlation with logs and metrics

Traces are exported to Jaeger via the OTEL Collector.

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

### Deploy using Kustomize

```bash
# Deploy everything
kubectl apply -k kubernetes/overlays/dev/

# View what will be applied
kubectl kustomize kubernetes/overlays/dev/
```

## Service Communication Flow

```
User Request
    ↓
gateway-service (Rust)
    ↓
order-service (Java)
    ├→ user-service (Java)
    ├→ product-service (Rust)
    ├→ inventory-service (Rust)
    └→ payment-service (Java)
        └→ notification-service (Rust)

analytics-service (Rust) ← Consumes metrics from all services
```

## Observability Stack Details

### Prometheus Configuration

**Scrape Configurations:**
- Kubernetes service discovery
- Pod annotations (`prometheus.io/scrape`, `prometheus.io/port`, `prometheus.io/path`)
- Static configs for monitoring stack components

**Key Metrics to Monitor:**
- `http_server_requests_seconds`: Request duration
- `jvm_memory_used_bytes`: JVM memory usage
- `process_cpu_seconds_total`: CPU usage
- Custom application metrics

### OpenTelemetry Setup

**OTEL Collector Pipeline:**
```
Applications → OTEL Collector → Jaeger (traces)
                              → Prometheus (metrics)
```

**Instrumentation:**
- Java: OpenTelemetry Java Agent + SDK
- Rust: opentelemetry-rust crates

### Jaeger Tracing

**Components:**
- All-in-one deployment (collector + query + UI)
- OTLP receiver enabled for OpenTelemetry compatibility
- In-memory storage (for demo purposes)

## Building Services

### Java Services

```bash
cd services/java/user-service
mvn clean package
docker build -t user-service:latest .
kind load docker-image user-service:latest --name monitoring-demo
```

### Rust Services

```bash
cd services/rust/product-service
cargo build --release
docker build -t product-service:latest .
kind load docker-image product-service:latest --name monitoring-demo
```

## Testing the Setup

### 1. Generate Traffic

```bash
# Get a service endpoint
kubectl port-forward -n services svc/user-service 8080:80

# Make requests
curl http://localhost:8080/api/users/1
curl http://localhost:8080/api/users
```

### 2. View Metrics in Prometheus

1. Open http://localhost:9090
2. Try queries:
   ```promql
   # Request rate
   rate(http_server_requests_seconds_count[5m])

   # P95 latency
   histogram_quantile(0.95, rate(http_server_requests_seconds_bucket[5m]))

   # Error rate
   rate(http_server_requests_seconds_count{status=~"5.."}[5m])
   ```

### 3. View Traces in Jaeger

1. Open http://localhost:16686
2. Select a service from dropdown
3. Click "Find Traces"
4. Explore trace details and service dependencies

### 4. Create Grafana Dashboards

1. Open http://localhost:3000 (admin/admin)
2. Create → Dashboard
3. Add panels with Prometheus queries
4. Save dashboard

## Kustomization for Other Clusters

To deploy this monitoring stack on another cluster:

### 1. Create a new overlay

```bash
mkdir -p kubernetes/overlays/production
```

### 2. Create kustomization.yaml

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
- prometheus-patch.yaml  # Adjust resources, retention, etc.
- grafana-patch.yaml     # Persistent storage, etc.
```

### 3. Apply to your cluster

```bash
kubectl apply -k kubernetes/overlays/production/
```

## Troubleshooting

### Prometheus not scraping services

Check service annotations:
```yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8080"
  prometheus.io/path: "/metrics"
```

### Jaeger not receiving traces

1. Check OTEL Collector logs:
   ```bash
   kubectl logs -n monitoring deployment/otel-collector
   ```

2. Verify service configuration:
   ```yaml
   env:
   - name: OTEL_EXPORTER_OTLP_ENDPOINT
     value: "http://otel-collector.monitoring.svc.cluster.local:4317"
   ```

### Services not starting

Check pod logs:
```bash
kubectl logs -n services <pod-name>
kubectl describe pod -n services <pod-name>
```

## Cleanup

```bash
# Delete the kind cluster
kind delete cluster --name monitoring-demo

# Or just delete the deployments
kubectl delete -k kubernetes/overlays/dev/
```

## Next Steps

1. **Add Persistent Storage**: Configure PVCs for Prometheus and Grafana
2. **Alerting**: Set up Alertmanager with Prometheus
3. **Log Aggregation**: Add Loki or ELK stack
4. **Service Mesh**: Integrate with Istio or Linkerd for advanced observability
5. **Custom Dashboards**: Create application-specific Grafana dashboards
6. **SLOs**: Define and monitor Service Level Objectives

## References

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [OpenTelemetry Documentation](https://opentelemetry.io/docs/)
- [Jaeger Documentation](https://www.jaegertracing.io/docs/)
- [Kustomize Documentation](https://kustomize.io/)

## License

This is a demonstration project for educational purposes.
