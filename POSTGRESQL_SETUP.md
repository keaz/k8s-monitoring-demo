# PostgreSQL Integration with Prometheus Monitoring

This document describes the PostgreSQL database setup integrated with Service C and monitored by Prometheus.

## Overview

The project now includes:
- PostgreSQL 15 database running in Kubernetes
- PostgreSQL Exporter for Prometheus metrics
- Service C integrated with PostgreSQL using Spring Data JPA
- Complete CRUD API endpoints for users and orders
- Production-ready configuration for managed PostgreSQL databases

## Architecture

```
Service C (Spring Boot + JPA)
    ↓
PostgreSQL (demo_db)
    ↓
PostgreSQL Exporter (port 9187)
    ↓
Prometheus (scrapes metrics)
    ↓
Grafana (visualize metrics)
```

## Deployed Components

### 1. PostgreSQL Database

- **Namespace**: `services`
- **Service**: `postgres.services.svc.cluster.local:5432`
- **Database**: `demo_db`
- **User**: `postgres`
- **Password**: `Abcd` (stored in Secret)
- **Storage**: 5Gi PersistentVolumeClaim

**Tables**:
- `users` - User information (id, username, email, status, timestamps)
- `orders` - Order information (id, order_number, user_id, amount, status, items_count, timestamps)

**Sample Data**:
- 10 users (john_doe, jane_smith, bob_wilson, etc.)
- 15 orders with various statuses

### 2. PostgreSQL Exporter

- **Namespace**: `services`
- **Service**: `postgres-exporter.services.svc.cluster.local:9187`
- **Metrics Endpoint**: `http://postgres-exporter:9187/metrics`
- **Image**: `prometheuscommunity/postgres-exporter:v0.15.0`

**Metrics Exported**:
- `pg_database_size_bytes` - Database size in bytes
- `pg_stat_activity_count` - Number of active/idle connections by state
- `pg_stat_database_*` - Database statistics
- Standard PostgreSQL metrics

**Annotations**:
```yaml
prometheus.io/scrape: "true"
prometheus.io/port: "9187"
prometheus.io/path: "/metrics"
```

### 3. Service C Database Integration

**Technology Stack**:
- Spring Boot 3.2.0
- Spring Data JPA
- PostgreSQL JDBC Driver
- Hibernate ORM

**Configuration** (application.yml):
```yaml
spring:
  datasource:
    url: jdbc:postgresql://${DB_HOST:postgres.services.svc.cluster.local}:${DB_PORT:5432}/${DB_NAME:demo_db}
    username: ${DB_USER:postgres}
    password: ${DB_PASSWORD:Abcd}
  jpa:
    hibernate:
      ddl-auto: update
    show-sql: true
```

## API Endpoints

### Service C - Data Service

Base URL: `http://service-c.services.svc.cluster.local:8082/api/data`

#### User Endpoints

**1. Get All Users**
```bash
GET /users
Response: {
  "service": "service-c",
  "users": [...],
  "count": 10,
  "queryTime": 385,
  "timestamp": 1761299621374
}
```

**2. Get User by ID**
```bash
GET /user/{userId}
Example: GET /user/1
Response: {
  "service": "service-c",
  "userId": 1,
  "username": "john_doe",
  "email": "john.doe@example.com",
  "status": "active",
  "createdAt": "2025-10-24T09:45:46.676773",
  "updatedAt": "2025-10-24T09:45:46.676773",
  "queryTime": 8,
  "timestamp": 1761299621374
}
```

**3. Create User**
```bash
POST /user
Content-Type: application/json
Body: {
  "username": "test_user",
  "email": "test@example.com",
  "status": "active"
}
Response: {
  "service": "service-c",
  "userId": 11,
  "username": "test_user",
  "email": "test@example.com",
  "status": "active",
  "createdAt": "2025-10-24T09:53:55.729483",
  "queryTime": 21,
  "timestamp": 1761299635747
}
```

#### Order Endpoints

**1. Get All Orders**
```bash
GET /orders
Response: {
  "service": "service-c",
  "orders": [...],
  "count": 15,
  "queryTime": 6,
  "timestamp": 1761299621374
}
```

**2. Get Order by ID**
```bash
GET /order/{orderId}
Example: GET /order/1
```

**3. Get Orders by User**
```bash
GET /user/{userId}/orders
Example: GET /user/1/orders
```

