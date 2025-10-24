# Troubleshooting Guide

## Common Issues and Solutions

### 1. Cannot Access Prometheus/Grafana/Jaeger UIs

**Symptoms:**
- Browser shows "connection refused" when accessing http://localhost:9090, http://localhost:3000, or http://localhost:16686
- curl returns HTTP 000

**Root Cause:**
Service selectors don't match pod labels, resulting in empty endpoints.

**Check:**
```bash
# Check if endpoints are populated
kubectl get endpoints -n monitoring prometheus grafana jaeger-query

# Should show IP addresses like:
# prometheus     10.244.2.29:9090
# grafana        10.244.1.53:3000
# jaeger-query   10.244.1.42:16686

# If they show <none>, labels don't match
```

**Solution:**
```bash
# Fix the service selectors
kubectl patch svc prometheus -n monitoring --type json -p='[{"op": "replace", "path": "/spec/selector", "value": {"app": "prometheus"}}]'
kubectl patch svc grafana -n monitoring --type json -p='[{"op": "replace", "path": "/spec/selector", "value": {"app": "grafana"}}]'
kubectl patch svc jaeger-query -n monitoring --type json -p='[{"op": "replace", "path": "/spec/selector", "value": {"app": "jaeger"}}]'

# Verify
kubectl get endpoints -n monitoring
```

**Permanent Fix:**
The kustomization overlay has been updated to use `labels` instead of `commonLabels` to prevent this issue.

### 2. Kind Cluster Port Mappings Not Working

**Symptoms:**
- Services work inside cluster but not from localhost
- `curl http://localhost:9090` fails

**Check:**
```bash
# Verify Kind container has port mappings
docker ps --filter "name=monitoring-demo-control-plane" --format "table {{.Names}}\t{{.Ports}}"

# Should show:
# 0.0.0.0:9090->30000/tcp
# 0.0.0.0:3000->30001/tcp
# 0.0.0.0:16686->30002/tcp
```

**Solution:**
Port mappings must be configured when creating the cluster. If missing, recreate:
```bash
kind delete cluster --name monitoring-demo
kind create cluster --config kind-config.yaml
# Then redeploy
./scripts/build-and-deploy.sh
```

### 3. Pods Crashing After Restart

**Prometheus: "lock DB directory: resource temporarily unavailable"**

**Cause:** Multiple pods trying to access the same PVC

**Solution:**
```bash
# Delete the failing pod, let the old one continue
kubectl delete pod <new-prometheus-pod> -n monitoring

# Only restart if absolutely necessary, and ensure old pod is terminated first
kubectl delete pod <old-prometheus-pod> -n monitoring
# Wait for it to fully terminate before new one starts
```

**Grafana: Plugin download timeout**

**Cause:** Network issues or Grafana.com unavailable

**Solution:**
```bash
# Check Grafana config for plugin requirements
kubectl get configmap grafana-config -n monitoring -o yaml

# If plugins are not critical, comment them out temporarily
# Or increase init timeout in the deployment
```

### 4. Java Services Not Receiving Traffic

**Check:**
```bash
# Verify Java services are running
kubectl get pods -n services -l app=service-a

# Check logs
kubectl logs -n services -l app=service-a --tail=50

# Test direct access
kubectl port-forward -n services svc/service-a 8080:80
curl http://localhost:8080/api/hello
```

**Gateway not routing:**
```bash
# Rebuild gateway with Java proxy
cd services/mock-services
docker build -t mock-service:latest .
kind load docker-image mock-service:latest
kubectl rollout restart deployment/gateway-service -n services
```

### 5. No Traces in Jaeger

**Check:**
```bash
# Verify OTEL collector is running
kubectl get pods -n monitoring -l app=otel-collector

# Check OTEL collector logs
kubectl logs -n monitoring -l app=otel-collector --tail=50

# Verify Jaeger collector is receiving data
kubectl logs -n monitoring -l app=jaeger --tail=50 | grep -i "span"
```

