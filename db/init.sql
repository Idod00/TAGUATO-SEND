-- ============================================
-- TAGUATO-SEND - Multi-tenant user schema
-- ============================================
-- Runs on first DB init via PostgreSQL entrypoint.
-- Uses separate 'taguato' schema to avoid conflicts with Prisma (public schema).

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE SCHEMA IF NOT EXISTS taguato;

-- Users table
CREATE TABLE IF NOT EXISTS taguato.users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(100) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role VARCHAR(20) DEFAULT 'user' CHECK (role IN ('admin', 'user')),
    api_token VARCHAR(64) UNIQUE NOT NULL,
    max_instances INT DEFAULT 1,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Instance ownership tracking
CREATE TABLE IF NOT EXISTS taguato.user_instances (
    id SERIAL PRIMARY KEY,
    user_id INT REFERENCES taguato.users(id) ON DELETE CASCADE,
    instance_name VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(user_id, instance_name)
);

CREATE INDEX IF NOT EXISTS idx_users_token ON taguato.users(api_token);
CREATE INDEX IF NOT EXISTS idx_user_instances_user ON taguato.user_instances(user_id);
CREATE INDEX IF NOT EXISTS idx_user_instances_name ON taguato.user_instances(instance_name);
