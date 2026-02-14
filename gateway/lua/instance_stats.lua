-- Instance stats endpoint
-- GET /api/instance/stats/{name} - Returns per-instance statistics

local db = require "init"
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
if not user then
    json.respond(401, { error = "Unauthorized" })
    return
end

local method = ngx.req.get_method()
if method ~= "GET" then
    json.respond(405, { error = "Method not allowed" })
    return
end

-- Extract instance name from URI: /api/instance/stats/{name}
local instance_name = ngx.var.uri:match("/api/instance/stats/(.+)")
if not instance_name then
    json.respond(400, { error = "Instance name required" })
    return
end
instance_name = ngx.unescape_uri(instance_name)

-- Verify ownership (unless admin)
if user.role ~= "admin" then
    local own = db.query(
        "SELECT id FROM taguato.user_instances WHERE user_id = $1 AND instance_name = $2 LIMIT 1",
        user.id, instance_name
    )
    if not own or #own == 0 then
        json.respond(403, { error = "Instance not found or not owned by you" })
        return
    end
end

-- Total messages by status
local counts_res = db.query(
    [[SELECT
        COUNT(*) as total,
        COUNT(*) FILTER (WHERE status = 'sent') as sent,
        COUNT(*) FILTER (WHERE status = 'failed') as failed,
        COUNT(*) FILTER (WHERE status = 'cancelled') as cancelled
      FROM taguato.message_logs
      WHERE user_id = $1 AND instance_name = $2]],
    user.id, instance_name
)

local total = 0
local sent = 0
local failed = 0
local cancelled = 0
if counts_res and #counts_res > 0 then
    total = tonumber(counts_res[1].total) or 0
    sent = tonumber(counts_res[1].sent) or 0
    failed = tonumber(counts_res[1].failed) or 0
    cancelled = tonumber(counts_res[1].cancelled) or 0
end

local delivery_rate = 0
if total > 0 then
    delivery_rate = math.floor((sent / total) * 100)
end

-- Recent errors (last 10)
local errors_res = db.query(
    [[SELECT phone_number, message_type, error_message,
             TO_CHAR(created_at, 'YYYY-MM-DD HH24:MI') as created_at
      FROM taguato.message_logs
      WHERE user_id = $1 AND instance_name = $2 AND status = 'failed'
      ORDER BY created_at DESC LIMIT 10]],
    user.id, instance_name
)

-- Reconnection history (last 20)
local reconnect_res = db.query(
    [[SELECT previous_state, action, result, error_message,
             TO_CHAR(created_at, 'YYYY-MM-DD HH24:MI') as created_at
      FROM taguato.reconnect_log
      WHERE instance_name = $1
      ORDER BY created_at DESC LIMIT 20]],
    instance_name
)

-- Messages per day last 7 days (with sent/failed breakdown)
local daily_res = db.query(
    [[SELECT DATE(created_at) as day,
             COUNT(*) as total,
             COUNT(*) FILTER (WHERE status = 'sent') as sent,
             COUNT(*) FILTER (WHERE status = 'failed') as failed
      FROM taguato.message_logs
      WHERE user_id = $1 AND instance_name = $2 AND created_at >= NOW() - INTERVAL '7 days'
      GROUP BY DATE(created_at)
      ORDER BY day ASC]],
    user.id, instance_name
)

-- Registration date
local reg_res = db.query(
    "SELECT TO_CHAR(created_at, 'YYYY-MM-DD HH24:MI') as created_at FROM taguato.user_instances WHERE user_id = $1 AND instance_name = $2 LIMIT 1",
    user.id, instance_name
)

local registered_at = nil
if reg_res and #reg_res > 0 then
    registered_at = reg_res[1].created_at
end

json.respond(200, {
    instance_name = instance_name,
    total = total,
    sent = sent,
    failed = failed,
    cancelled = cancelled,
    delivery_rate = delivery_rate,
    registered_at = registered_at,
    recent_errors = as_array(errors_res),
    reconnections = as_array(reconnect_res),
    daily = as_array(daily_res),
})
