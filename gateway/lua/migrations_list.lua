-- Migration definitions: ordered list of SQL migrations
-- Each entry: { version = N, name = "description", sql = "..." }
return {
    {
        version = 1,
        name = "add_brute_force_columns",
        sql = [[
            ALTER TABLE taguato.users ADD COLUMN IF NOT EXISTS failed_login_attempts INT DEFAULT 0;
            ALTER TABLE taguato.users ADD COLUMN IF NOT EXISTS locked_until TIMESTAMP;
        ]],
    },
    {
        version = 2,
        name = "create_user_webhooks",
        sql = [[
            CREATE TABLE IF NOT EXISTS taguato.user_webhooks (
                id SERIAL PRIMARY KEY,
                user_id INT NOT NULL REFERENCES taguato.users(id) ON DELETE CASCADE,
                instance_name VARCHAR(255) NOT NULL,
                webhook_url TEXT NOT NULL,
                events TEXT[] DEFAULT '{}',
                is_active BOOLEAN DEFAULT true,
                created_at TIMESTAMP DEFAULT NOW(),
                updated_at TIMESTAMP DEFAULT NOW(),
                UNIQUE(user_id, instance_name)
            );
            CREATE INDEX IF NOT EXISTS idx_webhooks_user ON taguato.user_webhooks(user_id);
        ]],
    },
    {
        version = 3,
        name = "session_expiry_and_webhook_retry",
        sql = [[
            ALTER TABLE taguato.sessions ADD COLUMN IF NOT EXISTS expires_at TIMESTAMP DEFAULT (NOW() + INTERVAL '24 hours');
            UPDATE taguato.sessions SET expires_at = created_at + INTERVAL '24 hours' WHERE expires_at IS NULL;
            CREATE INDEX IF NOT EXISTS idx_sessions_expires ON taguato.sessions(expires_at) WHERE is_active = true;

            ALTER TABLE taguato.user_webhooks ADD COLUMN IF NOT EXISTS retry_count INT DEFAULT 0;
            ALTER TABLE taguato.user_webhooks ADD COLUMN IF NOT EXISTS last_error TEXT;
            ALTER TABLE taguato.user_webhooks ADD COLUMN IF NOT EXISTS needs_sync BOOLEAN DEFAULT false;
        ]],
    },
    {
        version = 4,
        name = "unique_instance_name",
        sql = [[
            ALTER TABLE taguato.user_instances ADD CONSTRAINT uq_instance_name UNIQUE (instance_name);
        ]],
    },
    {
        version = 5,
        name = "invalidate_md5_sessions",
        sql = [[
            UPDATE taguato.sessions SET is_active = false WHERE is_active = true;
        ]],
    },
    {
        version = 6,
        name = "scheduled_message_idempotency",
        sql = [[
            ALTER TABLE taguato.message_logs ADD COLUMN IF NOT EXISTS scheduled_message_id INT REFERENCES taguato.scheduled_messages(id) ON DELETE SET NULL;
            CREATE INDEX IF NOT EXISTS idx_message_logs_scheduled ON taguato.message_logs(scheduled_message_id, phone_number) WHERE scheduled_message_id IS NOT NULL;
        ]],
    },
    {
        version = 7,
        name = "password_recovery",
        sql = [[
            ALTER TABLE taguato.users ADD COLUMN IF NOT EXISTS email VARCHAR(255) UNIQUE;
            ALTER TABLE taguato.users ADD COLUMN IF NOT EXISTS phone_number VARCHAR(30);
            CREATE INDEX IF NOT EXISTS idx_users_email ON taguato.users(email) WHERE email IS NOT NULL;

            CREATE TABLE IF NOT EXISTS taguato.password_resets (
                id SERIAL PRIMARY KEY,
                user_id INT NOT NULL REFERENCES taguato.users(id) ON DELETE CASCADE,
                reset_code VARCHAR(6) NOT NULL,
                reset_token VARCHAR(64),
                method VARCHAR(10) DEFAULT 'email' CHECK (method IN ('email', 'whatsapp')),
                attempts INT DEFAULT 0,
                expires_at TIMESTAMP NOT NULL DEFAULT (NOW() + INTERVAL '15 minutes'),
                used_at TIMESTAMP,
                created_at TIMESTAMP DEFAULT NOW()
            );
            CREATE INDEX IF NOT EXISTS idx_password_resets_user ON taguato.password_resets(user_id);
            CREATE INDEX IF NOT EXISTS idx_password_resets_token ON taguato.password_resets(reset_token) WHERE reset_token IS NOT NULL;
        ]],
    },
    {
        version = 8,
        name = "add_missing_indexes",
        sql = [[
            -- message_logs: filtered by status, instance_name, message_type
            CREATE INDEX IF NOT EXISTS idx_message_logs_status ON taguato.message_logs(status);
            CREATE INDEX IF NOT EXISTS idx_message_logs_instance ON taguato.message_logs(instance_name);
            CREATE INDEX IF NOT EXISTS idx_message_logs_user_created ON taguato.message_logs(user_id, created_at DESC);

            -- audit_log: filtered by action, username, resource_type
            CREATE INDEX IF NOT EXISTS idx_audit_log_username ON taguato.audit_log(username);
            CREATE INDEX IF NOT EXISTS idx_audit_log_resource ON taguato.audit_log(resource_type);

            -- scheduled_messages: filtered by status + scheduled_at
            CREATE INDEX IF NOT EXISTS idx_scheduled_status ON taguato.scheduled_messages(status);
            CREATE INDEX IF NOT EXISTS idx_scheduled_user_created ON taguato.scheduled_messages(user_id, created_at DESC);

            -- sessions: filtered by is_active
            CREATE INDEX IF NOT EXISTS idx_sessions_active ON taguato.sessions(user_id, is_active) WHERE is_active = true;

            -- incidents: filtered by status
            CREATE INDEX IF NOT EXISTS idx_incidents_status_created ON taguato.incidents(status, created_at DESC);

            -- scheduled_maintenances: filtered by status
            CREATE INDEX IF NOT EXISTS idx_maintenance_status ON taguato.scheduled_maintenances(status);
        ]],
    },
    {
        version = 9,
        name = "ephemeral_session_tokens",
        sql = [[
            -- Invalidate all existing sessions (they used api_token hashes, not session tokens)
            UPDATE taguato.sessions SET is_active = false WHERE is_active = true;

            -- Composite index for session token validation queries
            CREATE INDEX IF NOT EXISTS idx_sessions_token_active
                ON taguato.sessions(token_hash, is_active, expires_at) WHERE is_active = true;
        ]],
    },
}
