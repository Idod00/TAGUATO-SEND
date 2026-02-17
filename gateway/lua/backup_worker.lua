-- Automatic backup worker
-- Runs on a timer, creates pg_dump backups and retains last 7 auto-backups

local _M = {}

function _M.run()
    local log = require "log"

    local pg_user = os.getenv("PG_USER") or "taguato"
    local pg_host = os.getenv("PG_HOST") or "taguato-postgres"
    local pg_port = os.getenv("PG_PORT") or "5432"
    local pg_db = os.getenv("PG_DATABASE") or "evolution"
    local pg_pass = os.getenv("PG_PASSWORD") or "taguato_secret"

    local timestamp = os.date("%Y%m%d_%H%M%S")
    local backup_file = "/backups/taguato_auto_" .. timestamp .. ".sql.gz"

    -- Create backups directory if not exists
    os.execute("mkdir -p /backups")

    -- Write .pgpass file for secure password passing (not visible in ps aux)
    local pgpass_file = "/tmp/.pgpass_backup"
    local f = io.open(pgpass_file, "w")
    if f then
        f:write(string.format("%s:%s:%s:%s:%s\n", pg_host, pg_port, pg_db, pg_user, pg_pass))
        f:close()
        os.execute("chmod 600 " .. pgpass_file)
    end

    -- Run pg_dump using .pgpass for authentication
    local cmd = string.format(
        "PGPASSFILE='%s' pg_dump -h %s -p %s -U %s -d %s 2>/dev/null | gzip > %s",
        pgpass_file, pg_host, pg_port, pg_user, pg_db, backup_file
    )

    local ok = os.execute(cmd)

    -- Clean up .pgpass file
    os.remove(pgpass_file)

    if ok then
        log.info("backup_worker", "auto backup created", { file = backup_file })

        -- Retain only last 7 auto-backups (delete older ones)
        local handle = io.popen("ls -1t /backups/taguato_auto_*.sql.gz 2>/dev/null")
        local output = handle:read("*a")
        handle:close()

        local files = {}
        for line in output:gmatch("[^\n]+") do
            files[#files + 1] = line
        end

        if #files > 7 then
            for i = 8, #files do
                os.remove(files[i])
                log.info("backup_worker", "removed old auto backup", { file = files[i] })
            end
        end
    else
        log.err("backup_worker", "auto backup failed")
    end
end

return _M
