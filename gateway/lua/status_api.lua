-- Public status API endpoint
-- GET /api/status - Returns health of all services + active/recent incidents
-- Features: Redis cache (15s TTL), scheduled maintenances, uptime %

local db = require "init"
local json = require "json"
local cjson = require "cjson"

-- Ensure empty Lua tables serialize as JSON [] not {}
local empty_array_mt = cjson.empty_array_mt
local function as_array(t)
    if t == nil or (type(t) == "table" and #t == 0) then
        return setmetatable({}, empty_array_mt)
    end
    return t
end

if ngx.req.get_method() ~= "GET" then
    json.respond(405, { error = "Method not allowed" })
    return
end

-- Try Redis cache first
local redis = require "resty.redis"
local red = redis:new()
red:set_timeouts(3000, 3000, 3000)
local redis_host = os.getenv("REDIS_HOST") or "taguato-redis"
local redis_port = tonumber(os.getenv("REDIS_PORT")) or 6379

local cache_hit = false
local ok, err = red:connect(redis_host, redis_port)
if ok then
    local cached, _ = red:get("taguato:status:cache")
    if cached and cached ~= ngx.null then
        ngx.header["Content-Type"] = "application/json"
        ngx.header["X-Cache"] = "HIT"
        ngx.say(cached)
        red:set_keepalive(10000, 10)
        return
    end
    red:set_keepalive(10000, 10)
end

-- Cache miss: perform health checks

local services = {}

-- 1. Gateway - always operational (we're running)
services[1] = { name = "Gateway", status = "operational", response_time = 0 }

-- 2. Evolution API - internal subrequest
local t0 = ngx.now()
local res = ngx.location.capture("/_internal/api_health", { method = ngx.HTTP_GET })
local api_time = math.floor((ngx.now() - t0) * 1000)
if res and res.status == 200 then
    services[2] = { name = "Evolution API", status = "operational", response_time = api_time }
else
    services[2] = { name = "Evolution API", status = "major_outage", response_time = api_time }
end

-- 3. PostgreSQL - query SELECT 1
t0 = ngx.now()
local pg_res, pg_err = db.query("SELECT 1")
local pg_time = math.floor((ngx.now() - t0) * 1000)
if pg_res then
    services[3] = { name = "PostgreSQL", status = "operational", response_time = pg_time }
else
    services[3] = { name = "PostgreSQL", status = "major_outage", response_time = pg_time }
end

-- 4. Redis - connect + PING
local red2 = redis:new()
red2:set_timeouts(3000, 3000, 3000)
t0 = ngx.now()
local ok2, err2 = red2:connect(redis_host, redis_port)
if ok2 then
    local pong, _ = red2:ping()
    local redis_time = math.floor((ngx.now() - t0) * 1000)
    red2:set_keepalive(10000, 10)
    if pong then
        services[4] = { name = "Redis", status = "operational", response_time = redis_time }
    else
        services[4] = { name = "Redis", status = "major_outage", response_time = redis_time }
    end
else
    local redis_time = math.floor((ngx.now() - t0) * 1000)
    services[4] = { name = "Redis", status = "major_outage", response_time = redis_time }
end

-- Determine overall status
local overall = "operational"
local down_count = 0
local degraded = false
for _, svc in ipairs(services) do
    if svc.status == "major_outage" then
        down_count = down_count + 1
    elseif svc.status == "degraded" then
        degraded = true
    end
end
if down_count == #services then
    overall = "major_outage"
elseif down_count > 0 then
    overall = "partial_outage"
elseif degraded then
    overall = "degraded"
end

-- Check for active incidents that might override overall status
local active_incidents_res = db.query([[
    SELECT i.id, i.title, i.severity, i.status, i.created_at, i.updated_at
    FROM taguato.incidents i
    WHERE i.status != 'resolved'
    ORDER BY i.created_at DESC
]])
local active_incidents = as_array(active_incidents_res)

for _, inc in ipairs(active_incidents) do
    if inc.severity == "critical" and overall ~= "major_outage" then
        overall = "major_outage"
    elseif inc.severity == "major" and overall == "operational" then
        overall = "partial_outage"
    elseif inc.severity == "minor" and overall == "operational" then
        overall = "degraded"
    end
end

-- Enrich active incidents with affected services and updates
for _, inc in ipairs(active_incidents) do
    local svc_res = db.query([[
        SELECT s.name FROM taguato.incident_services isv
        JOIN taguato.services s ON s.id = isv.service_id
        WHERE isv.incident_id = $1
        ORDER BY s.display_order
    ]], inc.id)
    inc.affected_services = {}
    if svc_res then
        for _, s in ipairs(svc_res) do
            inc.affected_services[#inc.affected_services + 1] = s.name
        end
    end
    inc.affected_services = as_array(inc.affected_services)

    local upd_res = db.query([[
        SELECT iu.status, iu.message, iu.created_at
        FROM taguato.incident_updates iu
        WHERE iu.incident_id = $1
        ORDER BY iu.created_at DESC
    ]], inc.id)
    inc.updates = as_array(upd_res)
end

-- Recent resolved incidents (last 20)
local recent_res = db.query([[
    SELECT i.id, i.title, i.severity, i.status, i.created_at, i.resolved_at
    FROM taguato.incidents i
    WHERE i.status = 'resolved'
    ORDER BY i.resolved_at DESC
    LIMIT 20
]])
local recent_incidents = as_array(recent_res)

for _, inc in ipairs(recent_incidents) do
    local svc_res = db.query([[
        SELECT s.name FROM taguato.incident_services isv
        JOIN taguato.services s ON s.id = isv.service_id
        WHERE isv.incident_id = $1
        ORDER BY s.display_order
    ]], inc.id)
    inc.affected_services = {}
    if svc_res then
        for _, s in ipairs(svc_res) do
            inc.affected_services[#inc.affected_services + 1] = s.name
        end
    end
    inc.affected_services = as_array(inc.affected_services)

    local upd_res = db.query([[
        SELECT iu.status, iu.message, iu.created_at
        FROM taguato.incident_updates iu
        WHERE iu.incident_id = $1
        ORDER BY iu.created_at DESC
    ]], inc.id)
    inc.updates = as_array(upd_res)
end

-- Scheduled maintenances (upcoming + in_progress)
local maint_res = db.query([[
    SELECT m.id, m.title, m.description, m.scheduled_start, m.scheduled_end, m.status
    FROM taguato.scheduled_maintenances m
    WHERE m.status IN ('scheduled', 'in_progress')
    ORDER BY m.scheduled_start ASC
]])
local maintenances = as_array(maint_res)

for _, m in ipairs(maintenances) do
    local svc_res = db.query([[
        SELECT s.name FROM taguato.maintenance_services ms
        JOIN taguato.services s ON s.id = ms.service_id
        WHERE ms.maintenance_id = $1
        ORDER BY s.display_order
    ]], m.id)
    m.affected_services = {}
    if svc_res then
        for _, s in ipairs(svc_res) do
            m.affected_services[#m.affected_services + 1] = s.name
        end
    end
    m.affected_services = as_array(m.affected_services)
end

-- Uptime percentages (last 30 days)
local uptime = {}
local uptime_res = db.query([[
    SELECT service_name,
           COUNT(*) as total_checks,
           COUNT(*) FILTER (WHERE status = 'operational') as ok_checks
    FROM taguato.uptime_checks
    WHERE checked_at >= NOW() - INTERVAL '30 days'
    GROUP BY service_name
]])
if uptime_res then
    for _, row in ipairs(uptime_res) do
        local total = tonumber(row.total_checks) or 0
        local ok_count = tonumber(row.ok_checks) or 0
        if total > 0 then
            uptime[row.service_name] = math.floor((ok_count / total) * 10000) / 100
        end
    end
end

-- Daily uptime breakdown (last 30 days per service)
local uptime_daily = {}
local daily_res = db.query([[
    SELECT service_name,
           DATE(checked_at) as day,
           COUNT(*) as total,
           COUNT(*) FILTER (WHERE status = 'operational') as ok_count
    FROM taguato.uptime_checks
    WHERE checked_at >= NOW() - INTERVAL '30 days'
    GROUP BY service_name, DATE(checked_at)
    ORDER BY service_name, day
]])
if daily_res then
    for _, row in ipairs(daily_res) do
        if not uptime_daily[row.service_name] then
            uptime_daily[row.service_name] = {}
        end
        local total = tonumber(row.total) or 0
        local ok_count = tonumber(row.ok_count) or 0
        local pct = total > 0 and (math.floor((ok_count / total) * 10000) / 100) or 100
        uptime_daily[row.service_name][#uptime_daily[row.service_name] + 1] = {
            day = row.day,
            pct = pct
        }
    end
end

-- Response time history (hourly averages, last 24h)
local response_time_history = {}
local rt_res = db.query([[
    SELECT service_name, DATE_TRUNC('hour', checked_at) as hour,
           ROUND(AVG(response_time)) as avg_ms
    FROM taguato.uptime_checks
    WHERE checked_at >= NOW() - INTERVAL '24 hours'
    GROUP BY service_name, DATE_TRUNC('hour', checked_at)
    ORDER BY service_name, hour
]])
if rt_res then
    for _, row in ipairs(rt_res) do
        if not response_time_history[row.service_name] then
            response_time_history[row.service_name] = {}
        end
        local svc = response_time_history[row.service_name]
        svc[#svc + 1] = {
            hour = row.hour,
            avg_ms = tonumber(row.avg_ms) or 0,
        }
    end
end

local response_data = {
    overall_status = overall,
    services = services,
    active_incidents = active_incidents,
    recent_incidents = recent_incidents,
    scheduled_maintenances = maintenances,
    uptime = uptime,
    uptime_daily = uptime_daily,
    response_time_history = response_time_history,
    cached = false,
    checked_at = ngx.http_time(ngx.time()),
}

-- Store in Redis cache (15s TTL), graceful if Redis is down
local red3 = redis:new()
red3:set_timeouts(1000, 1000, 1000)
local ok3, _ = red3:connect(redis_host, redis_port)
if ok3 then
    local json_str = cjson.encode(response_data)
    red3:setex("taguato:status:cache", 15, json_str)
    red3:set_keepalive(10000, 10)
end

ngx.header["X-Cache"] = "MISS"
json.respond(200, response_data)
