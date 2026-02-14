-- Admin dashboard API endpoint
-- GET /admin/dashboard - Returns system stats for admin panel

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

-- Verify admin role
local user = ngx.ctx.user
if not user or user.role ~= "admin" then
    json.respond(403, { error = "Admin access required" })
    return
end

if ngx.req.get_method() ~= "GET" then
    json.respond(405, { error = "Method not allowed" })
    return
end

-- 1. User counts
local users_res = db.query(
    "SELECT COUNT(*) as total, COUNT(*) FILTER (WHERE is_active) as active FROM taguato.users"
)
local users = { total = 0, active = 0 }
if users_res and #users_res > 0 then
    users.total = tonumber(users_res[1].total) or 0
    users.active = tonumber(users_res[1].active) or 0
end

-- 2. Registered instances count
local inst_res = db.query("SELECT COUNT(*) as total FROM taguato.user_instances")
local total_registered = 0
if inst_res and #inst_res > 0 then
    total_registered = tonumber(inst_res[1].total) or 0
end

-- 3. Evolution API instances (internal subrequest)
local total_evolution = 0
local connected = 0
local evo_res = ngx.location.capture("/_internal/fetch_instances", { method = ngx.HTTP_GET })
if evo_res and evo_res.status == 200 and evo_res.body then
    local ok, evo_data = pcall(cjson.decode, evo_res.body)
    if ok and type(evo_data) == "table" then
        total_evolution = #evo_data
        for _, inst in ipairs(evo_data) do
            if inst.instance and inst.instance.state == "open" then
                connected = connected + 1
            end
        end
    end
end

-- 4. Uptime global 30d
local uptime_30d = 100
local uptime_res = db.query([[
    SELECT COUNT(*) as total, COUNT(*) FILTER (WHERE status = 'operational') as ok
    FROM taguato.uptime_checks
    WHERE checked_at >= NOW() - INTERVAL '30 days'
]])
if uptime_res and #uptime_res > 0 then
    local total = tonumber(uptime_res[1].total) or 0
    local ok_count = tonumber(uptime_res[1].ok) or 0
    if total > 0 then
        uptime_30d = math.floor((ok_count / total) * 10000) / 100
    end
end

-- 5. Message metrics
local messages = { today = 0, total = 0, sent = 0, failed = 0, delivery_rate = 0 }
local msg_res = db.query([[
    SELECT
        COUNT(*) as total,
        COUNT(*) FILTER (WHERE status = 'sent') as sent,
        COUNT(*) FILTER (WHERE status = 'failed') as failed,
        COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '1 day') as today
    FROM taguato.message_logs
]])
if msg_res and #msg_res > 0 then
    messages.total = tonumber(msg_res[1].total) or 0
    messages.sent = tonumber(msg_res[1].sent) or 0
    messages.failed = tonumber(msg_res[1].failed) or 0
    messages.today = tonumber(msg_res[1].today) or 0
    if messages.total > 0 then
        messages.delivery_rate = math.floor((messages.sent / messages.total) * 10000) / 100
    end
end

-- 6. Recent activity (users + instances + messages + logins, merged)
local recent_activity = {}

local recent_users = db.query([[
    SELECT username as name, created_at FROM taguato.users
    ORDER BY created_at DESC LIMIT 5
]])
if recent_users then
    for _, u in ipairs(recent_users) do
        recent_activity[#recent_activity + 1] = {
            type = "user_created",
            name = u.name,
            created_at = u.created_at,
        }
    end
end

local recent_instances = db.query([[
    SELECT instance_name as name, created_at FROM taguato.user_instances
    ORDER BY created_at DESC LIMIT 5
]])
if recent_instances then
    for _, inst in ipairs(recent_instances) do
        recent_activity[#recent_activity + 1] = {
            type = "instance_created",
            name = inst.name,
            created_at = inst.created_at,
        }
    end
end

local recent_messages = db.query([[
    SELECT instance_name as name, status, created_at FROM taguato.message_logs
    ORDER BY created_at DESC LIMIT 5
]])
if recent_messages then
    for _, m in ipairs(recent_messages) do
        recent_activity[#recent_activity + 1] = {
            type = m.status == "sent" and "message_sent" or "message_failed",
            name = m.name,
            created_at = m.created_at,
        }
    end
end

local recent_logins = db.query([[
    SELECT username as name, created_at FROM taguato.audit_log
    WHERE action = 'user_login'
    ORDER BY created_at DESC LIMIT 5
]])
if recent_logins then
    for _, l in ipairs(recent_logins) do
        recent_activity[#recent_activity + 1] = {
            type = "user_login",
            name = l.name,
            created_at = l.created_at,
        }
    end
end

-- Sort by created_at descending
table.sort(recent_activity, function(a, b)
    return (a.created_at or "") > (b.created_at or "")
end)

-- Trim to 15 max
while #recent_activity > 15 do
    recent_activity[#recent_activity] = nil
end

-- 7. Recent reconnections (last 5)
local recent_reconnections = db.query([[
    SELECT instance_name, previous_state, result, error_message, created_at
    FROM taguato.reconnect_log
    ORDER BY created_at DESC LIMIT 5
]])

json.respond(200, {
    users = users,
    instances = {
        total_registered = total_registered,
        total_evolution = total_evolution,
        connected = connected,
    },
    uptime_30d = uptime_30d,
    messages = messages,
    recent_activity = as_array(recent_activity),
    recent_reconnections = as_array(recent_reconnections),
})
