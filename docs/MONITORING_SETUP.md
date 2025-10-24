# Monitoring Setup Guide

This document provides detailed instructions for setting up and configuring the monitoring stack.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Cluster Setup](#cluster-setup)
3. [Monitoring Stack Deployment](#monitoring-stack-deployment)
4. [Service Instrumentation](#service-instrumentation)
5. [Verification](#verification)
6. [Customization](#customization)

## Prerequisites

### Required Tools

```bash
# Check Docker
docker --version

# Check kubectl
kubectl version --client

# Check kind
kind version

# For Java services
mvn --version

# For Rust services
rustc --version
cargo --version
```

### Install kind (if not already installed)

```bash
# Linux
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x ./kind
mkdir -p ~/.local/bin
mv ./kind ~/.local/bin/kind

# Add to PATH
export PATH="$HOME/.local/bin:$PATH"
```

## Cluster Setup

### Step 1: Create kind Cluster

The `kind-config.yaml` file configures a cluster with port mappings for monitoring dashboards:

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: monitoring-demo
nodes:
  - role: control-plane
    extraPortMappings:
    - containerPort: 30000  # Prometheus
      hostPort: 9090
    - containerPort: 30001  # Grafana
      hostPort: 3000
    - containerPort: 30002  # Jaeger
      hostPort: 16686
  - role: worker
  - role: worker
```

Create the cluster:

```bash
kind create cluster --config kind-config.yaml
```

### Step 2: Verify Cluster

```bash
kubectl cluster-info --context kind-monitoring-demo
kubectl get nodes
```

Expected output: 1 control-plane + 2 worker nodes

## Monitoring Stack Deployment

### Step 1: Create Namespaces

```bash
kubectl apply -f kubernetes/base/namespaces.yaml
```

This creates:
- `monitoring` namespace for monitoring stack
- `services` namespace for application services

### Step 2: Deploy Prometheus

```bash
kubectl apply -f kubernetes/base/prometheus/
```

Components deployed:
- **ServiceAccount & RBAC**: Permissions for Prometheus to scrape Kubernetes
- **ConfigMap**: Prometheus configuration with scrape configs
- **Deployment**: Prometheus server
- **Service**: NodePort service on port 30000

**Verify:**
```bash
kubectl get pods -n monitoring -l app=prometheus
kubectl logs -n monitoring -l app=prometheus
```

### Step 3: Deploy Grafana

```bash
kubectl apply -f kubernetes/base/grafana/
```

Components deployed:
- **ConfigMap**: Datasource configuration (Prometheus + Jaeger)
- **Deployment**: Grafana server
- **Service**: NodePort service on port 30001

**Verify:**
```bash
kubectl get pods -n monitoring -l app=grafana
```

Access: http://localhost:3000 (admin/admin)

### Step 4: Deploy Node Exporter

```bash
kubectl apply -f kubernetes/base/node-exporter/
```

Components deployed:
- **DaemonSet**: Runs on every node
- **Service**: Headless service for Prometheus scraping

**Verify:**
```bash
kubectl get daemonset -n monitoring node-exporter
kubectl get pods -n monitoring -l app=node-exporter
```

### Step 5: Deploy Jaeger

```bash
kubectl apply -f kubernetes/base/jaeger/
```

Components deployed:
- **Deployment**: Jaeger all-in-one (collector + query + UI)
- **Services**:
  - jaeger-query: UI on NodePort 30002
  - jaeger-collector: OTLP receivers

**Verify:**
```bash
kubectl get pods -n monitoring -l app=jaeger
```

Access: http://localhost:16686

### Step 6: Deploy OpenTelemetry Collector

```bash
kubectl apply -f kubernetes/base/otel-collector/
```

Components deployed:
- **ConfigMap**: OTEL Collector configuration
- **Deployment**: OTEL Collector
- **Service**: OTLP receivers (gRPC: 4317, HTTP: 4318)

**Verify:**
```bash
kubectl get pods -n monitoring -l app=otel-collector
kubectl logs -n monitoring -l app=otel-collector
```

## Service Instrumentation

### Java Services (Spring Boot)

#### 1. Add Dependencies (pom.xml)

```xml
<dependencies>
    <!-- Spring Boot Actuator for health/metrics -->
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-actuator</artifactId>
    </dependency>

    <!-- Micrometer Prometheus Registry -->
    <dependency>
        <groupId>io.micrometer</groupId>
        <artifactId>micrometer-registry-prometheus</artifactId>
    </dependency>

    <!-- OpenTelemetry -->
    <dependency>
        <groupId>io.opentelemetry</groupId>
        <artifactId>opentelemetry-api</artifactId>
        <version>1.31.0</version>
    </dependency>
    <dependency>
        <groupId>io.opentelemetry</groupId>
        <artifactId>opentelemetry-sdk</artifactId>
        <version>1.31.0</version>
    </dependency>
    <dependency>
        <groupId>io.opentelemetry</groupId>
        <artifactId>opentelemetry-exporter-otlp</artifactId>
        <version>1.31.0</version>
    </dependency>
</dependencies>
```

#### 2. Configure Application (application.yml)

```yaml
management:
  endpoints:
    web:
      exposure:
        include: health,info,metrics,prometheus
  metrics:
    export:
      prometheus:
        enabled: true

otel:
  exporter:
    otlp:
      endpoint: http://otel-collector.monitoring.svc.cluster.local:4317
  service:
    name: ${spring.application.name}
```

#### 3. Add OpenTelemetry Configuration

```java
@Configuration
public class OpenTelemetryConfig {
    @Bean
    public OpenTelemetry openTelemetry() {
        Resource resource = Resource.getDefault()
                .merge(Resource.create(Attributes.builder()
                        .put(ResourceAttributes.SERVICE_NAME, serviceName)
                        .build()));

        OtlpGrpcSpanExporter spanExporter = OtlpGrpcSpanExporter.builder()
                .setEndpoint(otlpEndpoint)
                .build();

        SdkTracerProvider sdkTracerProvider = SdkTracerProvider.builder()
                .addSpanProcessor(BatchSpanProcessor.builder(spanExporter).build())
                .setResource(resource)
                .build();

        return OpenTelemetrySdk.builder()
                .setTracerProvider(sdkTracerProvider)
                .buildAndRegisterGlobal();
    }
}
```

#### 4. Add Prometheus Annotations to Deployment

```yaml
metadata:
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080"
    prometheus.io/path: "/actuator/prometheus"
```

### Rust Services (Actix-web)

#### 1. Add Dependencies (Cargo.toml)

```toml
[dependencies]
actix-web = "4.4"
prometheus = "0.13"
opentelemetry = "0.20"
opentelemetry-otlp = "0.13"
tracing = "0.1"
tracing-subscriber = "0.3"
```

#### 2. Initialize Metrics

```rust
use prometheus::{Encoder, TextEncoder, Counter, Registry};

lazy_static! {
    static ref REGISTRY: Registry = Registry::new();
    static ref REQUEST_COUNTER: Counter = Counter::new(
        "http_requests_total",
        "Total HTTP requests"
    ).unwrap();
}

// Register metrics
REGISTRY.register(Box::new(REQUEST_COUNTER.clone())).unwrap();
```

#### 3. Expose Metrics Endpoint

```rust
async fn metrics() -> impl Responder {
    let encoder = TextEncoder::new();
    let metric_families = REGISTRY.gather();
    let mut buffer = vec![];
    encoder.encode(&metric_families, &mut buffer).unwrap();
    HttpResponse::Ok()
        .content_type("text/plain")
        .body(buffer)
}

HttpServer::new(|| {
    App::new()
        .route("/metrics", web::get().to(metrics))
})
```

#### 4. Configure OpenTelemetry

```rust
use opentelemetry::global;
use opentelemetry_otlp::WithExportConfig;

fn init_tracer() {
    let tracer = opentelemetry_otlp::new_pipeline()
        .tracing()
        .with_exporter(
            opentelemetry_otlp::new_exporter()
                .tonic()
                .with_endpoint("http://otel-collector.monitoring.svc.cluster.local:4317")
        )
        .install_batch(opentelemetry::runtime::Tokio)
        .expect("Failed to initialize tracer");

    global::set_tracer_provider(tracer);
}
```

## Verification

### Check All Pods are Running

```bash
# Monitoring namespace
kubectl get pods -n monitoring

# Services namespace
kubectl get pods -n services
```

### Verify Prometheus Targets

1. Open http://localhost:9090
2. Go to Status → Targets
3. Verify all targets are "UP"

Expected targets:
- kubernetes-apiservers
- kubernetes-nodes
- kubernetes-pods
- node-exporter
- cadvisor

### Verify Grafana Datasources

1. Open http://localhost:3000
2. Login (admin/admin)
3. Go to Configuration → Data Sources
4. Verify:
   - Prometheus datasource is connected
   - Jaeger datasource is connected

### Test Metrics Collection

```bash
# Port-forward to a service
kubectl port-forward -n services svc/user-service 8080:80

# Check metrics endpoint
curl http://localhost:8080/actuator/prometheus

# Make some requests
for i in {1..10}; do curl http://localhost:8080/api/users/1; done
```

Then check Prometheus:
```promql
rate(http_server_requests_seconds_count[1m])
```

### Test Distributed Tracing

1. Generate traffic with service-to-service calls
2. Open Jaeger UI: http://localhost:16686
3. Select service from dropdown
4. Click "Find Traces"
5. Inspect trace spans

## Customization

### Adding New Scrape Targets

Edit `kubernetes/base/prometheus/prometheus-config.yaml`:

```yaml
scrape_configs:
  - job_name: 'my-custom-service'
    static_configs:
      - targets: ['my-service:9090']
```

Apply changes:
```bash
kubectl apply -f kubernetes/base/prometheus/prometheus-config.yaml
kubectl rollout restart deployment/prometheus -n monitoring
```

### Adjusting Resource Limits

Edit deployment files or use Kustomize patches:

```yaml
# kubernetes/overlays/production/resource-limits.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus
  namespace: monitoring
spec:
  template:
    spec:
      containers:
      - name: prometheus
        resources:
          requests:
            memory: "2Gi"
            cpu: "1000m"
          limits:
            memory: "4Gi"
            cpu: "2000m"
```

### Adding Persistent Storage

For Prometheus:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: prometheus-storage
  namespace: monitoring
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
```

Update deployment to use PVC:

```yaml
volumes:
- name: storage
  persistentVolumeClaim:
    claimName: prometheus-storage
```

## Troubleshooting

### Prometheus not scraping pods

1. Check pod annotations
2. Verify network policies allow scraping
3. Check Prometheus logs:
   ```bash
   kubectl logs -n monitoring deployment/prometheus
   ```

### Jaeger not showing traces

1. Check OTEL Collector logs:
   ```bash
   kubectl logs -n monitoring deployment/otel-collector
   ```

2. Verify service OTEL configuration
3. Check Jaeger collector endpoint is reachable

### Grafana can't connect to Prometheus

1. Verify Prometheus service is running:
   ```bash
   kubectl get svc -n monitoring prometheus
   ```

2. Test connectivity from Grafana pod:
   ```bash
   kubectl exec -n monitoring deployment/grafana -- curl http://prometheus:9090/-/healthy
   ```

## Next Steps

1. Create custom Grafana dashboards
2. Set up alerting with Alertmanager
3. Configure log aggregation
4. Implement SLO monitoring
5. Add more custom metrics to applications
