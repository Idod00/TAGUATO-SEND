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
    must_change_password BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Instance ownership tracking
CREATE TABLE IF NOT EXISTS taguato.user_instances (
    id SERIAL PRIMARY KEY,
    user_id INT REFERENCES taguato.users(id) ON DELETE CASCADE,
    instance_name VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(user_id, instance_name),
    UNIQUE(instance_name)
);

CREATE INDEX IF NOT EXISTS idx_users_token ON taguato.users(api_token);
CREATE INDEX IF NOT EXISTS idx_user_instances_user ON taguato.user_instances(user_id);
CREATE INDEX IF NOT EXISTS idx_user_instances_name ON taguato.user_instances(instance_name);

-- ============================================
-- Status page tables
-- ============================================

-- Monitored services (pre-seeded)
CREATE TABLE IF NOT EXISTS taguato.services (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) UNIQUE NOT NULL,
    description TEXT,
    display_order INT DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Incidents
CREATE TABLE IF NOT EXISTS taguato.incidents (
    id SERIAL PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    severity VARCHAR(20) NOT NULL CHECK (severity IN ('minor', 'major', 'critical')),
    status VARCHAR(20) NOT NULL DEFAULT 'investigating' CHECK (status IN ('investigating', 'identified', 'monitoring', 'resolved')),
    created_by INT REFERENCES taguato.users(id) ON DELETE SET NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    resolved_at TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_incidents_status ON taguato.incidents(status);
CREATE INDEX IF NOT EXISTS idx_incidents_created ON taguato.incidents(created_at DESC);

-- Incident timeline updates
CREATE TABLE IF NOT EXISTS taguato.incident_updates (
    id SERIAL PRIMARY KEY,
    incident_id INT NOT NULL REFERENCES taguato.incidents(id) ON DELETE CASCADE,
    status VARCHAR(20) NOT NULL CHECK (status IN ('investigating', 'identified', 'monitoring', 'resolved')),
    message TEXT NOT NULL,
    created_by INT REFERENCES taguato.users(id) ON DELETE SET NULL,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_incident_updates_incident ON taguato.incident_updates(incident_id);

-- Affected services per incident (junction table)
CREATE TABLE IF NOT EXISTS taguato.incident_services (
    incident_id INT NOT NULL REFERENCES taguato.incidents(id) ON DELETE CASCADE,
    service_id INT NOT NULL REFERENCES taguato.services(id) ON DELETE CASCADE,
    PRIMARY KEY (incident_id, service_id)
);

-- Scheduled maintenances
CREATE TABLE IF NOT EXISTS taguato.scheduled_maintenances (
    id SERIAL PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    scheduled_start TIMESTAMP NOT NULL,
    scheduled_end TIMESTAMP NOT NULL,
    status VARCHAR(20) DEFAULT 'scheduled' CHECK (status IN ('scheduled', 'in_progress', 'completed')),
    created_by INT REFERENCES taguato.users(id) ON DELETE SET NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Junction: maintenance <-> affected services
CREATE TABLE IF NOT EXISTS taguato.maintenance_services (
    maintenance_id INT NOT NULL REFERENCES taguato.scheduled_maintenances(id) ON DELETE CASCADE,
    service_id INT NOT NULL REFERENCES taguato.services(id) ON DELETE CASCADE,
    PRIMARY KEY (maintenance_id, service_id)
);

-- Uptime check history (periodic snapshots)
CREATE TABLE IF NOT EXISTS taguato.uptime_checks (
    id SERIAL PRIMARY KEY,
    service_name VARCHAR(100) NOT NULL,
    status VARCHAR(20) NOT NULL,
    response_time INT DEFAULT 0,
    checked_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_uptime_checks_service_time
    ON taguato.uptime_checks(service_name, checked_at DESC);

-- Seed default services
INSERT INTO taguato.services (name, description, display_order) VALUES
    ('Gateway', 'API Gateway y enrutamiento', 1),
    ('Evolution API', 'Motor de WhatsApp', 2),
    ('PostgreSQL', 'Base de datos', 3),
    ('Redis', 'Cache y colas', 4)
ON CONFLICT (name) DO NOTHING;

-- ============================================
-- Message templates
-- ============================================
CREATE TABLE IF NOT EXISTS taguato.message_templates (
    id SERIAL PRIMARY KEY,
    user_id INT NOT NULL REFERENCES taguato.users(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    content TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_templates_user ON taguato.message_templates(user_id);

-- ============================================
-- Contact lists
-- ============================================
CREATE TABLE IF NOT EXISTS taguato.contact_lists (
    id SERIAL PRIMARY KEY,
    user_id INT NOT NULL REFERENCES taguato.users(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_contact_lists_user ON taguato.contact_lists(user_id);

CREATE TABLE IF NOT EXISTS taguato.contact_list_items (
    id SERIAL PRIMARY KEY,
    list_id INT NOT NULL REFERENCES taguato.contact_lists(id) ON DELETE CASCADE,
    phone_number VARCHAR(20) NOT NULL,
    label VARCHAR(100) DEFAULT '',
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_contact_items_list ON taguato.contact_list_items(list_id);

-- ============================================
-- User rate limiting (per-user override)
-- ============================================
-- rate_limit column on users table (NULL = use global default)
ALTER TABLE taguato.users ADD COLUMN IF NOT EXISTS rate_limit INT DEFAULT NULL;

-- ============================================
-- Brute-force protection columns
-- ============================================
ALTER TABLE taguato.users ADD COLUMN IF NOT EXISTS failed_login_attempts INT DEFAULT 0;
ALTER TABLE taguato.users ADD COLUMN IF NOT EXISTS locked_until TIMESTAMP;

-- ============================================
-- User sessions
-- ============================================
CREATE TABLE IF NOT EXISTS taguato.sessions (
    id SERIAL PRIMARY KEY,
    user_id INT NOT NULL REFERENCES taguato.users(id) ON DELETE CASCADE,
    token_hash VARCHAR(64) NOT NULL,
    ip_address VARCHAR(45),
    user_agent TEXT,
    last_active TIMESTAMP DEFAULT NOW(),
    is_active BOOLEAN DEFAULT true,
    expires_at TIMESTAMP DEFAULT (NOW() + INTERVAL '24 hours'),
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sessions_user ON taguato.sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_sessions_token ON taguato.sessions(token_hash);
CREATE INDEX IF NOT EXISTS idx_sessions_expires ON taguato.sessions(expires_at) WHERE is_active = true;

-- ============================================
-- Message logs
-- ============================================
CREATE TABLE IF NOT EXISTS taguato.message_logs (
    id SERIAL PRIMARY KEY,
    user_id INT NOT NULL REFERENCES taguato.users(id) ON DELETE CASCADE,
    instance_name VARCHAR(255) NOT NULL,
    phone_number VARCHAR(20) NOT NULL,
    message_type VARCHAR(20) DEFAULT 'text' CHECK (message_type IN ('text', 'image', 'document', 'audio', 'video')),
    status VARCHAR(20) DEFAULT 'sent' CHECK (status IN ('sent', 'failed', 'cancelled')),
    error_message TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_message_logs_user ON taguato.message_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_message_logs_created ON taguato.message_logs(created_at DESC);

-- ============================================
-- Audit log
-- ============================================
CREATE TABLE IF NOT EXISTS taguato.audit_log (
    id SERIAL PRIMARY KEY,
    user_id INT REFERENCES taguato.users(id) ON DELETE SET NULL,
    username VARCHAR(100),
    action VARCHAR(50) NOT NULL,
    resource_type VARCHAR(50),
    resource_id VARCHAR(100),
    details JSONB,
    ip_address VARCHAR(45),
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_log_created ON taguato.audit_log(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_log_user ON taguato.audit_log(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_action ON taguato.audit_log(action);

-- ============================================
-- Reconnect log
-- ============================================
CREATE TABLE IF NOT EXISTS taguato.reconnect_log (
    id SERIAL PRIMARY KEY,
    instance_name VARCHAR(255) NOT NULL,
    previous_state VARCHAR(50),
    action VARCHAR(50),
    result VARCHAR(50),
    error_message TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_reconnect_log_created ON taguato.reconnect_log(created_at DESC);

-- ============================================
-- Scheduled messages
-- ============================================
CREATE TABLE IF NOT EXISTS taguato.scheduled_messages (
    id SERIAL PRIMARY KEY,
    user_id INT NOT NULL REFERENCES taguato.users(id) ON DELETE CASCADE,
    instance_name VARCHAR(255) NOT NULL,
    message_type VARCHAR(20) DEFAULT 'text' CHECK (message_type IN ('text', 'image', 'document', 'audio', 'video')),
    message_content TEXT NOT NULL,
    recipients TEXT NOT NULL,
    scheduled_at TIMESTAMP NOT NULL,
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'cancelled')),
    results JSONB,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_scheduled_user ON taguato.scheduled_messages(user_id);
CREATE INDEX IF NOT EXISTS idx_scheduled_pending ON taguato.scheduled_messages(status, scheduled_at)
    WHERE status = 'pending';

-- ============================================
-- Schema migrations tracking
-- ============================================
CREATE TABLE IF NOT EXISTS taguato.schema_migrations (
    version INT PRIMARY KEY,
    filename VARCHAR(255) NOT NULL,
    applied_at TIMESTAMP DEFAULT NOW()
);

-- ============================================
-- User webhooks
-- ============================================
CREATE TABLE IF NOT EXISTS taguato.user_webhooks (
    id SERIAL PRIMARY KEY,
    user_id INT NOT NULL REFERENCES taguato.users(id) ON DELETE CASCADE,
    instance_name VARCHAR(255) NOT NULL,
    webhook_url TEXT NOT NULL,
    events TEXT[] DEFAULT '{}',
    is_active BOOLEAN DEFAULT true,
    retry_count INT DEFAULT 0,
    last_error TEXT,
    needs_sync BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(user_id, instance_name)
);

CREATE INDEX IF NOT EXISTS idx_webhooks_user ON taguato.user_webhooks(user_id);
