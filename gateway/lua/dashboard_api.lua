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

-- 5. Recent activity (last 5 users + last 5 instances, merged)
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

-- Sort by created_at descending
table.sort(recent_activity, function(a, b)
    return (a.created_at or "") > (b.created_at or "")
end)

-- Trim to 10 max
while #recent_activity > 10 do
    recent_activity[#recent_activity] = nil
end

-- 6. Recent reconnections (last 5)
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
    recent_activity = as_array(recent_activity),
    recent_reconnections = as_array(recent_reconnections),
})
