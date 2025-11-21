# PostgreSQL Exporter Architecture

## Overview

The PostgreSQL exporter can monitor both in-cluster and external databases with zero code changes - just configuration.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                           │
│                                                                   │
│  ┌────────────────────────────────────────────────────────┐    │
│  │              Monitoring Namespace                       │    │
│  │                                                          │    │
│  │  ┌─────────────────────────────────────────────────┐  │    │
│  │  │     PostgreSQL Exporter Deployment              │  │    │
│  │  │                                                   │  │    │
│  │  │  Configuration Priority:                         │  │    │
│  │  │  1. Check postgres-external-config ConfigMap    │  │    │
│  │  │  2. Fallback to default (in-cluster)            │  │    │
│  │  │                                                   │  │    │
│  │  │  Environment Variables:                          │  │    │
│  │  │  - POSTGRES_HOST (from ConfigMap or default)    │  │    │
│  │  │  - POSTGRES_PORT (from ConfigMap or default)    │  │    │
│  │  │  - POSTGRES_SSLMODE (from ConfigMap or default) │  │    │
│  │  │  - POSTGRES_USER (from postgres-config)         │  │    │
│  │  │  - POSTGRES_PASSWORD (from postgres-secret)     │  │    │
│  │  │                                                   │  │    │
│  │  │  Exposes: :9187/metrics                          │  │    │
│  │  └─────────────────────────────────────────────────┘  │    │
│  │            │                                             │    │
│  │            │ connects to                                │    │
│  │            ▼                                             │    │
│  │  ┌──────────────────────────────┐                      │    │
│  │  │  postgres-external-config    │  ◄── Optional        │    │
│  │  │  ConfigMap                    │                      │    │
│  │  │                               │                      │    │
│  │  │  POSTGRES_HOST: "external"   │                      │    │
│  │  │  POSTGRES_PORT: "5432"       │                      │    │
│  │  │  POSTGRES_SSLMODE: "require" │                      │    │
│  │  └──────────────────────────────┘                      │    │
│  │                                                          │    │
│  │  ┌──────────────────────────────┐                      │    │
│  │  │    Prometheus                 │                      │    │
│  │  │                               │                      │    │
│  │  │  Scrapes: postgres-exporter  │                      │    │
│  │  │           :9187/metrics       │                      │    │
│  │  └──────────────────────────────┘                      │    │
│  │                                                          │    │
│  └────────────────────────────────────────────────────────┘    │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
                        │
                        │ TCP :5432 with optional SSL/TLS
                        ▼
        ┌───────────────────────────────────────┐
        │      Database Options (choose one)     │
        └───────────────────────────────────────┘
                        │
        ┌───────────────┴───────────────┐
        │                               │
        ▼                               ▼
┌───────────────────┐          ┌─────────────────────┐
│   In-Cluster      │          │  External Database  │
│   PostgreSQL      │          │                     │
│                   │          │  • AWS RDS          │
│  postgres.        │          │  • Azure Database   │
│  services.        │          │  • GCP Cloud SQL    │
│  svc.cluster.     │          │  • On-Premise       │
│  local:5432       │          │                     │
│                   │          │  Requires:          │
│  Default option   │          │  - Network access   │
│  if external      │          │  - Firewall rules   │
│  config not found │          │  - SSL/TLS          │
└───────────────────┘          └─────────────────────┘
```

## Configuration Flow

### Scenario 1: External Database (Production)

```
1. User creates postgres-external-config ConfigMap
   └─> POSTGRES_HOST: "mydb.rds.amazonaws.com"
   └─> POSTGRES_PORT: "5432"
   └─> POSTGRES_SSLMODE: "require"

2. Exporter reads configuration
   └─> Finds postgres-external-config
   └─> Uses external host values
   └─> Enables SSL

3. Exporter connects
   └─> postgresql://user:pass@mydb.rds.amazonaws.com:5432/db?sslmode=require
   └─> Scrapes metrics
   └─> Exposes to Prometheus
```

### Scenario 2: In-Cluster Database (Development)

```
1. No postgres-external-config ConfigMap exists

2. Exporter uses defaults
   └─> POSTGRES_HOST: "postgres.services.svc.cluster.local"
   └─> POSTGRES_PORT: "5432"
   └─> POSTGRES_SSLMODE: "disable"

3. Exporter connects
   └─> postgresql://user:pass@postgres.services.svc.cluster.local:5432/db
   └─> Scrapes metrics
   └─> Exposes to Prometheus
