# Persistent Storage for Monitoring Stack

## Overview

The monitoring stack has been configured with persistent storage to ensure data retention across pod restarts and cluster maintenance. This makes the setup production-ready by preventing data loss.

## Storage Architecture

All monitoring components now use **PersistentVolumeClaims (PVCs)** backed by the cluster's storage provisioner (local-path for kind clusters).

### Storage Components

| Component | Storage Size | Purpose | Data Stored |
|-----------|-------------|---------|-------------|
| **Prometheus** | 10 Gi | Metrics storage with 7-day retention | Time-series metrics, WAL, indexes |
| **VictoriaMetrics** | 20 Gi | Long-term metrics storage (14-day retention) | Compressed time-series, indexes |
| **VictoriaTraces** | 10 Gi | Distributed traces storage | Trace spans, metadata |
| **Grafana** | 2 Gi | Dashboard and user data | Dashboards, users, settings, plugins |
| **Jaeger** | 10 Gi | Distributed traces (badger storage) | Trace spans, indexes |

## Retention Policies

### Prometheus: 7 Days
Configured with `--storage.tsdb.retention.time=7d` flag. This means:
- Metrics are kept for 1 week
- After 7 days, old data is automatically purged
- Suitable for recent operational monitoring

### VictoriaMetrics: 14 Days
Configured with `-retentionPeriod=14d` flag. This provides:
- 2 weeks of historical data
- More efficient compression than Prometheus
- Better for trend analysis and longer-term views

### Jaeger: No automatic cleanup
Badger storage doesn't have built-in TTL. For production:
- Monitor disk usage
- Implement manual cleanup scripts if needed
- Consider switching to Cassandra/Elasticsearch for large-scale deployments

### VictoriaTraces: Default retention
- Inherits VictoriaMetrics storage characteristics
- More efficient than standard Jaeger storage

## PersistentVolumeClaims (PVCs)

All PVCs are defined in: `kubernetes/base/storage/monitoring-pvcs.yaml`

### PVC Specifications

```yaml
accessModes: ReadWriteOnce (RWO)
storageClassName: standard (local-path for kind)
reclaimPolicy: Delete (PVs deleted when PVCs are deleted)
```

### Viewing PVCs

```bash
# List all PVCs
kubectl get pvc -n monitoring

# Get detailed info
kubectl describe pvc prometheus-storage -n monitoring

# Check which pod is using a PVC
kubectl get pods -n monitoring -o json | jq '.items[] | select(.spec.volumes[]?.persistentVolumeClaim.claimName=="prometheus-storage") | .metadata.name'
```

## PersistentVolumes (PVs)

PVs are automatically provisioned by the storage class.

### Viewing PVs

```bash
# List all PVs
kubectl get pv

# Get detailed info
kubectl describe pv <pv-name>

# Check PV usage
kubectl get pv -o custom-columns=NAME:.metadata.name,CAPACITY:.spec.capacity.storage,STATUS:.status.phase,CLAIM:.spec.claimName
```

## Storage Verification

### Check Prometheus Storage

```bash
# View Prometheus data directory
kubectl exec -n monitoring deployment/prometheus -- ls -lh /prometheus

# Check retention configuration
kubectl get deployment prometheus -n monitoring -o jsonpath='{.spec.template.spec.containers[0].args}' | grep retention

# Monitor Prometheus disk usage
kubectl exec -n monitoring deployment/prometheus -- du -sh /prometheus
```

### Check VictoriaMetrics Storage

```bash
# View storage directory
kubectl exec -n monitoring deployment/victoriametrics -- ls -lh /storage

# Check storage size
kubectl exec -n monitoring deployment/victoriametrics -- du -sh /storage
```

### Check Grafana Storage

```bash
# View Grafana data directory
kubectl exec -n monitoring deployment/grafana -- ls -lh /var/lib/grafana

# Check database
kubectl exec -n monitoring deployment/grafana -- ls -lh /var/lib/grafana/grafana.db
```

