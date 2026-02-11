-- CSV export endpoint for message history
-- GET /api/messages/export - Download message logs as CSV

local db = require "init"
local json = require "json"

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

-- Escape CSV field
local function escape_csv(val)
    if not val then return "" end
    val = tostring(val)
    if val:find('[,"\n\r]') then
        return '"' .. val:gsub('"', '""') .. '"'
    end
    return val
end

local args = ngx.req.get_uri_args()

-- Build WHERE clause (same filters as message_log.lua)
local conditions = { "user_id = $1" }
local vals = { user.id }
local idx = 1

if args.status and args.status ~= "" then
    idx = idx + 1
    conditions[#conditions + 1] = "status = $" .. idx
    vals[idx] = args.status
end

if args.message_type and args.message_type ~= "" then
    idx = idx + 1
    conditions[#conditions + 1] = "message_type = $" .. idx
    vals[idx] = args.message_type
end

if args.instance_name and args.instance_name ~= "" then
    idx = idx + 1
    conditions[#conditions + 1] = "instance_name = $" .. idx
    vals[idx] = args.instance_name
end

if args.date_from and args.date_from ~= "" then
    idx = idx + 1
    conditions[#conditions + 1] = "created_at >= $" .. idx .. "::timestamp"
    vals[idx] = args.date_from
end

if args.date_to and args.date_to ~= "" then
    idx = idx + 1
    conditions[#conditions + 1] = "created_at <= $" .. idx .. "::timestamp"
    vals[idx] = args.date_to
end

local where = table.concat(conditions, " AND ")

-- Fetch all matching records (limit to 10000 for safety)
local sql = "SELECT id, instance_name, phone_number, message_type, status, error_message, created_at" ..
            " FROM taguato.message_logs WHERE " .. where ..
            " ORDER BY created_at DESC LIMIT 10000"

local res = db.query(sql, unpack(vals))

if not res then
    json.respond(500, { error = "Failed to export messages" })
    return
end

-- Build CSV
local lines = {}
lines[1] = "ID,Instance,Phone,Type,Status,Error,Date"

for _, row in ipairs(res) do
    lines[#lines + 1] = table.concat({
        escape_csv(row.id),
        escape_csv(row.instance_name),
        escape_csv(row.phone_number),
        escape_csv(row.message_type),
        escape_csv(row.status),
        escape_csv(row.error_message),
        escape_csv(row.created_at),
    }, ",")
end

local csv = table.concat(lines, "\n")

ngx.header["Content-Type"] = "text/csv; charset=utf-8"
ngx.header["Content-Disposition"] = "attachment; filename=message_history.csv"
ngx.say(csv)
