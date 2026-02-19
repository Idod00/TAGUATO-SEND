-- Admin CRUD endpoints for scheduled maintenance management
-- All endpoints require role=admin (enforced by auth.lua in nginx location)

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

local method = ngx.req.get_method()
local uri = ngx.var.uri

-- Helper: decode json_agg string fields returned by PostgreSQL
local function decode_json_field(row, field)
    if type(row[field]) == "string" then
        local ok, data = pcall(cjson.decode, row[field])
        row[field] = ok and data or as_array(nil)
    elseif not row[field] then
        row[field] = as_array(nil)
    end
end

-- Route: GET /admin/maintenance - List all maintenances (paginated)
if method == "GET" and uri == "/admin/maintenance" then
    local args = ngx.req.get_uri_args()
    local page = tonumber(args.page) or 1
    local limit = tonumber(args.limit) or 50
    if limit > 100 then limit = 100 end
    local offset = (page - 1) * limit

    local conditions = {}
    local vals = {}
    local idx = 0

    if args.status and args.status ~= "" then
        idx = idx + 1
        conditions[#conditions + 1] = "m.status = $" .. idx
        vals[idx] = args.status
    end

    local where = ""
    if #conditions > 0 then
        where = " WHERE " .. table.concat(conditions, " AND ")
    end

    -- Count total
    local count_sql = "SELECT COUNT(*) as total FROM taguato.scheduled_maintenances m" .. where
    local count_res = db.query(count_sql, unpack(vals))
    local total = 0
    if count_res and #count_res > 0 then
        total = tonumber(count_res[1].total) or 0
    end

    -- Fetch page with correlated subquery (no N+1)
    idx = idx + 1
    vals[idx] = limit
    idx = idx + 1
    vals[idx] = offset

    local data_sql = [[
        SELECT m.id, m.title, m.description, m.scheduled_start, m.scheduled_end,
               m.status, m.created_at, m.updated_at,
               u.username as created_by_name,
               COALESCE((SELECT json_agg(row_to_json(s_row)) FROM (
                   SELECT s.id, s.name FROM taguato.maintenance_services ms
                   JOIN taguato.services s ON s.id = ms.service_id
                   WHERE ms.maintenance_id = m.id
                   ORDER BY s.display_order
               ) s_row), '[]') as affected_services
        FROM taguato.scheduled_maintenances m
        LEFT JOIN taguato.users u ON u.id = m.created_by
    ]] .. where .. [[
        ORDER BY
            CASE WHEN m.status = 'in_progress' THEN 0
                 WHEN m.status = 'scheduled' THEN 1
                 ELSE 2 END,
            m.scheduled_start DESC
        LIMIT $]] .. (idx - 1) .. " OFFSET $" .. idx

    local res = db.query(data_sql, unpack(vals))
    if not res then
        json.respond(500, { error = "Failed to list maintenances" })
        return
    end

    for _, m in ipairs(res) do
        decode_json_field(m, "affected_services")
    end

    json.respond(200, {
        maintenances = as_array(res),
        total = total,
        page = page,
        limit = limit,
        pages = math.ceil(total / limit),
    })
    return
end

-- Route: POST /admin/maintenance - Create maintenance
if method == "POST" and uri == "/admin/maintenance" then
    local body, err = json.read_body()
    if not body then
        json.respond(400, { error = "Invalid JSON body" })
        return
    end

    local title = body.title
    local description = body.description or ""
    local scheduled_start = body.scheduled_start
    local scheduled_end = body.scheduled_end
    local service_ids = body.service_ids

    if not title or not scheduled_start or not scheduled_end then
        json.respond(400, { error = "title, scheduled_start, and scheduled_end are required" })
        return
    end

    local res, err = db.query(
        [[INSERT INTO taguato.scheduled_maintenances (title, description, scheduled_start, scheduled_end, created_by)
          VALUES ($1, $2, $3, $4, $5)
          RETURNING id, title, description, scheduled_start, scheduled_end, status, created_at]],
        title, description, scheduled_start, scheduled_end, user.id
    )
    if not res or #res == 0 then
        json.respond(500, { error = "Failed to create maintenance" })
        return
    end

    local maintenance = res[1]

    -- Link affected services
    if service_ids and type(service_ids) == "table" then
        for _, sid in ipairs(service_ids) do
            db.query(
                "INSERT INTO taguato.maintenance_services (maintenance_id, service_id) VALUES ($1, $2) ON CONFLICT DO NOTHING",
                maintenance.id, sid
            )
        end
    end

    -- Audit log
    local audit = require "audit"
    audit.log(user.id, user.username, "maintenance_created", "maintenance", tostring(maintenance.id),
        { title = maintenance.title }, ngx.var.remote_addr)

    json.respond(201, { maintenance = maintenance })
    return
end

-- Extract maintenance ID from URI: /admin/maintenance/123
local maint_id = uri:match("^/admin/maintenance/(%d+)$")

-- Route: PUT /admin/maintenance/{id} - Update maintenance
if method == "PUT" and maint_id then
    local body, err = json.read_body()
    if not body then
        json.respond(400, { error = "Invalid JSON body" })
        return
    end

    local sets = {}
    local vals = {}
    local idx = 0

    if body.title then
        idx = idx + 1
        sets[#sets + 1] = "title = $" .. idx
        vals[idx] = body.title
    end

    if body.description then
        idx = idx + 1
        sets[#sets + 1] = "description = $" .. idx
        vals[idx] = body.description
    end

    if body.scheduled_start then
        idx = idx + 1
        sets[#sets + 1] = "scheduled_start = $" .. idx
        vals[idx] = body.scheduled_start
    end

    if body.scheduled_end then
        idx = idx + 1
        sets[#sets + 1] = "scheduled_end = $" .. idx
        vals[idx] = body.scheduled_end
    end

    if body.status then
        local validate = require "validate"
        local st_ok, st_err = validate.validate_enum(body.status, "status", {"scheduled", "in_progress", "completed"})
        if not st_ok then
            json.respond(400, { error = st_err })
            return
        end
        idx = idx + 1
        sets[#sets + 1] = "status = $" .. idx
        vals[idx] = body.status
    end

    if body.service_ids and type(body.service_ids) == "table" then
        db.query("DELETE FROM taguato.maintenance_services WHERE maintenance_id = $1", maint_id)
        for _, sid in ipairs(body.service_ids) do
            db.query(
                "INSERT INTO taguato.maintenance_services (maintenance_id, service_id) VALUES ($1, $2) ON CONFLICT DO NOTHING",
                maint_id, sid
            )
        end
    end

    if #sets == 0 and not body.service_ids then
        json.respond(400, { error = "No fields to update" })
        return
    end

    if #sets > 0 then
        sets[#sets + 1] = "updated_at = NOW()"
        idx = idx + 1
        vals[idx] = maint_id

        local sql = "UPDATE taguato.scheduled_maintenances SET " .. table.concat(sets, ", ") ..
                    " WHERE id = $" .. idx ..
                    " RETURNING id, title, description, scheduled_start, scheduled_end, status, updated_at"

        local res, err = db.query(sql, unpack(vals))
        if not res or #res == 0 then
            json.respond(404, { error = "Maintenance not found" })
            return
        end
        json.respond(200, { maintenance = res[1] })
        return
    end

    json.respond(200, { message = "Services updated" })
    return
end

-- Route: DELETE /admin/maintenance/{id} - Delete maintenance
if method == "DELETE" and maint_id then
    local res, err = db.query(
        "DELETE FROM taguato.scheduled_maintenances WHERE id = $1 RETURNING id, title",
        maint_id
    )
    if not res or #res == 0 then
        json.respond(404, { error = "Maintenance not found" })
        return
    end
    -- Audit log
    local audit = require "audit"
    audit.log(user.id, user.username, "maintenance_deleted", "maintenance", maint_id,
        { title = res[1].title }, ngx.var.remote_addr)

    json.respond(200, { deleted = res[1] })
    return
end

-- No route matched
json.respond(404, { error = "Not found" })
