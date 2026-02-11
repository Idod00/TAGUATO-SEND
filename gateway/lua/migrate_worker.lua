-- Database migration worker
-- Runs once at startup (worker 0) to apply pending migrations

local _M = {}

function _M.run()
    local pgmoon = require "pgmoon"

    local pg_config = {
        host = os.getenv("PG_HOST") or "taguato-postgres",
        port = tonumber(os.getenv("PG_PORT")) or 5432,
        database = os.getenv("PG_DATABASE") or "evolution",
        user = os.getenv("PG_USER") or "taguato",
        password = os.getenv("PG_PASSWORD") or "taguato_secret",
    }

    local pg = pgmoon.new(pg_config)
    local ok, err = pg:connect()
    if not ok then
        ngx.log(ngx.ERR, "migrate_worker: cannot connect to DB: ", err)
        return
    end

    -- Create schema_migrations table if not exists
    local res, qerr = pg:query([[
        CREATE TABLE IF NOT EXISTS taguato.schema_migrations (
            version INT PRIMARY KEY,
            filename VARCHAR(255) NOT NULL,
            applied_at TIMESTAMP DEFAULT NOW()
        )
    ]])
    if not res then
        ngx.log(ngx.ERR, "migrate_worker: cannot create migrations table: ", qerr)
        pg:keepalive(10000, 10)
        return
    end

    -- Get already applied versions
    local applied, aerr = pg:query("SELECT version FROM taguato.schema_migrations ORDER BY version")
    if not applied then
        ngx.log(ngx.ERR, "migrate_worker: cannot read migrations: ", aerr)
        pg:keepalive(10000, 10)
        return
    end

    local applied_set = {}
    for _, row in ipairs(applied) do
        applied_set[tonumber(row.version)] = true
    end

    -- Load migration list
    local migrations = require "migrations_list"
    local applied_count = 0

    for _, m in ipairs(migrations) do
        if not applied_set[m.version] then
            ngx.log(ngx.INFO, "migrate_worker: applying migration ", m.version, " (", m.name, ")")

            local mres, merr = pg:query(m.sql)
            if not mres then
                ngx.log(ngx.ERR, "migrate_worker: migration ", m.version, " FAILED: ", merr)
                -- Stop on first failure
                break
            end

            -- Record migration
            local ires, ierr = pg:query(
                "INSERT INTO taguato.schema_migrations (version, filename) VALUES ("
                .. tostring(m.version) .. ", "
                .. pg:escape_literal(m.name) .. ")"
            )
            if not ires then
                ngx.log(ngx.ERR, "migrate_worker: cannot record migration ", m.version, ": ", ierr)
                break
            end

            applied_count = applied_count + 1
            ngx.log(ngx.INFO, "migrate_worker: migration ", m.version, " applied successfully")
        end
    end

    if applied_count > 0 then
        ngx.log(ngx.INFO, "migrate_worker: ", applied_count, " migration(s) applied")
    else
        ngx.log(ngx.INFO, "migrate_worker: database is up to date")
    end

    pg:keepalive(10000, 10)
end

return _M
