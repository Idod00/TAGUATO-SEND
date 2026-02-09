-- Migration: Status Page v2 - Scheduled Maintenances + Uptime Checks
-- Run this on existing databases that already have the v1 status tables.
-- Usage: docker exec -i taguato-postgres psql -U taguato -d evolution < scripts/migrate-status-v2.sql

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
