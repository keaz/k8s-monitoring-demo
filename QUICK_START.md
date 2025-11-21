# Quick Start Guide - Kafka Monitoring Demo

## Current Status

✅ All services are deployed and running
✅ Kafka cluster is operational
✅ Port forwarding is active
✅ Ready to use!

## Access URLs

| Service | URL | Credentials |
|---------|-----|-------------|
| **Grafana** | http://localhost:3000 | admin / admin |
| **Prometheus** | http://localhost:9090 | - |
| **Jaeger UI** | http://localhost:16686 | - |
| **Service-A API** | http://localhost:8888 | - |

## Quick Commands

### Send a Kafka Message
```bash
curl http://localhost:8888/api/kafka/send/HelloWorld
```

### Generate Traffic (30 seconds)
```bash
DURATION=30 ./scripts/generate-kafka-traffic.sh
```

### View Consumer Logs
```bash
# Service-B
kubectl logs -n services deploy/service-b -f | grep Kafka

# Service-C
kubectl logs -n services deploy/service-c -f | grep Kafka
```

### View Traces
1. Open http://localhost:16686
2. Select **service-a** from Service dropdown
3. Click **Find Traces**
4. Click any trace to see Kafka spans

## What to Look For in Jaeger

When you view a trace, you'll see:

1. **HTTP Request Span** - The incoming HTTP request to service-a
2. **Kafka Producer Span** - service-a sending message to Kafka
   - Tags: `messaging.system=kafka`, `messaging.destination=service-events`
3. **Consumer Traces** (separate) - service-b and service-c processing
   - Check logs to correlate: `kubectl logs -n services deploy/service-b`

## Grafana Dashboards

Create a new dashboard with these queries:

### Message Rate
```promql
rate(kafka_server_brokertopicmetrics_messagesin_total[1m])
```

### Consumer Lag
```promql
kafka_consumergroup_lag
```

### Throughput
```promql
rate(kafka_server_brokertopicmetrics_bytesin_total[1m])
```

## Check System Health

```bash
# All pods status
kubectl get pods -n services
kubectl get pods -n monitoring

# Kafka metrics endpoint
kubectl exec -n services kafka-0 -c kafka -- curl -s http://localhost:5556/metrics | head -20
```

## Stopping Port Forwards

When you're done, stop the port forwards:

```bash
# Find the kubectl port-forward processes
ps aux | grep "kubectl port-forward"

# Kill them
pkill -f "kubectl port-forward"
```

## Next Time You Start

1. Ensure Kind cluster is running: `kind get clusters`
2. Check pods: `kubectl get pods -A`
3. Start port forwards: `./scripts/port-forward.sh`
4. Send test message: `curl http://localhost:8888/api/kafka/send/Test`

## Architecture Overview

```
┌──────────┐
│ Browser  │
└─────┬────┘
      │
      ▼
┌──────────────────────────────────┐
│   Monitoring UIs (localhost)     │
│  Grafana:3000  Jaeger:16686      │
│  Prometheus:9090                 │
└──────────────────────────────────┘
      │
      ▼
┌──────────────────────────────────┐
│     Kubernetes (Kind)            │
│                                  │
│  Service-A ──▶ Kafka ──▶ Service-B │
│                  │                │
│                  └─▶ Service-C     │
│                                  │
│  Prometheus ◀── Exporters        │
│  OTEL Collector ◀── Services     │
└──────────────────────────────────┘
```

## Troubleshooting

**Can't access URLs?**
- Check port forwards are running: `ps aux | grep port-forward`
- Restart: `./scripts/port-forward.sh`

**No traces in Jaeger?**
- Wait 10-20 seconds for traces to propagate
- Send more messages: `curl http://localhost:8888/api/kafka/send/Test`
- Check service-a logs: `kubectl logs -n services deploy/service-a`

**Kafka metrics not showing?**
- Check Prometheus targets: http://localhost:9090/targets
- Look for `kafka-jmx` and `kafka-exporter` (should be UP)
- Restart Prometheus: `kubectl rollout restart deployment/prometheus -n monitoring`

## More Information

- Full documentation: [KAFKA_SETUP.md](KAFKA_SETUP.md)
- Original README: [README.md](README.md)
