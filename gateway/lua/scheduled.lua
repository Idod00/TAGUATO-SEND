-- CRUD endpoints for scheduled messages
-- Requires auth.lua (ngx.ctx.user set)

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

local msg_id = uri:match("^/api/scheduled/(%d+)$")

-- GET /api/scheduled - List scheduled messages with pagination
if method == "GET" and uri == "/api/scheduled" then
    local args = ngx.req.get_uri_args()
    local page = tonumber(args.page) or 1
    local limit = tonumber(args.limit) or 20
    if limit > 100 then limit = 100 end
    local offset = (page - 1) * limit

    local conditions = { "user_id = $1" }
    local vals = { user.id }
    local idx = 1

    if args.status and args.status ~= "" then
        idx = idx + 1
        conditions[#conditions + 1] = "status = $" .. idx
        vals[idx] = args.status
    end

    local where = table.concat(conditions, " AND ")

    -- Count total
    local count_sql = "SELECT COUNT(*) as total FROM taguato.scheduled_messages WHERE " .. where
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

    local data_sql = "SELECT id, instance_name, message_type, message_content, recipients, scheduled_at, status, results, created_at, updated_at" ..
                     " FROM taguato.scheduled_messages WHERE " .. where ..
                     " ORDER BY scheduled_at DESC LIMIT $" .. (idx - 1) .. " OFFSET $" .. idx

    local res = db.query(data_sql, unpack(vals))

    json.respond(200, {
        messages = as_array(res),
        total = total,
        page = page,
        limit = limit,
        pages = math.ceil(total / limit),
    })
    return
end

-- GET /api/scheduled/{id} - Get detail
if method == "GET" and msg_id then
    local res, err = db.query(
        [[SELECT id, instance_name, message_type, message_content, recipients, scheduled_at, status, results, created_at, updated_at
          FROM taguato.scheduled_messages WHERE id = $1 AND user_id = $2]],
        msg_id, user.id
    )
    if not res or #res == 0 then
        json.respond(404, { error = "Scheduled message not found" })
        return
    end
    json.respond(200, { message = res[1] })
    return
end

-- POST /api/scheduled - Create scheduled message
if method == "POST" and uri == "/api/scheduled" then
    local body, err = json.read_body()
    if not body then
        json.respond(400, { error = "Invalid JSON body" })
        return
    end

    if not body.instance_name or body.instance_name == "" then
        json.respond(400, { error = "instance_name is required" })
        return
    end
    if not body.recipients or type(body.recipients) ~= "table" or #body.recipients == 0 then
        json.respond(400, { error = "recipients must be a non-empty array" })
        return
    end
    if not body.message_content or body.message_content == "" then
        json.respond(400, { error = "message_content is required" })
        return
    end
    if not body.scheduled_at or body.scheduled_at == "" then
        json.respond(400, { error = "scheduled_at is required" })
        return
    end

    -- Verify instance ownership
    local own_res = db.query(
        "SELECT id FROM taguato.user_instances WHERE user_id = $1 AND instance_name = $2 LIMIT 1",
        user.id, body.instance_name
    )
    -- Admin bypass: if user is admin, skip ownership check
    if user.role ~= "admin" then
        if not own_res or #own_res == 0 then
            json.respond(403, { error = "You do not own this instance" })
            return
        end
    end

    local message_type = body.message_type or "text"
    local recipients_json = cjson.encode(body.recipients)

    local res, err = db.query(
        [[INSERT INTO taguato.scheduled_messages (user_id, instance_name, message_type, message_content, recipients, scheduled_at)
          VALUES ($1, $2, $3, $4, $5, $6::timestamp)
          RETURNING id, instance_name, message_type, message_content, recipients, scheduled_at, status, created_at]],
        user.id, body.instance_name, message_type, body.message_content, recipients_json, body.scheduled_at
    )
    if not res or #res == 0 then
        json.respond(500, { error = "Failed to create scheduled message" })
        return
    end
    json.respond(201, { message = res[1] })
    return
end

-- PUT /api/scheduled/{id} - Update (only if pending)
if method == "PUT" and msg_id then
    local body, err = json.read_body()
    if not body then
        json.respond(400, { error = "Invalid JSON body" })
        return
    end

    -- Check current status
    local current = db.query(
        "SELECT id, status FROM taguato.scheduled_messages WHERE id = $1 AND user_id = $2",
        msg_id, user.id
    )
    if not current or #current == 0 then
        json.respond(404, { error = "Scheduled message not found" })
        return
    end
    if current[1].status ~= "pending" then
        json.respond(400, { error = "Only pending messages can be updated" })
        return
    end

    local sets = {}
    local vals = {}
    local idx = 0

    if body.instance_name then
        idx = idx + 1
        sets[#sets + 1] = "instance_name = $" .. idx
        vals[idx] = body.instance_name
    end
    if body.message_type then
        idx = idx + 1
        sets[#sets + 1] = "message_type = $" .. idx
        vals[idx] = body.message_type
    end
    if body.message_content then
        idx = idx + 1
        sets[#sets + 1] = "message_content = $" .. idx
        vals[idx] = body.message_content
    end
    if body.recipients and type(body.recipients) == "table" then
        idx = idx + 1
        sets[#sets + 1] = "recipients = $" .. idx
        vals[idx] = cjson.encode(body.recipients)
    end
    if body.scheduled_at then
        idx = idx + 1
        sets[#sets + 1] = "scheduled_at = $" .. idx .. "::timestamp"
        vals[idx] = body.scheduled_at
    end

    if #sets == 0 then
        json.respond(400, { error = "No fields to update" })
        return
    end

    sets[#sets + 1] = "updated_at = NOW()"
    idx = idx + 1
    vals[idx] = msg_id
    idx = idx + 1
    vals[idx] = user.id

    local sql = "UPDATE taguato.scheduled_messages SET " .. table.concat(sets, ", ") ..
                " WHERE id = $" .. (idx - 1) .. " AND user_id = $" .. idx ..
                " RETURNING id, instance_name, message_type, message_content, recipients, scheduled_at, status, created_at, updated_at"
    local res, err = db.query(sql, unpack(vals))
    if not res or #res == 0 then
        json.respond(404, { error = "Scheduled message not found" })
        return
    end
    json.respond(200, { message = res[1] })
    return
end

-- DELETE /api/scheduled/{id} - Cancel (only if pending)
if method == "DELETE" and msg_id then
    local current = db.query(
        "SELECT id, status FROM taguato.scheduled_messages WHERE id = $1 AND user_id = $2",
        msg_id, user.id
    )
    if not current or #current == 0 then
        json.respond(404, { error = "Scheduled message not found" })
        return
    end
    if current[1].status ~= "pending" then
        json.respond(400, { error = "Only pending messages can be cancelled" })
        return
    end

    local res, err = db.query(
        "UPDATE taguato.scheduled_messages SET status = 'cancelled', updated_at = NOW() WHERE id = $1 AND user_id = $2 RETURNING id, status",
        msg_id, user.id
    )
    if not res or #res == 0 then
        json.respond(500, { error = "Failed to cancel message" })
        return
    end
    json.respond(200, { message = res[1] })
    return
end

json.respond(404, { error = "Not found" })
