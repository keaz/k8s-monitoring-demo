# Inter-Service Communication Setup

This document describes the inter-service communication architecture and how to demo it.

## Service Architecture

The system consists of three Java microservices that communicate with each other:

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  Service-A   │────▶│  Service-B   │────▶│  Service-C   │────▶ PostgreSQL
│  (Port 80)   │     │  (Port 8081) │     │  (Port 8082) │        Database
└──────────────┘     └──────────────┘     └──────────────┘
```

### Service Responsibilities

**Service-A (Frontend Service)**
- Entry point for user requests
- Orchestrates calls to Service-B
- Exposes endpoints at port 80

**Service-B (Backend Service)**
- Processes business logic
- Calls Service-C for data operations
- Exposes endpoints at port 8081

**Service-C (Data Service)**
- Interacts with PostgreSQL database
- Manages user and order data
- Exposes endpoints at port 8082

## Available Endpoints

All three services now support the following endpoints:

### Simple Endpoints
- `GET /api/hello` - Simple hello response
- `GET /actuator/health` - Spring Boot health check

### Service Chain Endpoints (Service-A only)
- `GET /api/users/{userId}` - Fetch user data (A → B → C → DB)
- `GET /api/orders/{orderId}` - Fetch order data (A → B → C → DB)

### CPU-Intensive Endpoints
- `GET /api/compute/primes/{limit}` - Calculate prime numbers
- `GET /api/compute/hash/{iterations}` - Compute SHA-256 hash iterations

### Memory-Intensive Endpoints
- `GET /api/memory/allocate/{sizeMb}` - Allocate memory
- `GET /api/memory/process/{itemCount}` - Process large collections

### Slow Endpoints
- `GET /api/slow/database/{delayMs}` - Simulate slow database queries

### Error Simulation
- `GET /api/simulate/error` - Randomly generate errors

## Testing Inter-Service Communication

### 1. Test Simple Hello Endpoints

```bash
# Service-A
kubectl exec -n services deploy/service-a -- wget -q -O- http://service-a.services.svc.cluster.local/api/hello

# Service-B
kubectl exec -n services deploy/service-b -- wget -q -O- http://service-b.services.svc.cluster.local:8081/api/hello

# Service-C
kubectl exec -n services deploy/service-c -- wget -q -O- http://service-c.services.svc.cluster.local:8082/api/hello
```

### 2. Test Service Chain (A → B → C → Database)

```bash
# Fetch user data (creates distributed trace across all 3 services)
kubectl exec -n services deploy/service-a -- \
  wget -q -O- http://service-a.services.svc.cluster.local/api/users/1

# Fetch order data
kubectl exec -n services deploy/service-a -- \
  wget -q -O- http://service-a.services.svc.cluster.local/api/orders/1
```

**Expected Response for User:**
```json
{
  "service": "service-a",
  "userId": "1",
  "data": {
    "service": "service-b",
    "userId": "1",
    "processed": true,
    "dataFromServiceC": {
      "service": "service-c",
      "userId": 1,
      "username": "john_doe",
      "email": "john.doe@example.com",
      "status": "active",
      "queryTime": 3
    }
  }
}
```

### 3. Use the Traffic Generator

The easiest way to demo inter-service communication is with the traffic generator:

```bash
# Run for 60 seconds with 5 concurrent users
DURATION=60 CONCURRENT_USERS=5 ./scripts/generate-traffic.sh

# Run continuously (until Ctrl+C)
DURATION=0 ./scripts/generate-traffic.sh
```

The traffic generator automatically:
- Creates service chain requests (users/orders)
- Generates CPU/memory intensive workloads
- Simulates errors
- Creates varied traffic patterns

## Viewing Distributed Traces

### Jaeger UI (http://localhost:16686)

1. **Find Traces:**
   - Select Service: `service-a`, `service-b`, or `service-c`
   - Click "Find Traces"

2. **View Trace Details:**
   - Click on any trace to see the full span tree
   - You'll see spans across multiple services:
     ```
     service-a: GET /api/users/{id}
     └─▶ service-b: GET /api/user/{id}
         └─▶ service-c: GET /api/data/user/{id}
             └─▶ SELECT FROM users WHERE id=?
     ```

3. **Service Performance Monitoring (SPM):**
   - Go to the "Monitor" tab
   - Select a service
   - View RED metrics:
     - **R**ate: Requests per second
     - **E**rrors: Error percentage
     - **D**uration: P50, P95, P99 latencies

### Example Trace Flow

For a request to `/api/users/5`:

1. **Service-A** receives HTTP request
   - Creates span: `GET /api/users/5`
   - Calls Service-B

2. **Service-B** processes request
   - Creates span: `GET /api/user/5`
   - Adds 100ms processing delay
   - Calls Service-C

3. **Service-C** fetches data
   - Creates span: `GET /api/data/user/5`
   - Queries PostgreSQL database
   - Creates database span

All spans are linked in a single distributed trace!

## Database

Service-C connects to PostgreSQL with pre-populated data:

### Users Table
- 10 sample users (IDs 1-10)
- Fields: id, username, email, status, created_at, updated_at

### Orders Table
- 20 sample orders (IDs 1-20)
- Fields: id, order_number, user_id, amount, status, items_count, created_at, updated_at

### Check Database Contents

```bash
# View all users
kubectl exec -n services deploy/service-c -- \
  wget -q -O- http://service-c.services.svc.cluster.local:8082/api/data/users

