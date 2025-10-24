# Quick Start Guide

Get the monitoring demo up and running in minutes!

## Current Status

✅ Kubernetes cluster created (kind-monitoring-demo)
✅ Monitoring stack deployed
✅ Prometheus, Grafana, Jaeger, OTEL Collector running
✅ Node Exporter for system metrics
✅ Project structure and documentation created

## Access Monitoring Dashboards

The monitoring stack is already deployed and accessible:

| Service | URL | Credentials |
|---------|-----|-------------|
| **Prometheus** | http://localhost:9090 | None |
| **Grafana** | http://localhost:3000 | admin / admin |
| **Jaeger** | http://localhost:16686 | None |

## Quick Commands

### View Cluster Status

```bash
# Get cluster info
kubectl cluster-info --context kind-monitoring-demo

# View all nodes
kubectl get nodes

# View monitoring pods
kubectl get pods -n monitoring

# View service pods
kubectl get pods -n services
```

### Check Monitoring Stack

```bash
# Prometheus
kubectl get pods -n monitoring -l app=prometheus

# Grafana
kubectl get pods -n monitoring -l app=grafana

# Jaeger
kubectl get pods -n monitoring -l app=jaeger

# OTEL Collector
kubectl get pods -n monitoring -l app=otel-collector

# Node Exporter (DaemonSet - runs on each node)
kubectl get daemonset -n monitoring node-exporter
```

### View Logs

```bash
# Prometheus logs
kubectl logs -n monitoring -l app=prometheus --tail=50

# Grafana logs
kubectl logs -n monitoring -l app=grafana --tail=50

# Jaeger logs
kubectl logs -n monitoring -l app=jaeger --tail=50

# OTEL Collector logs
kubectl logs -n monitoring -l app=otel-collector --tail=50
```

## Deploy Sample Applications

### Option 1: Deploy User Service (Java)

The user-service is already defined but needs to be built:

```bash
# Build the Docker image
cd services/java/user-service
docker build -t user-service:latest .

# Load into kind cluster
kind load docker-image user-service:latest --name monitoring-demo

# Deploy to Kubernetes
kubectl apply -f ../../kubernetes/base/services/user-service.yaml

# Check deployment
kubectl get pods -n services
kubectl get svc -n services

# Test the service
kubectl port-forward -n services svc/user-service 8080:80
curl http://localhost:8080/api/users/1
```

### Option 2: Use Kustomize to Deploy Everything

```bash
# Deploy using kustomize
kubectl apply -k kubernetes/overlays/dev/

# Check all resources
kubectl get all -n monitoring
kubectl get all -n services
```

## Testing the Monitoring Stack

### 1. Verify Prometheus is Scraping

Open http://localhost:9090 and go to:
- **Status → Targets** - See all scrape targets
- **Status → Configuration** - View Prometheus config
- **Status → Service Discovery** - See discovered Kubernetes services

Try some queries:
```promql
# See all metrics
{__name__=~".+"}

# Node CPU usage
rate(node_cpu_seconds_total[5m])

# Memory usage
node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes

# Container metrics
container_cpu_usage_seconds_total
```

### 2. Explore Grafana Dashboards

1. Open http://localhost:3000
2. Login with `admin` / `admin`
3. Go to **Configuration → Data Sources**
   - Verify Prometheus connection
   - Verify Jaeger connection
4. Create a new dashboard:
   - Click "+" → Dashboard
   - Add Panel
   - Select Prometheus datasource
   - Enter query: `rate(node_cpu_seconds_total[5m])`
   - Save dashboard

### 3. View Traces in Jaeger

1. Open http://localhost:16686
2. Once services are deployed and receiving traffic:
   - Select service from dropdown
   - Click "Find Traces"
   - Explore trace details

## Generate Test Traffic

If you have a service deployed:

```bash
# Port forward to service
kubectl port-forward -n services svc/user-service 8080:80

# Generate requests
for i in {1..100}; do
  curl http://localhost:8080/api/users/1
  sleep 0.1
done
```

Then check:
- **Prometheus**: Query `rate(http_server_requests_seconds_count[1m])`
- **Grafana**: Create panel with request rate
- **Jaeger**: View distributed traces

## Common Tasks

### Restart a Component

```bash
# Restart Prometheus
kubectl rollout restart deployment/prometheus -n monitoring

# Restart Grafana
kubectl rollout restart deployment/grafana -n monitoring

# Restart OTEL Collector
kubectl rollout restart deployment/otel-collector -n monitoring
```

