# VictoriaMetrics Dashboard (ID: 24134) - Quick Start Guide

## ✅ What's Been Configured

I've successfully added **VictoriaMetrics** and **VictoriaTraces** to your monitoring stack to support the VictoriaTraces Cluster dashboard (ID: 24134).

### Deployed Components

| Component | Status | Port | Purpose |
|-----------|--------|------|---------|
| **VictoriaMetrics** | ✅ Running | 30003 | Metrics storage (receives from Prometheus) |
| **VictoriaTraces** | ✅ Running | 30004 | Trace storage (Jaeger-compatible) |
| **Prometheus** | ✅ Updated | 30000 | Now sends data to VictoriaMetrics via remote write |
| **OTEL Collector** | ✅ Updated | - | Now sends metrics to VictoriaMetrics |
| **Grafana** | ✅ Updated | 30001 | New datasources added |

## 🚀 Quick Start - Import the Dashboard Now!

### Step 1: Generate Traffic (Required)

The dashboard needs data. Start the traffic generator:

```bash
cd /home/Kasun/Development/RnD/Monitoring/K8S/k8s-monitoring-demo

# Generate traffic
./scripts/generate-traffic.sh
```

**Leave this running** for a few minutes to generate metrics and traces.

### Step 2: Import Dashboard into Grafana

1. **Open Grafana**: http://localhost:3000
2. **Login**: admin / admin
3. **Navigate to Import**:
   - Click the "+" icon (Create) in the left sidebar
   - Select "Import"
4. **Enter Dashboard ID**:
   - Type: **24134**
   - Click "Load"
5. **Configure the Dashboard**:
   - **Name**: VictoriaTraces Cluster (or customize)
   - **Folder**: Select "General" or create a new folder
   - **Select datasource**: Choose **"VictoriaMetrics"**
6. **Click "Import"**

That's it! The dashboard should now load with your metrics.

### Step 3: Wait for Data (2-3 minutes)

- The dashboard may initially show "No Data"
- Wait 2-3 minutes for metrics to accumulate in VictoriaMetrics
- Refresh the dashboard
- You should see metrics appearing!

## 📊 What the Dashboard Shows

The VictoriaTraces Cluster dashboard (24134) displays:

### System Metrics
- **Request Rate**: Incoming requests per second
- **Response Time**: Latency percentiles (P50, P95, P99)
- **Error Rate**: Failed requests
- **Throughput**: Data volume

### Service Metrics
- **Active Services**: Number of reporting services
- **Service Health**: Up/down status
- **Service Load**: Requests per service

### Storage Metrics
- **Data Points**: Total metrics stored
- **Disk Usage**: Storage consumption
- **Ingestion Rate**: Metrics/second being written

## 🔧 Available Datasources in Grafana

After the update, you have these datasources:

| Datasource | Type | URL | Purpose |
|------------|------|-----|---------|
| **Prometheus** (default) | Prometheus | http://prometheus:9090 | Original metrics |
| **VictoriaMetrics** | Prometheus | http://victoriametrics:8428 | Enhanced metrics storage |
| **Jaeger** | Jaeger | http://jaeger-query:16686 | Original traces |
| **VictoriaTraces** | Jaeger | http://victoriatraces:8428 | Enhanced trace storage |

## 🎯 Verify Everything is Working

### Check VictoriaMetrics is Receiving Data

```bash
# Query VictoriaMetrics directly
curl -s 'http://localhost:30003/api/v1/query?query=up' | python3 -m json.tool

# Should show results with "status": "success"
```

### Check Services are Running

```bash
kubectl get pods -n monitoring

# All should be Running:
# - victoriametrics-xxx    1/1   Running
# - victoriatraces-xxx     1/1   Running
# - prometheus-xxx         1/1   Running
# - grafana-xxx            1/1   Running
# - otel-collector-xxx     1/1   Running
```

### Check Prometheus Remote Write

```bash
# Check Prometheus logs for remote write
kubectl logs -n monitoring deployment/prometheus | grep "remote"

# Should see successful remote write operations
```

## 📈 Sample Queries for VictoriaMetrics

Once you have data, try these in Grafana (using VictoriaMetrics datasource):

### Service Metrics
```promql
# Request rate by service
sum by (service_name) (rate(http_requests_total[1m]))

# P95 latency
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))

# Error rate
rate(http_requests_total{status=~"5.."}[1m])
```