**Solution:**
Verify OTLP endpoints in service deployments:
```bash
# For Java services
kubectl get deployment service-a -n services -o yaml | grep OTEL

# Should point to jaeger-collector:4317
```

### 6. No Metrics in Prometheus

**Check scrape targets:**
```bash
# Access Prometheus UI: http://localhost:9090
# Go to Status > Targets
# All targets should show "UP"
```

**Fix common issues:**
```bash
# Check if Prometheus can reach services
kubectl exec -n monitoring deploy/prometheus -- wget -qO- http://service-a.services.svc.cluster.local:9464/metrics

# Verify service annotations
kubectl get svc service-a -n services -o yaml | grep prometheus.io

# Should have:
# prometheus.io/scrape: "true"
# prometheus.io/port: "9464"
# prometheus.io/path: "/metrics"
```

### 7. VictoriaMetrics Connection Refused

**Symptoms:**
Prometheus logs show:
```
Failed to send batch, retrying: connection refused
```

**This is normal if:**
- VictoriaMetrics is used for long-term storage
- The error appears during VictoriaMetrics restarts

**Fix if persistent:**
```bash
# Check VictoriaMetrics is running
kubectl get pods -n monitoring -l app=victoriametrics

# Verify service endpoint
kubectl get svc victoriametrics -n monitoring

# Check VictoriaMetrics logs
kubectl logs -n monitoring -l app=victoriametrics --tail=50
```

## Useful Commands

### Quick Health Check
```bash
# All monitoring pods
kubectl get pods -n monitoring

# All service pods
kubectl get pods -n services

# Check all endpoints
kubectl get endpoints --all-namespaces | grep -v "<none>"

# Test external access
curl -s http://localhost:9090/-/healthy && echo " - Prometheus OK"
curl -s http://localhost:3000/api/health && echo " - Grafana OK"
curl -s http://localhost:16686/ && echo " - Jaeger OK"
```

### View Logs
```bash
# Streaming logs
kubectl logs -n monitoring -l app=prometheus -f

# Last 100 lines with timestamps
kubectl logs -n monitoring -l app=prometheus --tail=100 --timestamps

# Logs from all containers in namespace
kubectl logs -n monitoring --all-containers=true --tail=20
```

### Resource Usage
```bash
# Pod resource usage
kubectl top pods -n monitoring
kubectl top pods -n services

# Node resource usage
kubectl top nodes
```

### Port Forwarding (Alternative Access)
```bash
# If NodePort doesn't work, use port-forward
kubectl port-forward -n monitoring svc/prometheus 9090:9090 &
kubectl port-forward -n monitoring svc/grafana 3000:3000 &
kubectl port-forward -n monitoring svc/jaeger-query 16686:16686 &
```

## Getting Help

If issues persist:

1. **Collect diagnostics:**
   ```bash
   kubectl describe pod <pod-name> -n <namespace>
   kubectl logs <pod-name> -n <namespace> --previous  # Previous crash logs
   kubectl get events -n <namespace> --sort-by='.lastTimestamp'
   ```

2. **Check Kubernetes cluster:**
   ```bash
   kubectl cluster-info
   kubectl get nodes
   kubectl get all --all-namespaces
   ```

3. **Verify Docker/Kind:**
   ```bash
   docker ps
   kind get clusters
   ```

## Access URLs

After fixing the issues, these should work:

- **Prometheus**: http://localhost:9090
- **Grafana**: http://localhost:3000 (default login: admin/admin)
- **Jaeger UI**: http://localhost:16686
- **VictoriaMetrics**: http://localhost:30003
- **Gateway Service**: http://localhost:30080

## Expected Status

All pods should be Running:
```bash
kubectl get pods -n monitoring
# Expected:
# grafana-xxx              1/1     Running
# jaeger-xxx               1/1     Running
# otel-collector-xxx       1/1     Running
# prometheus-xxx           1/1     Running
# victoriametrics-xxx      1/1     Running
```

All endpoints should have IPs (not `<none>`):
```bash
kubectl get endpoints -n monitoring
```