```

## Connection String Construction

The exporter builds the connection string dynamically:

```bash
DATA_SOURCE_NAME = postgresql://
  $(POSTGRES_USER):                    # From postgres-config ConfigMap
  $(POSTGRES_PASSWORD)@                # From postgres-secret Secret
  $(POSTGRES_HOST:-                    # From postgres-external-config OR
    postgres.services.svc.cluster.local):  # Default fallback
  $(POSTGRES_PORT:-5432)/              # From postgres-external-config OR 5432
  $(POSTGRES_DB)?                      # From postgres-config ConfigMap
  sslmode=$(POSTGRES_SSLMODE:-disable) # From postgres-external-config OR disable
```

## Network Paths

### In-Cluster Database
```
Exporter Pod → Kubernetes Service → PostgreSQL Pod
    ↓              ↓                    ↓
  Container    ClusterIP:5432      Container
  Network      (postgres.services   Network
               .svc.cluster.local)
```

### External Database
```
Exporter Pod → Node → Firewall → External Network → Database
    ↓           ↓        ↓            ↓                ↓
  Container   Host     Security    Internet/VPC    AWS RDS/
  Network    Network    Groups      Peering         Azure/GCP
```

## Security Layers

```
┌─────────────────────────────────────────────────────┐
│ 1. Network Security                                 │
│    • Kubernetes Network Policies                    │
│    • Security Groups / Firewall Rules               │
│    • VPC Peering / Private Link                     │
└─────────────────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────┐
│ 2. Transport Security                               │
│    • SSL/TLS Encryption (sslmode=require)          │
│    • Certificate Verification (optional)            │
└─────────────────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────┐
│ 3. Authentication                                   │
│    • Username/Password (from Kubernetes Secret)     │
│    • IAM Authentication (AWS/GCP)                   │
└─────────────────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────┐
│ 4. Authorization                                    │
│    • Minimal database permissions                   │
│    • Read-only access to system views               │
│    • pg_monitor role (PostgreSQL 10+)               │
└─────────────────────────────────────────────────────┘
```

## Metrics Flow

```
PostgreSQL Database
        │
        │ SQL Queries (custom + default)
        ▼
PostgreSQL Exporter
        │
        │ Transform to Prometheus format
        ▼
Prometheus Metrics Endpoint (:9187/metrics)
        │
        │ HTTP scrape every 15s
        ▼
Prometheus Server
        │
        │ PromQL queries
        ▼
Grafana Dashboard
        │
        │ Visualization
        ▼
User / Alerts
```

## High Availability Setup

For production, you can run multiple exporter instances:

```
┌───────────────────────────────────────────┐
│  Multiple PostgreSQL Exporter Replicas   │
│                                            │
│  ┌────────────┐  ┌────────────┐          │
│  │ Exporter 1 │  │ Exporter 2 │          │
│  │  (Primary) │  │  (Replica) │          │
│  └──────┬─────┘  └──────┬─────┘          │
│         │                │                 │
│         └────────┬───────┘                │
│                  │                         │
└──────────────────┼─────────────────────────┘
                   │
                   ▼
           ┌───────────────┐
           │  External DB  │
           │   (Primary)   │
           └───────────────┘
                   │
                   ▼
           ┌───────────────┐
           │  External DB  │
           │  (Read Replica)│
           └───────────────┘
```

## Monitoring Multiple Databases

```
┌─────────────────────────────────────────────┐
│         Kubernetes Cluster                  │
│                                              │
│  ┌─────────────┐  ┌─────────────┐          │
│  │  Exporter   │  │  Exporter   │          │
│  │   DB-1      │  │   DB-2      │          │
│  └──────┬──────┘  └──────┬──────┘          │
│         │                │                  │
└─────────┼────────────────┼──────────────────┘
          │                │
          ▼                ▼
   ┌──────────┐     ┌──────────┐
   │ Database │     │ Database │
   │    1     │     │    2     │
   └──────────┘     └──────────┘
```

Each exporter gets its own:
- Deployment
- ConfigMap (postgres-external-config-db1, postgres-external-config-db2)
- Service
- Prometheus scrape config

## Quick Reference

| Component | Purpose | Required for External DB |
|-----------|---------|--------------------------|
| `postgres-external-config` | External DB connection details | ✅ Yes |
| `postgres-config` | Database name and user | ✅ Yes |
| `postgres-secret` | Database password | ✅ Yes |
| `postgres-exporter-queries` | Custom metrics queries | ⚪ Optional |
| VPC Peering / Private Link | Network connectivity | ✅ Yes (for private DBs) |
| Security Group Rules | Firewall access | ✅ Yes |
| SSL Certificate | Encrypted connection | ⚪ Optional (but recommended) |
