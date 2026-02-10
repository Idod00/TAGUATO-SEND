-- Uptime worker: runs in init_worker timer context every 5 minutes
-- Checks health of all 4 services and stores results in taguato.uptime_checks
-- Note: ngx.location.capture is NOT available in timer context, so we use cosocket

local pgmoon = require "pgmoon"

local _M = {}

local pg_config = {
    host = os.getenv("PG_HOST") or "taguato-postgres",
    port = tonumber(os.getenv("PG_PORT")) or 5432,
    database = os.getenv("PG_DATABASE") or "evolution",
    user = os.getenv("PG_USER") or "taguato",
    password = os.getenv("PG_PASSWORD") or "taguato_secret",
}

-- Simple HTTP GET via raw TCP cosocket (no resty.http dependency)
local function http_get_health(host, port, path, timeout_ms)
    local sock = ngx.socket.tcp()
    sock:settimeouts(timeout_ms, timeout_ms, timeout_ms)

    local ok, err = sock:connect(host, port)
    if not ok then
        return nil, err
    end

    local req = "GET " .. path .. " HTTP/1.0\r\nHost: " .. host .. "\r\nConnection: close\r\n\r\n"
    local bytes, err = sock:send(req)
    if not bytes then
        sock:close()
        return nil, err
    end

    local status_line, err = sock:receive("*l")
    if not status_line then
        sock:close()
        return nil, err
    end

    local status_code = tonumber(status_line:match("HTTP/%d%.%d (%d+)"))
    sock:close()
    return status_code
end

function _M.check()
    local results = {}
    local t0

    -- 1. Gateway - always operational (we're the gateway)
    results[1] = { name = "Gateway", status = "operational", response_time = 0 }

    -- 2. Evolution API - raw HTTP GET to taguato-api:8080/ (v2.3.7 root endpoint)
    t0 = ngx.now()
    local api_status, api_err = http_get_health("taguato-api", 8080, "/", 5000)
    local api_time = math.floor((ngx.now() - t0) * 1000)
    if api_status and api_status == 200 then
        results[2] = { name = "Evolution API", status = "operational", response_time = api_time }
    else
        results[2] = { name = "Evolution API", status = "major_outage", response_time = api_time }
        ngx.log(ngx.WARN, "uptime_worker: Evolution API health check failed: ", api_err or ("status=" .. tostring(api_status)))
    end

    -- 3. PostgreSQL - pgmoon connect + SELECT 1
    t0 = ngx.now()
    local pg = pgmoon.new(pg_config)
    local pg_ok, pg_err = pg:connect()
    local pg_status = "major_outage"
    if pg_ok then
        local res, query_err = pg:query("SELECT 1")
        if res then
            pg_status = "operational"
        end
        pg:keepalive(10000, 10)
    else
        ngx.log(ngx.WARN, "uptime_worker: PostgreSQL connect failed: ", pg_err)
    end
    local pg_time = math.floor((ngx.now() - t0) * 1000)
    results[3] = { name = "PostgreSQL", status = pg_status, response_time = pg_time }

    -- 4. Redis - connect + PING
    local redis_lib = require "resty.redis"
    local red = redis_lib:new()
    red:set_timeouts(3000, 3000, 3000)
    local redis_host = os.getenv("REDIS_HOST") or "taguato-redis"
    local redis_port = tonumber(os.getenv("REDIS_PORT")) or 6379

    t0 = ngx.now()
    local redis_ok, redis_err = red:connect(redis_host, redis_port)
    local redis_status = "major_outage"
    if redis_ok then
        local pong, _ = red:ping()
        if pong then
            redis_status = "operational"
        end
        red:set_keepalive(10000, 10)
    else
        ngx.log(ngx.WARN, "uptime_worker: Redis connect failed: ", redis_err)
    end
    local redis_time = math.floor((ngx.now() - t0) * 1000)
    results[4] = { name = "Redis", status = redis_status, response_time = redis_time }

    -- Insert results into database
    local pg2 = pgmoon.new(pg_config)
    local ok2, err2 = pg2:connect()
    if not ok2 then
        ngx.log(ngx.ERR, "uptime_worker: cannot connect to DB for insert: ", err2)
        return
    end

    for _, r in ipairs(results) do
        local sql = "INSERT INTO taguato.uptime_checks (service_name, status, response_time) VALUES ("
            .. pg2:escape_literal(r.name) .. ", "
            .. pg2:escape_literal(r.status) .. ", "
            .. tostring(r.response_time) .. ")"
        local res, qerr = pg2:query(sql)
        if not res then
            ngx.log(ngx.ERR, "uptime_worker: insert failed: ", qerr)
        end
    end

    -- Cleanup: delete records older than 90 days
    pg2:query("DELETE FROM taguato.uptime_checks WHERE checked_at < NOW() - INTERVAL '90 days'")

    pg2:keepalive(10000, 10)
    ngx.log(ngx.INFO, "uptime_worker: check completed, 4 services recorded")
end

return _M
