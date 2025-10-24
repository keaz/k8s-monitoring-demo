#!/bin/bash

# Script to initialize PostgreSQL database with sample data
# This script can be run in both development (k8s) and production (managed DB)

set -e

echo "=== PostgreSQL Database Initialization ==="
echo ""

# Get PostgreSQL pod name
POSTGRES_POD=$(kubectl get pods -n services -l app=postgres -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$POSTGRES_POD" ]; then
    echo "ERROR: PostgreSQL pod not found in 'services' namespace"
    echo "Please ensure PostgreSQL is running: kubectl get pods -n services"
    exit 1
fi

echo "Found PostgreSQL pod: $POSTGRES_POD"
echo ""

# Copy SQL script to pod
echo "Copying initialization script to PostgreSQL pod..."
kubectl cp scripts/init-db.sql services/$POSTGRES_POD:/tmp/init-db.sql

# Execute SQL script
echo "Executing initialization script..."
kubectl exec -n services $POSTGRES_POD -- psql -U postgres -d demo_db -f /tmp/init-db.sql

echo ""
echo "=== Database Initialization Complete ==="
echo ""
echo "You can verify the data with:"
echo "  kubectl exec -n services $POSTGRES_POD -- psql -U postgres -d demo_db -c 'SELECT COUNT(*) FROM users;'"
echo "  kubectl exec -n services $POSTGRES_POD -- psql -U postgres -d demo_db -c 'SELECT COUNT(*) FROM orders;'"
echo ""
echo "To connect to PostgreSQL directly:"
echo "  kubectl exec -it -n services $POSTGRES_POD -- psql -U postgres -d demo_db"