### System Metrics
```promql
# CPU usage
rate(node_cpu_seconds_total{mode!="idle"}[5m])

# Memory usage
node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes

# Disk usage
node_filesystem_avail_bytes / node_filesystem_size_bytes
```

## 🎨 Customize the Dashboard

After importing, you can:

1. **Edit Panels**: Click panel title → Edit
2. **Change Time Range**: Top-right dropdown
3. **Add Variables**: Dashboard settings → Variables
4. **Modify Queries**: Edit any panel to change queries
5. **Save Changes**: Click "Save dashboard" icon

## 🔍 Troubleshooting

### Dashboard Shows "No Data"

**Solution**:
1. Ensure traffic is being generated: `./scripts/generate-traffic.sh`
2. Wait 2-3 minutes for data to accumulate
3. Check time range (top-right) includes "now"
4. Verify datasource is "VictoriaMetrics"

### VictoriaMetrics Not Receiving Data

```bash
# Check Prometheus remote write status
kubectl logs -n monitoring deployment/prometheus | grep -i remote

# Check VictoriaMetrics logs
kubectl logs -n monitoring deployment/victoriametrics

# Restart Prometheus
kubectl rollout restart deployment/prometheus -n monitoring
```

### Dashboard Import Fails

**Solution**:
1. Ensure you're using dashboard ID: **24134**
2. Select "VictoriaMetrics" as the datasource (NOT Prometheus)
3. Try downloading JSON from https://grafana.com/grafana/dashboards/24134
4. Import via "Upload JSON file"

### Grafana Datasources Not Showing

```bash
# Restart Grafana
kubectl rollout restart deployment/grafana -n monitoring

# Wait for restart
kubectl wait --for=condition=available deployment/grafana -n monitoring

# Refresh Grafana in browser
```

## 🌟 Additional Dashboards to Try

While you're at it, import these popular dashboards using VictoriaMetrics:

| ID | Name | Purpose |
|----|------|---------|
| **1860** | Node Exporter Full | System metrics |
| **3662** | Prometheus 2.0 Stats | Prometheus metrics |
| **13473** | VictoriaMetrics Single | VictoriaMetrics monitoring |
| **12683** | VictoriaMetrics Cluster | Cluster metrics |

Import the same way: Dashboards → Import → Enter ID → Select VictoriaMetrics

## 📚 Access Points Summary

| Service | URL | Credentials |
|---------|-----|-------------|
| **Grafana** | http://localhost:3000 | admin / admin |
| **Prometheus** | http://localhost:9090 | - |
| **VictoriaMetrics** | http://localhost:30003 | - |
| **VictoriaTraces** | http://localhost:30004 | - |
| **Jaeger** | http://localhost:16686 | - |
| **Gateway API** | http://localhost:30080 | - |

## 🎯 Next Steps

1. ✅ **Import Dashboard 24134** (follow steps above)
2. **Explore the Dashboard**: See all the metrics
3. **Create Custom Dashboards**: Use VictoriaMetrics datasource
4. **Compare Performance**: Try same queries in Prometheus vs VictoriaMetrics
5. **Monitor Long-term**: VictoriaMetrics is more efficient for long-term storage

## 💡 Tips

- **Best Performance**: Use VictoriaMetrics for queries over large time ranges
- **Development**: Use Prometheus for recent data (faster for small windows)
- **Production**: VictoriaMetrics is more resource-efficient
- **Redundancy**: Keep both - you have dual storage now!

## 📖 Learn More

- **Dashboard**: https://grafana.com/grafana/dashboards/24134
- **VictoriaMetrics Docs**: https://docs.victoriametrics.com/
- **PromQL Guide**: https://prometheus.io/docs/prometheus/latest/querying/basics/
- **Detailed Setup**: See `docs/VICTORIAMETRICS_SETUP.md`

## ✅ Summary

You're all set! You now have:

- ✅ VictoriaMetrics collecting all metrics
- ✅ VictoriaTraces for distributed tracing
- ✅ Enhanced Grafana datasources
- ✅ Ready to import dashboard 24134
- ✅ Traffic generator running
- ✅ Full observability stack

**Import the dashboard now and enjoy the enhanced monitoring!** 🎉
