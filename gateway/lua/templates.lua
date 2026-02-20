-- CRUD endpoints for message templates
-- Requires auth.lua (ngx.ctx.user set)

local db = require "init"
local json = require "json"
local cjson = require "cjson"
local validate = require "validate"

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

local template_id = uri:match("^/api/templates/(%d+)$")

-- GET /api/templates - List user's templates (paginated)
if method == "GET" and uri == "/api/templates" then
    local args = ngx.req.get_uri_args()
    local page = tonumber(args.page) or 1
    local limit = tonumber(args.limit) or 50
    if limit > 100 then limit = 100 end
    local offset = (page - 1) * limit

    -- Count total
    local count_res = db.query(
        "SELECT COUNT(*) as total FROM taguato.message_templates WHERE user_id = $1",
        user.id
    )
    local total = 0
    if count_res and #count_res > 0 then
        total = tonumber(count_res[1].total) or 0
    end

    -- Fetch page
    local res, err = db.query(
        "SELECT id, name, content, created_at, updated_at FROM taguato.message_templates WHERE user_id = $1 ORDER BY updated_at DESC LIMIT $2 OFFSET $3",
        user.id, limit, offset
    )
    if not res then
        json.respond(500, { error = "Failed to list templates" })
        return
    end

    json.respond(200, {
        templates = as_array(res),
        total = total,
        page = page,
        limit = limit,
        pages = math.ceil(total / limit),
    })
    return
end

-- POST /api/templates - Create template
if method == "POST" and uri == "/api/templates" then
    local body, err = json.read_body()
    if not body then
        json.respond(400, { error = "Invalid JSON body" })
        return
    end
    if not body.name or not body.content then
        json.respond(400, { error = "name and content are required" })
        return
    end
    local name_ok, name_err = validate.validate_string(body.name, "name", 1, 100)
    if not name_ok then
        json.respond(400, { error = name_err })
        return
    end
    local content_ok, content_err = validate.validate_string(body.content, "content", 1, 5000)
    if not content_ok then
        json.respond(400, { error = content_err })
        return
    end
    local res, err = db.query(
        [[INSERT INTO taguato.message_templates (user_id, name, content)
          VALUES ($1, $2, $3)
          RETURNING id, name, content, created_at, updated_at]],
        user.id, body.name, body.content
    )
    if not res or #res == 0 then
        json.respond(500, { error = "Failed to create template" })
        return
    end
    json.respond(201, { template = res[1] })
    return
end

-- PUT /api/templates/{id} - Update template
if method == "PUT" and template_id then
    local body, err = json.read_body()
    if not body then
        json.respond(400, { error = "Invalid JSON body" })
        return
    end
    local sets = {}
    local vals = {}
    local idx = 0
    if body.name then
        idx = idx + 1
        sets[#sets + 1] = "name = $" .. idx
        vals[idx] = body.name
    end
    if body.content then
        idx = idx + 1
        sets[#sets + 1] = "content = $" .. idx
        vals[idx] = body.content
    end
    if #sets == 0 then
        json.respond(400, { error = "No fields to update" })
        return
    end
    sets[#sets + 1] = "updated_at = NOW()"
    idx = idx + 1
    vals[idx] = template_id
    idx = idx + 1
    vals[idx] = user.id

    local sql = "UPDATE taguato.message_templates SET " .. table.concat(sets, ", ") ..
                " WHERE id = $" .. (idx - 1) .. " AND user_id = $" .. idx ..
                " RETURNING id, name, content, created_at, updated_at"
    local res, err = db.query(sql, unpack(vals))
    if not res or #res == 0 then
        json.respond(404, { error = "Template not found" })
        return
    end
    json.respond(200, { template = res[1] })
    return
end

-- DELETE /api/templates/{id} - Delete template
if method == "DELETE" and template_id then
    local res, err = db.query(
        "DELETE FROM taguato.message_templates WHERE id = $1 AND user_id = $2 RETURNING id, name",
        template_id, user.id
    )
    if not res or #res == 0 then
        json.respond(404, { error = "Template not found" })
        return
    end
    json.respond(200, { deleted = res[1] })
    return
end

json.respond(404, { error = "Not found" })
