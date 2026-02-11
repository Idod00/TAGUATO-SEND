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
}
