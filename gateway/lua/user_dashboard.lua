-- User dashboard endpoint
-- GET /api/user/dashboard - Returns user-specific stats and metrics

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

-- Messages today
local today_res = db.query(
    "SELECT COUNT(*) as count FROM taguato.message_logs WHERE user_id = $1 AND created_at >= NOW() - INTERVAL '1 day'",
    user.id
)
local messages_today = 0
if today_res and #today_res > 0 then
    messages_today = tonumber(today_res[1].count) or 0
end

-- Messages this week
local week_res = db.query(
    "SELECT COUNT(*) as count FROM taguato.message_logs WHERE user_id = $1 AND created_at >= NOW() - INTERVAL '7 days'",
    user.id
)
local messages_week = 0
if week_res and #week_res > 0 then
    messages_week = tonumber(week_res[1].count) or 0
end

-- Messages this month
local month_res = db.query(
    "SELECT COUNT(*) as count FROM taguato.message_logs WHERE user_id = $1 AND created_at >= NOW() - INTERVAL '30 days'",
    user.id
)
local messages_month = 0
if month_res and #month_res > 0 then
    messages_month = tonumber(month_res[1].count) or 0
end

-- Total messages
local total_res = db.query(
    "SELECT COUNT(*) as count FROM taguato.message_logs WHERE user_id = $1",
    user.id
)
local messages_total = 0
if total_res and #total_res > 0 then
    messages_total = tonumber(total_res[1].count) or 0
end

-- Delivery rate (sent vs total)
local sent_res = db.query(
    "SELECT COUNT(*) as count FROM taguato.message_logs WHERE user_id = $1 AND status = 'sent'",
    user.id
)
local sent_count = 0
if sent_res and #sent_res > 0 then
    sent_count = tonumber(sent_res[1].count) or 0
end
local delivery_rate = 0
if messages_total > 0 then
    delivery_rate = math.floor((sent_count / messages_total) * 100)
end

-- Instance count
local inst_res = db.query(
    "SELECT COUNT(*) as count FROM taguato.user_instances WHERE user_id = $1",
    user.id
)
local instance_count = 0
if inst_res and #inst_res > 0 then
    instance_count = tonumber(inst_res[1].count) or 0
end

-- Messages per day (last 7 days)
local daily_res = db.query(
    [[SELECT DATE(created_at) as day, COUNT(*) as count
      FROM taguato.message_logs
      WHERE user_id = $1 AND created_at >= NOW() - INTERVAL '7 days'
      GROUP BY DATE(created_at)
      ORDER BY day ASC]],
    user.id
)

local daily = as_array(daily_res)

json.respond(200, {
    messages_today = messages_today,
    messages_week = messages_week,
    messages_month = messages_month,
    messages_total = messages_total,
    delivery_rate = delivery_rate,
    instances = instance_count,
    max_instances = user.max_instances or 1,
    daily = daily,
})