**4. Create Order**
```bash
POST /order
Content-Type: application/json
Body: {
  "orderNumber": "ORD-2025-0016",
  "userId": 1,
  "amount": 199.99,
  "status": "pending",
  "itemsCount": 3
}
```

## Testing the Integration

### 1. Test API Endpoints

```bash
# Get all users
kubectl run curl-test --image=curlimages/curl:latest --rm -i --restart=Never -n services -- \
  curl -s http://service-c.services.svc.cluster.local:8082/api/data/users

# Get specific user
kubectl run curl-test --image=curlimages/curl:latest --rm -i --restart=Never -n services -- \
  curl -s http://service-c.services.svc.cluster.local:8082/api/data/user/1

# Create new user
kubectl run curl-test --image=curlimages/curl:latest --rm -i --restart=Never -n services -- \
  curl -s -X POST http://service-c.services.svc.cluster.local:8082/api/data/user \
  -H "Content-Type: application/json" \
  -d '{"username":"new_user","email":"new@example.com","status":"active"}'
```

### 2. Verify PostgreSQL Exporter Metrics

```bash
# Check postgres-exporter metrics
kubectl run curl-test --image=curlimages/curl:latest --rm -i --restart=Never -n services -- \
  curl -s http://postgres-exporter.services.svc.cluster.local:9187/metrics | grep pg_database_size
```

### 3. Query Prometheus

Access Prometheus UI at `http://localhost:30000` and run queries:

```promql
# Database size
pg_database_size_bytes{datname="demo_db"}

# Active connections
pg_stat_activity_count{datname="demo_db",state="active"}

# Idle connections
pg_stat_activity_count{datname="demo_db",state="idle"}
```

### 4. Direct Database Access

```bash
# Connect to PostgreSQL
kubectl exec -it -n services deployment/postgres -- psql -U postgres -d demo_db

# Query users
demo_db=# SELECT * FROM users;

# Query orders
demo_db=# SELECT * FROM orders;

# Exit
demo_db=# \q
```

## Database Management

### Initialize Database with Sample Data

```bash
# From project root
cd /home/Kasun/Development/RnD/Monitoring/K8S/k8s-monitoring-demo
bash scripts/init-database.sh
```

This script:
- Creates tables (users, orders) with proper schema
- Populates 10 sample users
- Populates 15 sample orders
- Creates indexes for performance

### Manual Database Operations

```bash
# Get PostgreSQL pod name
POSTGRES_POD=$(kubectl get pods -n services -l app=postgres -o jsonpath='{.items[0].metadata.name}')

# Run SQL commands
kubectl exec -n services $POSTGRES_POD -- psql -U postgres -d demo_db -c "SELECT COUNT(*) FROM users;"
kubectl exec -n services $POSTGRES_POD -- psql -U postgres -d demo_db -c "SELECT COUNT(*) FROM orders;"

# Backup database
kubectl exec -n services $POSTGRES_POD -- pg_dump -U postgres demo_db > backup.sql

# Restore database
cat backup.sql | kubectl exec -i -n services $POSTGRES_POD -- psql -U postgres -d demo_db
```

## Production Considerations

### For Managed PostgreSQL (AWS RDS, Google Cloud SQL, Azure Database)

The configuration supports managed PostgreSQL services through environment variables:

1. **Update Service C Deployment** (`kubernetes/base/services/service-c.yaml`):
```yaml
env:
  - name: DB_HOST
    value: "your-rds-endpoint.amazonaws.com"
  - name: DB_PORT
    value: "5432"
  - name: DB_NAME
    value: "production_db"
  - name: DB_USER
    valueFrom:
      secretKeyRef:
        name: db-credentials
        key: username
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: db-credentials
        key: password
```

2. **Update PostgreSQL Exporter** (`kubernetes/base/postgres/postgres-exporter.yaml`):
```yaml
env:
  - name: POSTGRES_HOST
    value: "your-rds-endpoint.amazonaws.com"
  - name: POSTGRES_PORT
    value: "5432"
  - name: POSTGRES_DB
    value: "production_db"
  - name: POSTGRES_USER
    valueFrom:
      secretKeyRef:
        name: db-credentials
        key: username
  - name: POSTGRES_PASSWORD
    valueFrom:
      secretKeyRef:
        name: db-credentials
        key: password
```

3. **Create Database Credentials Secret**:
```bash
kubectl create secret generic db-credentials -n services \
  --from-literal=username=your_db_user \
  --from-literal=password=your_db_password
```

