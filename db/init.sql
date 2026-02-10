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
    UNIQUE(user_id, instance_name)
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