# View all orders
kubectl exec -n services deploy/service-c -- \
  wget -q -O- http://service-c.services.svc.cluster.local:8082/api/data/orders
```

## Monitoring Stack Integration

### OpenTelemetry Collector
- Receives traces from all services
- Generates span metrics (calls_total, duration_milliseconds)
- Exports to:
  - Jaeger (for tracing)
  - Prometheus (for metrics)
  - VictoriaMetrics (for long-term storage)

### Prometheus
- Scrapes span metrics from OTEL Collector
- Scrapes application metrics from services
- Provides data for Jaeger SPM

### Grafana
- Visualize metrics from Prometheus/VictoriaMetrics
- Create dashboards for service health
- Access: http://localhost:3000 (admin/admin)

## Traffic Patterns

The traffic generator creates realistic patterns:

| Pattern | Percentage | Description |
|---------|-----------|-------------|
| Service Chains | 20% | `/api/users` and `/api/orders` (A→B→C) |
| Simple Requests | 27% | `/api/hello` and health checks |
| CPU Intensive | 20% | Prime calculations and hashing |
| Memory Intensive | 20% | Memory allocation and processing |
| Slow Requests | 10% | Database delay simulations |
| Errors | 3% | Random error generation |

## Demo Scenarios

### Scenario 1: Basic Service Chain
```bash
# Start traffic
DURATION=120 ./scripts/generate-traffic.sh

# Open Jaeger: http://localhost:16686
# Select service-a
# Find traces for "GET /api/users/{userId}"
# See the full chain: A → B → C → Database
```

### Scenario 2: Performance Analysis
```bash
# Generate high load
DURATION=300 CONCURRENT_USERS=10 ./scripts/generate-traffic.sh

# Open Jaeger Monitor tab
# Compare latencies across services
# Identify bottlenecks
```

### Scenario 3: Error Tracking
```bash
# Generate traffic with errors
DURATION=60 ./scripts/generate-traffic.sh

# In Jaeger, filter by "error=true"
# Trace error propagation across services
```

## Troubleshooting

### No traces appearing
```bash
# Check if services are running
kubectl get pods -n services

# Check OTEL collector logs
kubectl logs -n monitoring deploy/otel-collector --tail=50

# Verify service communication
kubectl exec -n services deploy/service-a -- \
  wget -q -O- http://service-a.services.svc.cluster.local/api/users/1
```

### Service chain broken
```bash
# Check Service-B can reach Service-C
kubectl exec -n services deploy/service-b -- \
  wget -q -O- http://service-c.services.svc.cluster.local:8082/api/hello

# Check database connection
kubectl logs -n services deploy/service-c | grep -i "database\|postgres"
```

### Rebuild services
```bash
# If you make code changes
./scripts/build-and-deploy.sh

# Or restart specific service
kubectl rollout restart deployment/service-a -n services
kubectl rollout status deployment/service-a -n services
```

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                     Kubernetes Cluster                       │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌────────────┐    ┌────────────┐    ┌────────────┐        │
│  │ Service-A  │───▶│ Service-B  │───▶│ Service-C  │────┐   │
│  │  :80       │    │  :8081     │    │  :8082     │    │   │
│  └─────┬──────┘    └─────┬──────┘    └─────┬──────┘    │   │
│        │                 │                 │            │   │
│        │ OTLP Traces     │ OTLP Traces     │ OTLP       │   │
│        │                 │                 │ Traces     │   │
│        └─────────────────┴─────────────────┘            │   │
│                          │                              │   │
│                          ▼                              ▼   │
│                  ┌───────────────┐              ┌──────────┐│
│                  │ OTEL Collector│              │PostgreSQL││
│                  └───────┬───────┘              └──────────┘│
│                          │                                   │
│                          │ Span Metrics                      │
│                          ▼                                   │
│             ┌────────────────────────┐                       │
│             │                        │                       │
│             ▼                        ▼                       │
│      ┌─────────────┐         ┌─────────────┐               │
│      │  Prometheus │         │    Jaeger   │               │
│      └──────┬──────┘         └──────┬──────┘               │
│             │                       │                       │
│             │ Metrics               │ Traces                │
│             ▼                       ▼                       │
│      ┌─────────────┐         ┌────────────┐               │
│      │   Grafana   │         │ Jaeger UI  │               │
│      │ :3000       │         │ :16686     │               │
│      └─────────────┘         └────────────┘               │
│                                     │                       │
│                                     │ SPM Metrics           │
│                                     ▼                       │
│                              ┌─────────────┐               │
│                              │ Prometheus  │               │
│                              └─────────────┘               │
└─────────────────────────────────────────────────────────────┘
```

## Next Steps

1. **Generate Traffic:** Run `./scripts/generate-traffic.sh`
2. **View Traces:** Open http://localhost:16686
3. **Analyze Performance:** Check SPM in Jaeger Monitor tab
4. **Create Dashboards:** Build Grafana dashboards at http://localhost:3000
5. **Experiment:** Try different traffic patterns and observe the traces