### Scale a Service

```bash
# Scale user-service to 3 replicas
kubectl scale deployment/user-service -n services --replicas=3

# Verify
kubectl get pods -n services
```

### View Resource Usage

```bash
# Overall cluster resources
kubectl top nodes

# Pod resources (requires metrics-server)
kubectl top pods -n monitoring
kubectl top pods -n services
```

## Project Structure Overview

```
k8s-monitoring-demo/
├── README.md                     # Main documentation
├── QUICKSTART.md                 # This file
├── kind-config.yaml              # Kind cluster configuration
├── kubernetes/
│   ├── base/                     # Base Kubernetes manifests
│   │   ├── namespaces.yaml
│   │   ├── prometheus/           # Prometheus configuration
│   │   ├── grafana/              # Grafana configuration
│   │   ├── jaeger/               # Jaeger tracing
│   │   ├── otel-collector/       # OpenTelemetry Collector
│   │   ├── node-exporter/        # Node metrics
│   │   ├── services/             # Application services
│   │   └── kustomization.yaml
│   └── overlays/
│       └── dev/                  # Dev environment overlay
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
│   └── build-and-deploy.sh      # Automated deployment
└── docs/
    ├── MONITORING_SETUP.md       # Detailed setup guide
    ├── PROMETHEUS.md             # Prometheus guide
    ├── GRAFANA.md                # Grafana guide
    └── OTEL_TRACING.md           # OpenTelemetry guide
```

## Useful Prometheus Queries

```promql
# CPU usage by node
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Memory usage by node
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100

# Disk usage
(1 - (node_filesystem_avail_bytes / node_filesystem_size_bytes)) * 100

# Network traffic
rate(node_network_receive_bytes_total[5m])
rate(node_network_transmit_bytes_total[5m])

# HTTP request rate (when services are deployed)
rate(http_server_requests_seconds_count[1m])

# HTTP request duration P95
histogram_quantile(0.95, rate(http_server_requests_seconds_bucket[5m]))

# Error rate
rate(http_server_requests_seconds_count{status=~"5.."}[1m])
```

## Grafana Dashboard Ideas

### Node Overview Dashboard
- CPU usage per node
- Memory usage per node
- Disk I/O
- Network I/O

### Application Dashboard
- Request rate
- Error rate
- Request duration (P50, P95, P99)
- Active connections

### Kubernetes Dashboard
- Pods per namespace
- Container restarts
- Resource usage by pod

## Next Steps

1. **Build and deploy services**: Follow instructions in README.md
2. **Create Grafana dashboards**: Visualize your metrics
3. **Set up alerts**: Configure Alertmanager
4. **Add more services**: Deploy remaining Java and Rust services
5. **Customize**: Adjust configurations for your needs

## Cleanup

When done experimenting:

```bash
# Delete the entire cluster
kind delete cluster --name monitoring-demo

# Or just delete applications
kubectl delete -k kubernetes/overlays/dev/
```

## Troubleshooting

### Pods not starting

```bash
# Check pod status
kubectl get pods -n monitoring
kubectl describe pod <pod-name> -n monitoring

# Check logs
kubectl logs <pod-name> -n monitoring
```

### Can't access dashboards

```bash
# Verify port mappings
docker ps | grep monitoring-demo

# Verify services
kubectl get svc -n monitoring

# Check NodePort configuration
kubectl get svc prometheus -n monitoring -o yaml | grep nodePort
```

### Prometheus not scraping

1. Check Prometheus targets: http://localhost:9090/targets
2. Verify pod annotations:
   ```bash
   kubectl get pod <pod-name> -n services -o yaml | grep annotations -A 5
   ```
3. Check Prometheus logs for errors

## Resources

- Main documentation: [README.md](README.md)
- Detailed setup: [docs/MONITORING_SETUP.md](docs/MONITORING_SETUP.md)
- Prometheus docs: https://prometheus.io/docs/
- Grafana docs: https://grafana.com/docs/
- Jaeger docs: https://www.jaegertracing.io/docs/
- OpenTelemetry docs: https://opentelemetry.io/docs/

## Support

For issues or questions:
1. Check the documentation in `docs/`
2. Review Kubernetes events: `kubectl get events -n monitoring`
3. Check pod logs: `kubectl logs <pod-name> -n monitoring`
