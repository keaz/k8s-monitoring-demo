# OpenTelemetry Java Agent Setup

## Container Build Checklist
- Download the agent during the image build: `ADD https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v2.0.0/opentelemetry-javaagent.jar /app/opentelemetry-javaagent.jar`.
- Expose both the application port and Prometheus metrics port: `EXPOSE 8080 9464`.
- Launch the JVM with the agent attached: `ENTRYPOINT ["java", "-javaagent:/app/opentelemetry-javaagent.jar", "-jar", "app.jar"]`.
- Keep the service name out of source code; inject it via environment variables so the same image can run in multiple environments.

## Required Runtime Configuration
Set these environment variables for each service (Kubernetes manifests already provide sensible defaults):

| Variable | Purpose |
| --- | --- |
| `OTEL_SERVICE_NAME` | Logical service identifier (e.g. `service-a`). |
| `OTEL_TRACES_EXPORTER=otlp` | Sends spans with the OTLP protocol. |
| `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=http://jaeger-collector.monitoring.svc.cluster.local:4317` | Targets the Jaeger collector’s OTLP gRPC endpoint. |
| `OTEL_EXPORTER_OTLP_TRACES_PROTOCOL=grpc` | Explicitly selects gRPC transport. |
| `OTEL_EXPORTER_OTLP_TRACES_INSECURE=true` | Allows plaintext (no TLS) inside the cluster. |
| `OTEL_METRICS_EXPORTER=prometheus` | Exposes metrics via an embedded Prometheus endpoint. |
| `OTEL_EXPORTER_PROMETHEUS_HOST=0.0.0.0` | Listens on all interfaces inside the pod. |
| `OTEL_EXPORTER_PROMETHEUS_PORT=9464` | Prometheus scrape port, matching the Service annotations. |
| `OTEL_LOGS_EXPORTER=none` | Disables log export when only traces/metrics are required. |

The agent accepts the same settings through Java system properties (`-Dotel.metrics.exporter=prometheus`) if you prefer property files over environment variables.

## Kubernetes Integration
- Add Prometheus annotations to the pod template:
  ```yaml
  prometheus.io/scrape: "true"
  prometheus.io/port: "9464"
  prometheus.io/path: "/metrics"
  ```
- Publish a `metrics` named container port at `9464` and surface it through the service manifest so Prometheus discovers the endpoint.
- Depend on cluster-local service URLs for downstream calls (e.g. `SERVICE_B_URL=http://service-b.services.svc.cluster.local:8081`).
- After deployment, confirm traces arrive via `kubectl port-forward -n monitoring svc/jaeger-query 16686:16686` and metrics populate Prometheus at `http://localhost:9090`.

With this setup each Java service automatically emits Jaeger traces and Prometheus metrics without touching application code, letting you iterate quickly on business logic while retaining full telemetry coverage.