### Check Jaeger Storage

```bash
# View badger storage
kubectl exec -n monitoring deployment/jaeger -- ls -lh /badger

# Check data and key directories
kubectl exec -n monitoring deployment/jaeger -- du -sh /badger/*
```

## Data Persistence Testing

### Test 1: Pod Restart

```bash
# Delete a pod
kubectl delete pod -n monitoring <pod-name>

# Wait for pod to restart
kubectl wait --for=condition=ready pod -l app=prometheus -n monitoring

# Verify data is still present
kubectl exec -n monitoring deployment/prometheus -- ls -lh /prometheus
```

### Test 2: Deployment Rollout

```bash
# Restart deployment
kubectl rollout restart deployment/prometheus -n monitoring

# Verify data persists
# Old metrics should still be queryable in Grafana
```

### Test 3: Check Historical Data

```bash
# Query old metrics (within retention period)
curl 'http://localhost:9090/api/v1/query?query=up&time=<timestamp-from-yesterday>'
```

## Storage Monitoring

### Disk Usage Alerts

Monitor these metrics to avoid running out of disk:

```promql
# Prometheus disk usage
prometheus_tsdb_storage_blocks_bytes / (10 * 1024^3) * 100

# Node disk usage (where PVs are stored)
(node_filesystem_size_bytes - node_filesystem_avail_bytes) / node_filesystem_size_bytes * 100
```

### Storage Growth Rate

```promql
# Prometheus storage growth rate (bytes per hour)
rate(prometheus_tsdb_storage_blocks_bytes[1h])

# VictoriaMetrics storage size
vm_data_size_bytes
```

## Production Considerations

### 1. Increase Storage Size for Production

Edit PVC sizes in `kubernetes/base/storage/monitoring-pvcs.yaml`:

```yaml
resources:
  requests:
    storage: 100Gi  # Increase as needed
```

### 2. Use Better Storage Class

For production Kubernetes clusters, use:
- **AWS**: `gp3` (SSD) or `io2` (high IOPS)
- **GCP**: `pd-ssd` (SSD) or `pd-balanced`
- **Azure**: `managed-premium` or `managed-standard`
- **On-prem**: Ceph RBD, NFS, or local SSDs with replication

Example for AWS:
```yaml
storageClassName: gp3
```

### 3. Enable Volume Snapshots

```bash
# Create snapshot
kubectl create -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: prometheus-snapshot
  namespace: monitoring
spec:
  volumeSnapshotClassName: csi-snapclass
  source:
    persistentVolumeClaimName: prometheus-storage
EOF
```

### 4. Backup Strategy

Implement regular backups:

```bash
# Prometheus snapshot API
curl -X POST http://localhost:9090/api/v1/admin/tsdb/snapshot

# VictoriaMetrics snapshot
curl http://localhost:30003/snapshot/create

# Copy snapshots to remote storage (S3, GCS, etc.)
```

### 5. Adjust Retention Periods

For production, consider:
- **Prometheus**: 7-14 days (operational metrics)
- **VictoriaMetrics**: 30-90 days (trend analysis)
- **Jaeger**: Configure TTL or use Elasticsearch with ILM

Edit deployments to change retention:

**Prometheus**:
```yaml
args:
  - '--storage.tsdb.retention.time=14d'  # Increase to 14 days
```

**VictoriaMetrics**:
```yaml
args:
  - -retentionPeriod=30d  # Increase to 30 days
```

## Cleanup and Reclaim

### Delete PVCs (WARNING: Data Loss)

```bash
# Delete specific PVC
kubectl delete pvc prometheus-storage -n monitoring

# Delete all monitoring PVCs
kubectl delete pvc -n monitoring -l app=prometheus
```

### Change PV Reclaim Policy

By default, PVs are deleted when PVCs are deleted. To retain data:

```bash
# List PVs
kubectl get pv

# Change reclaim policy to Retain
kubectl patch pv <pv-name> -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
```

