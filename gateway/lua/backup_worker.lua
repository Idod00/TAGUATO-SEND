-- Automatic backup worker
-- Runs on a timer, creates pg_dump backups and retains last 7 auto-backups
-- Uses PGPASSFILE instead of PGPASSWORD to hide credentials from process listings

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
    local pgpass_file = "/tmp/.pgpass_" .. ngx.worker.pid()

    -- Create backups directory if not exists
    os.execute("mkdir -p /backups")

    -- Write temporary .pgpass file with restrictive permissions
    local f = io.open(pgpass_file, "w")
    if not f then
        log.err("backup_worker", "failed to create pgpass file")
        return
    end
    f:write(string.format("%s:%s:%s:%s:%s\n", pg_host, pg_port, pg_db, pg_user, pg_pass))
    f:close()
    os.execute("chmod 600 " .. pgpass_file)

    -- Run pg_dump using PGPASSFILE (password not visible in process listing)
    local cmd = string.format(
        "PGPASSFILE='%s' pg_dump --no-password -h %s -p %s -U %s -d %s 2>/dev/null | gzip > %s",
        pgpass_file, pg_host, pg_port, pg_user, pg_db, backup_file
    )

    local ok = os.execute(cmd)

    -- Clean up pgpass file immediately
    os.remove(pgpass_file)

    if ok then
        -- Verify backup integrity
        local verify_cmd = string.format("gzip -t %s 2>/dev/null", backup_file)
        local verify_ok = os.execute(verify_cmd)
        if not verify_ok then
            log.err("backup_worker", "backup verification failed, file may be corrupted", { file = backup_file })
            os.remove(backup_file)
            return
        end

        log.info("backup_worker", "auto backup created and verified", { file = backup_file })

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

        -- Backup Evolution API volumes (if mounted)
        _M.backup_volumes(timestamp, log)
    else
        log.err("backup_worker", "auto backup failed")
    end
end

-- Backup Evolution API data volumes (mounted read-only)
function _M.backup_volumes(timestamp, log)
    -- Check if volume directories are mounted
    local f = io.open("/evolution_instances", "r")
    if not f then return end
    f:close()

    local vol_backup = "/backups/taguato_volumes_" .. timestamp .. ".tar.gz"
    local cmd = string.format(
        "tar czf %s -C / evolution_instances evolution_store 2>/dev/null",
        vol_backup
    )
    local ok = os.execute(cmd)

    if ok then
        log.info("backup_worker", "volume backup created", { file = vol_backup })

        -- Retain only last 7 volume backups
        local handle = io.popen("ls -1t /backups/taguato_volumes_*.tar.gz 2>/dev/null")
        local output = handle:read("*a")
        handle:close()

        local files = {}
        for line in output:gmatch("[^\n]+") do
            files[#files + 1] = line
        end

        if #files > 7 then
            for i = 8, #files do
                os.remove(files[i])
                log.info("backup_worker", "removed old volume backup", { file = files[i] })
            end
        end
    else
        log.err("backup_worker", "volume backup failed")
    end
end

return _M