### Security Best Practices

1. **Use Secrets** for database credentials (not ConfigMaps)
2. **Enable SSL/TLS** for database connections in production:
   ```yaml
   spring.datasource.url: jdbc:postgresql://host:5432/db?ssl=true&sslmode=require
   ```
3. **Restrict Network Access** using NetworkPolicies
4. **Regular Backups** - Set up automated backups
5. **Connection Pooling** - Adjust HikariCP settings for production:
   ```yaml
   spring:
     datasource:
       hikari:
         maximum-pool-size: 20
         minimum-idle: 5
         connection-timeout: 30000
   ```

## Monitoring and Alerts

### Key Metrics to Monitor

1. **Database Size**
   - `pg_database_size_bytes{datname="demo_db"}`
   - Alert when > 80% of allocated storage

2. **Connection Pool**
   - `pg_stat_activity_count` (active, idle connections)
   - Alert when active connections > 80% of max_connections

3. **Query Performance**
   - Service C logs show `queryTime` for each request
   - Use Jaeger for distributed tracing of database queries

4. **Database Health**
   - PostgreSQL pod liveness/readiness probes
   - postgres-exporter availability

### Grafana Dashboard

Create a Grafana dashboard with:
- Database size over time
- Connection pool usage
- Query latency (from Service C metrics)
- Top queries by execution time
- Database errors and warnings

Access Grafana at `http://localhost:30001` (admin/admin)

## File Structure

```
kubernetes/base/postgres/
├── postgres.yaml              # PostgreSQL deployment, service, configmap, secret, PVC
└── postgres-exporter.yaml     # PostgreSQL exporter deployment and service

services/java/service-c/
├── src/main/java/com/example/otel/servicec/
│   ├── entity/
│   │   ├── User.java         # JPA entity for users
│   │   └── Order.java        # JPA entity for orders
│   ├── repository/
│   │   ├── UserRepository.java    # Spring Data repository
│   │   └── OrderRepository.java   # Spring Data repository
│   └── DataController.java   # REST API endpoints
└── src/main/resources/
    └── application.yml        # Database configuration

scripts/
├── init-db.sql               # Database schema and sample data
└── init-database.sh          # Script to initialize database
```

## Troubleshooting

### Service C can't connect to PostgreSQL

```bash
# Check PostgreSQL is running
kubectl get pods -n services -l app=postgres

# Check PostgreSQL logs
kubectl logs -n services deployment/postgres

# Test connection from Service C pod
kubectl exec -n services deployment/service-c -- sh -c \
  'apt-get update && apt-get install -y postgresql-client && \
   psql -h postgres.services.svc.cluster.local -U postgres -d demo_db -c "SELECT 1"'
```

### Postgres-exporter not scraping

```bash
# Check postgres-exporter pod
kubectl get pods -n services -l app=postgres-exporter

# Check postgres-exporter logs
kubectl logs -n services deployment/postgres-exporter

# Manually test metrics endpoint
kubectl run curl-test --image=curlimages/curl:latest --rm -i --restart=Never -n services -- \
  curl -s http://postgres-exporter.services.svc.cluster.local:9187/metrics
```

### Prometheus not receiving metrics

```bash
# Check Prometheus targets
# Access http://localhost:30000/targets
# Look for postgres-exporter in kubernetes-pods or kubernetes-services

# Check Prometheus scrape errors
# Access http://localhost:30000/targets and look for error messages
```

## Next Steps

1. **Add More Endpoints**: Extend Service C with UPDATE and DELETE operations
2. **Add Validation**: Implement input validation and error handling
3. **Add Database Migrations**: Use Flyway or Liquibase for schema versioning
4. **Add Connection Pooling Metrics**: Expose HikariCP metrics to Prometheus
5. **Create Grafana Dashboards**: Build comprehensive PostgreSQL monitoring dashboards
6. **Set Up Alerts**: Configure Prometheus alerting rules for database issues
7. **Add Integration Tests**: Write tests for database operations
8. **Implement Caching**: Add Redis caching layer for frequently accessed data

## References

- [PostgreSQL Exporter Documentation](https://github.com/prometheus-community/postgres_exporter)
- [Spring Data JPA Documentation](https://spring.io/projects/spring-data-jpa)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [Prometheus PostgreSQL Metrics](https://prometheus.io/docs/instrumenting/exporters/)