### Manual PV Cleanup

If reclaim policy is "Retain":

```bash
# Delete PVC
kubectl delete pvc prometheus-storage -n monitoring

# PV will remain in "Released" state
kubectl get pv

# Manually delete PV
kubectl delete pv <pv-name>
```

## Storage Migration

### Migrate to Larger Storage

1. Create a snapshot or backup
2. Scale down the deployment
3. Delete the PVC
4. Create new PVC with larger size
5. Restore from backup if needed
6. Scale up deployment

### Example Migration Script

```bash
#!/bin/bash

NAMESPACE="monitoring"
APP="prometheus"
PVC="${APP}-storage"

# Create snapshot (if supported)
echo "Creating snapshot..."
kubectl create -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: ${APP}-snapshot
  namespace: ${NAMESPACE}
spec:
  source:
    persistentVolumeClaimName: ${PVC}
EOF

# Scale down
echo "Scaling down..."
kubectl scale deployment/${APP} -n ${NAMESPACE} --replicas=0

# Delete PVC
echo "Deleting old PVC..."
kubectl delete pvc ${PVC} -n ${NAMESPACE}

# Create new PVC with larger size
echo "Creating new PVC..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${PVC}
  namespace: ${NAMESPACE}
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 50Gi  # Increased size
  storageClassName: standard
EOF

# Restore from snapshot (if needed)
# ... restore logic ...

# Scale up
echo "Scaling up..."
kubectl scale deployment/${APP} -n ${NAMESPACE} --replicas=1
```

## Troubleshooting

### PVC Stuck in Pending

```bash
# Check events
kubectl describe pvc prometheus-storage -n monitoring

# Common causes:
# 1. No storage provisioner
# 2. Insufficient cluster storage
# 3. StorageClass not found
# 4. Node selector constraints not met
```

### PV Not Binding

```bash
# Check PV status
kubectl get pv

# Check if PV matches PVC requirements
kubectl describe pv <pv-name>

# Verify storage class
kubectl get storageclass
```

### Out of Disk Space

```bash
# Check disk usage
kubectl exec -n monitoring deployment/prometheus -- df -h /prometheus

# Reduce retention period (requires restart)
kubectl set env deployment/prometheus -n monitoring PROMETHEUS_RETENTION_TIME=3d

# Or edit deployment directly
kubectl edit deployment prometheus -n monitoring
```

### Data Corruption

```bash
# Check Prometheus WAL
kubectl exec -n monitoring deployment/prometheus -- /bin/prometheus --storage.tsdb.path=/prometheus --check

# If corrupted, may need to delete and restart
kubectl delete pod -n monitoring -l app=prometheus
```

## Summary

Your monitoring stack now has production-ready persistent storage:

✅ **Prometheus**: 10Gi storage, 7-day retention
✅ **VictoriaMetrics**: 20Gi storage, 14-day retention
✅ **VictoriaTraces**: 10Gi persistent traces
✅ **Grafana**: 2Gi for dashboards and config
✅ **Jaeger**: 10Gi badger storage

All data survives pod restarts, deployments, and cluster maintenance. For production environments, increase storage sizes and implement backup strategies.

## Next Steps

1. **Monitor Storage Usage**: Set up alerts for disk usage
2. **Implement Backups**: Regular snapshots or exports
3. **Test Recovery**: Practice restore procedures
4. **Optimize Retention**: Adjust based on actual usage patterns
5. **Consider Long-term Storage**: For metrics older than retention period, consider external systems like S3/GCS with VictoriaMetrics backup

## References

- [Prometheus Storage Documentation](https://prometheus.io/docs/prometheus/latest/storage/)
- [VictoriaMetrics Retention](https://docs.victoriametrics.com/#retention)
- [Kubernetes Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
- [Jaeger Badger Storage](https://www.jaegertracing.io/docs/latest/deployment/#badger---local-storage)
