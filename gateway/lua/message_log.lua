-- Message log endpoints
-- POST /api/messages/log - Record a message send attempt
-- GET /api/messages/log - List message logs with pagination and filters

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
local uri = ngx.var.uri

-- POST /api/messages/log - Record message log
if method == "POST" and uri == "/api/messages/log" then
    local body, err = json.read_body()
    if not body then
        json.respond(400, { error = "Invalid JSON body" })
        return
    end

    local instance_name = body.instance_name
    local phone_number = body.phone_number
    local message_type = body.message_type or "text"
    local status = body.status or "sent"
    local error_message = body.error_message

    if not instance_name or not phone_number then
        json.respond(400, { error = "instance_name and phone_number are required" })
        return
    end

    local res, err = db.query(
        [[INSERT INTO taguato.message_logs (user_id, instance_name, phone_number, message_type, status, error_message)
          VALUES ($1, $2, $3, $4, $5, $6)
          RETURNING id, instance_name, phone_number, message_type, status, error_message, created_at]],
        user.id, instance_name, phone_number, message_type, status, error_message
    )
    if not res or #res == 0 then
        json.respond(500, { error = "Failed to log message" })
        return
    end
    json.respond(201, { log = res[1] })
    return
end

-- GET /api/messages/log - List logs with pagination
if method == "GET" and uri == "/api/messages/log" then
    local args = ngx.req.get_uri_args()
    local page = tonumber(args.page) or 1
    local limit = tonumber(args.limit) or 50
    if limit > 100 then limit = 100 end
    local offset = (page - 1) * limit

    -- Build WHERE clause
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

    -- Count total
    local count_sql = "SELECT COUNT(*) as total FROM taguato.message_logs WHERE " .. where
    local count_res = db.query(count_sql, unpack(vals))
    local total = 0
    if count_res and #count_res > 0 then
        total = tonumber(count_res[1].total) or 0
    end

    -- Fetch page
    idx = idx + 1
    vals[idx] = limit
    idx = idx + 1
    vals[idx] = offset

    local data_sql = "SELECT id, instance_name, phone_number, message_type, status, error_message, created_at" ..
                     " FROM taguato.message_logs WHERE " .. where ..
                     " ORDER BY created_at DESC LIMIT $" .. (idx - 1) .. " OFFSET $" .. idx

    local res = db.query(data_sql, unpack(vals))

    json.respond(200, {
        logs = as_array(res),
        total = total,
        page = page,
        limit = limit,
        pages = math.ceil(total / limit),
    })
    return
end

json.respond(404, { error = "Not found" })
