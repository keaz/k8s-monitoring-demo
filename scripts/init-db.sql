-- Database Initialization Script for k8s-monitoring-demo
-- This script creates tables and populates sample data

-- Drop tables if they exist (for fresh start)
DROP TABLE IF EXISTS orders CASCADE;
DROP TABLE IF EXISTS users CASCADE;

-- Create Users table
CREATE TABLE users (
    id BIGSERIAL PRIMARY KEY,
    username VARCHAR(255) NOT NULL UNIQUE,
    email VARCHAR(255) NOT NULL,
    status VARCHAR(50) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Create Orders table
CREATE TABLE orders (
    id BIGSERIAL PRIMARY KEY,
    order_number VARCHAR(255) NOT NULL UNIQUE,
    user_id BIGINT NOT NULL,
    amount NUMERIC(10, 2) NOT NULL,
    status VARCHAR(50) NOT NULL,
    items_count INTEGER NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Create index for faster lookups
CREATE INDEX idx_orders_user_id ON orders(user_id);
CREATE INDEX idx_orders_status ON orders(status);
CREATE INDEX idx_users_username ON users(username);

-- Insert sample users
INSERT INTO users (username, email, status, created_at, updated_at) VALUES
    ('john_doe', 'john.doe@example.com', 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('jane_smith', 'jane.smith@example.com', 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('bob_wilson', 'bob.wilson@example.com', 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('alice_johnson', 'alice.johnson@example.com', 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('charlie_brown', 'charlie.brown@example.com', 'inactive', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('diana_prince', 'diana.prince@example.com', 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('edward_stark', 'edward.stark@example.com', 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('fiona_gallagher', 'fiona.gallagher@example.com', 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('george_miller', 'george.miller@example.com', 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('hannah_montana', 'hannah.montana@example.com', 'inactive', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

-- Insert sample orders
INSERT INTO orders (order_number, user_id, amount, status, items_count, created_at, updated_at) VALUES
    ('ORD-2025-0001', 1, 125.50, 'completed', 3, CURRENT_TIMESTAMP - INTERVAL '10 days', CURRENT_TIMESTAMP),
    ('ORD-2025-0002', 1, 89.99, 'completed', 2, CURRENT_TIMESTAMP - INTERVAL '8 days', CURRENT_TIMESTAMP),
    ('ORD-2025-0003', 2, 245.00, 'completed', 5, CURRENT_TIMESTAMP - INTERVAL '7 days', CURRENT_TIMESTAMP),
    ('ORD-2025-0004', 3, 56.75, 'pending', 1, CURRENT_TIMESTAMP - INTERVAL '6 days', CURRENT_TIMESTAMP),
    ('ORD-2025-0005', 2, 178.25, 'completed', 4, CURRENT_TIMESTAMP - INTERVAL '5 days', CURRENT_TIMESTAMP),
    ('ORD-2025-0006', 4, 512.99, 'completed', 8, CURRENT_TIMESTAMP - INTERVAL '4 days', CURRENT_TIMESTAMP),
    ('ORD-2025-0007', 5, 99.00, 'cancelled', 2, CURRENT_TIMESTAMP - INTERVAL '3 days', CURRENT_TIMESTAMP),
    ('ORD-2025-0008', 6, 345.50, 'pending', 6, CURRENT_TIMESTAMP - INTERVAL '2 days', CURRENT_TIMESTAMP),
    ('ORD-2025-0009', 1, 67.80, 'completed', 1, CURRENT_TIMESTAMP - INTERVAL '1 day', CURRENT_TIMESTAMP),
    ('ORD-2025-0010', 7, 890.00, 'pending', 12, CURRENT_TIMESTAMP - INTERVAL '12 hours', CURRENT_TIMESTAMP),
    ('ORD-2025-0011', 8, 234.75, 'completed', 4, CURRENT_TIMESTAMP - INTERVAL '6 hours', CURRENT_TIMESTAMP),
    ('ORD-2025-0012', 9, 156.99, 'pending', 3, CURRENT_TIMESTAMP - INTERVAL '3 hours', CURRENT_TIMESTAMP),
    ('ORD-2025-0013', 3, 445.00, 'completed', 7, CURRENT_TIMESTAMP - INTERVAL '2 hours', CURRENT_TIMESTAMP),
    ('ORD-2025-0014', 6, 78.50, 'pending', 2, CURRENT_TIMESTAMP - INTERVAL '1 hour', CURRENT_TIMESTAMP),
    ('ORD-2025-0015', 4, 299.99, 'completed', 5, CURRENT_TIMESTAMP - INTERVAL '30 minutes', CURRENT_TIMESTAMP);

-- Display counts
SELECT 'Users created:' as info, COUNT(*) as count FROM users
UNION ALL
SELECT 'Orders created:' as info, COUNT(*) as count FROM orders;

-- Display sample data
SELECT 'Sample Users:' as info;
SELECT id, username, email, status FROM users LIMIT 5;

SELECT 'Sample Orders:' as info;
SELECT id, order_number, user_id, amount, status, items_count FROM orders LIMIT 5;
