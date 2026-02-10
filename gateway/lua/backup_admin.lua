-- Backup admin endpoints
-- POST /admin/backup - Trigger database backup
-- GET /admin/backup - List existing backups

local json = require "json"
local cjson = require "cjson"

local empty_array_mt = cjson.empty_array_mt
local function as_array(t)
    if t == nil or (type(t) == "table" and #t == 0) then
        return setmetatable({}, empty_array_mt)
    end
    return t
end

local user = ngx.ctx.user
if not user or user.role ~= "admin" then
    json.respond(403, { error = "Admin access required" })
    return
end

local method = ngx.req.get_method()
local uri = ngx.var.uri

-- GET /admin/backup - List backups
if method == "GET" and uri == "/admin/backup" then
    local handle = io.popen("ls -lt /backups/*.sql.gz 2>/dev/null | head -20")
    local output = handle:read("*a")
    handle:close()

    local backups = {}
    for line in output:gmatch("[^\n]+") do
        local perms, links, owner, group, size, month, day, time_or_year, name = line:match(
            "(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(.+)"
        )
        if name then
            local filename = name:match("([^/]+)$")
            backups[#backups + 1] = {
                filename = filename,
                size = size,
                date = month .. " " .. day .. " " .. time_or_year,
            }
        end
    end

    json.respond(200, { backups = as_array(backups) })
    return
end

-- POST /admin/backup - Create backup
if method == "POST" and uri == "/admin/backup" then
    local pg_user = os.getenv("PG_USER") or "taguato"
    local pg_host = os.getenv("PG_HOST") or "taguato-postgres"
    local pg_port = os.getenv("PG_PORT") or "5432"
    local pg_db = os.getenv("PG_DATABASE") or "evolution"
    local pg_pass = os.getenv("PG_PASSWORD") or "taguato_secret"

    local timestamp = os.date("%Y%m%d_%H%M%S")
    local backup_file = "/backups/taguato_backup_" .. timestamp .. ".sql.gz"

    -- Create backups directory if not exists
    os.execute("mkdir -p /backups")

    -- Run pg_dump
    local cmd = string.format(
        "PGPASSWORD='%s' pg_dump -h %s -p %s -U %s -d %s 2>/dev/null | gzip > %s",
        pg_pass, pg_host, pg_port, pg_user, pg_db, backup_file
    )

    local ok = os.execute(cmd)

    if ok then
        -- Get file size
        local handle = io.popen("ls -lh " .. backup_file .. " 2>/dev/null")
        local output = handle:read("*a")
        handle:close()
        local size = output:match("%S+%s+%S+%s+%S+%s+%S+%s+(%S+)") or "unknown"

        -- Log audit
        local audit = require "audit"
        audit.log(user.id, user.username, "backup_created", "backup", backup_file, { size = size }, ngx.var.remote_addr)

        json.respond(201, {
            message = "Backup created",
            filename = "taguato_backup_" .. timestamp .. ".sql.gz",
            size = size,
        })
    else
        json.respond(500, { error = "Backup failed" })
    end
    return
end

json.respond(404, { error = "Not found" })
