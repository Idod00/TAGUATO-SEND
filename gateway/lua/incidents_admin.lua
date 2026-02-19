-- Admin CRUD endpoints for incident management
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

-- Route: GET /admin/incidents/services - List services for checkboxes
if method == "GET" and uri == "/admin/incidents/services" then
    local res, err = db.query(
        "SELECT id, name, description, display_order FROM taguato.services WHERE is_active = TRUE ORDER BY display_order"
    )
    if not res then
        json.respond(500, { error = "Failed to list services" })
        return
    end
    json.respond(200, { services = as_array(res) })
    return
end

-- Helper: decode json_agg string fields returned by PostgreSQL
local function decode_json_field(row, field)
    if type(row[field]) == "string" then
        local ok, data = pcall(cjson.decode, row[field])
        row[field] = ok and data or as_array(nil)
    elseif not row[field] then
        row[field] = as_array(nil)
    end
end

-- Route: GET /admin/incidents - List all incidents (paginated)
if method == "GET" and uri == "/admin/incidents" then
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
        conditions[#conditions + 1] = "i.status = $" .. idx
        vals[idx] = args.status
    end

    local where = ""
    if #conditions > 0 then
        where = " WHERE " .. table.concat(conditions, " AND ")
    end

    -- Count total
    local count_sql = "SELECT COUNT(*) as total FROM taguato.incidents i" .. where
    local count_res = db.query(count_sql, unpack(vals))
    local total = 0
    if count_res and #count_res > 0 then
        total = tonumber(count_res[1].total) or 0
    end

    -- Fetch page with correlated subqueries (no N+1)
    idx = idx + 1
    vals[idx] = limit
    idx = idx + 1
    vals[idx] = offset

    local data_sql = [[
        SELECT i.id, i.title, i.severity, i.status, i.created_at, i.updated_at, i.resolved_at,
               u.username as created_by_name,
               COALESCE((SELECT json_agg(row_to_json(s_row)) FROM (
                   SELECT s.id, s.name FROM taguato.incident_services isv
                   JOIN taguato.services s ON s.id = isv.service_id
                   WHERE isv.incident_id = i.id
                   ORDER BY s.display_order
               ) s_row), '[]') as affected_services,
               COALESCE((SELECT json_agg(row_to_json(u_row)) FROM (
                   SELECT iu.id, iu.status, iu.message, iu.created_at,
                          ux.username as created_by_name
                   FROM taguato.incident_updates iu
                   LEFT JOIN taguato.users ux ON ux.id = iu.created_by
                   WHERE iu.incident_id = i.id
                   ORDER BY iu.created_at DESC
               ) u_row), '[]') as updates
        FROM taguato.incidents i
        LEFT JOIN taguato.users u ON u.id = i.created_by
    ]] .. where .. [[
        ORDER BY
            CASE WHEN i.status != 'resolved' THEN 0 ELSE 1 END,
            i.created_at DESC
        LIMIT $]] .. (idx - 1) .. " OFFSET $" .. idx

    local res = db.query(data_sql, unpack(vals))
    if not res then
        json.respond(500, { error = "Failed to list incidents" })
        return
    end

    for _, inc in ipairs(res) do
        decode_json_field(inc, "affected_services")
        decode_json_field(inc, "updates")
    end

    json.respond(200, {
        incidents = as_array(res),
        total = total,
        page = page,
        limit = limit,
        pages = math.ceil(total / limit),
    })
    return
end

-- Route: POST /admin/incidents - Create incident
if method == "POST" and uri == "/admin/incidents" then
    local body, err = json.read_body()
    if not body then
        json.respond(400, { error = "Invalid JSON body" })
        return
    end

    local title = body.title
    local severity = body.severity
    local status = body.status or "investigating"
    local message = body.message
    local service_ids = body.service_ids

    if not title or not severity then
        json.respond(400, { error = "title and severity are required" })
        return
    end

    local validate = require "validate"
    local sev_ok, sev_err = validate.validate_enum(severity, "severity", {"minor", "major", "critical"})
    if not sev_ok then
        json.respond(400, { error = sev_err })
        return
    end
    local st_ok, st_err = validate.validate_enum(status, "status", {"investigating", "identified", "monitoring", "resolved"})
    if not st_ok then
        json.respond(400, { error = st_err })
        return
    end

    if not message then
        json.respond(400, { error = "message is required (initial update)" })
        return
    end

    -- Insert incident
    local res, err = db.query(
        [[INSERT INTO taguato.incidents (title, severity, status, created_by)
          VALUES ($1, $2, $3, $4)
          RETURNING id, title, severity, status, created_at]],
        title, severity, status, user.id
    )
    if not res or #res == 0 then
        json.respond(500, { error = "Failed to create incident" })
        return
    end

    local incident = res[1]

    -- Create initial update
    db.query(
        [[INSERT INTO taguato.incident_updates (incident_id, status, message, created_by)
          VALUES ($1, $2, $3, $4)]],
        incident.id, status, message, user.id
    )

    -- Link affected services
    if service_ids and type(service_ids) == "table" then
        for _, sid in ipairs(service_ids) do
            db.query(
                "INSERT INTO taguato.incident_services (incident_id, service_id) VALUES ($1, $2) ON CONFLICT DO NOTHING",
                incident.id, sid
            )
        end
    end

    -- Audit log
    local audit = require "audit"
    audit.log(user.id, user.username, "incident_created", "incident", tostring(incident.id),
        { title = incident.title, severity = incident.severity }, ngx.var.remote_addr)

    json.respond(201, { incident = incident })
    return
end

-- Extract incident ID from URI: /admin/incidents/123 or /admin/incidents/123/updates
local incident_id = uri:match("^/admin/incidents/(%d+)")

-- Route: POST /admin/incidents/{id}/updates - Add update to timeline
local is_update_route = uri:match("^/admin/incidents/%d+/updates$")
if method == "POST" and incident_id and is_update_route then
    local body, err = json.read_body()
    if not body then
        json.respond(400, { error = "Invalid JSON body" })
        return
    end

    local status = body.status
    local message = body.message

    if not status or not message then
        json.respond(400, { error = "status and message are required" })
        return
    end

    local validate = require "validate"
    local st_ok, st_err = validate.validate_enum(status, "status", {"investigating", "identified", "monitoring", "resolved"})
    if not st_ok then
        json.respond(400, { error = st_err })
        return
    end

    -- Insert update
    local res, err = db.query(
        [[INSERT INTO taguato.incident_updates (incident_id, status, message, created_by)
          VALUES ($1, $2, $3, $4)
          RETURNING id, status, message, created_at]],
        incident_id, status, message, user.id
    )
    if not res or #res == 0 then
        json.respond(500, { error = "Failed to add update" })
        return
    end

    -- Update incident status and timestamp
    local update_sql = "UPDATE taguato.incidents SET status = $1, updated_at = NOW()"
    if status == "resolved" then
        update_sql = update_sql .. ", resolved_at = NOW()"
    end
    update_sql = update_sql .. " WHERE id = $2"
    db.query(update_sql, status, incident_id)

    json.respond(201, { update = res[1] })
    return
end

-- Route: PUT /admin/incidents/{id} - Update incident metadata
if method == "PUT" and incident_id and uri:match("^/admin/incidents/%d+$") then
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

    if body.severity then
        local validate = require "validate"
        local sev_ok, sev_err = validate.validate_enum(body.severity, "severity", {"minor", "major", "critical"})
        if not sev_ok then
            json.respond(400, { error = sev_err })
            return
        end
        idx = idx + 1
        sets[#sets + 1] = "severity = $" .. idx
        vals[idx] = body.severity
    end

    if body.service_ids and type(body.service_ids) == "table" then
        -- Update affected services: remove old, insert new
        db.query("DELETE FROM taguato.incident_services WHERE incident_id = $1", incident_id)
        for _, sid in ipairs(body.service_ids) do
            db.query(
                "INSERT INTO taguato.incident_services (incident_id, service_id) VALUES ($1, $2) ON CONFLICT DO NOTHING",
                incident_id, sid
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
        vals[idx] = incident_id

        local sql = "UPDATE taguato.incidents SET " .. table.concat(sets, ", ") ..
                    " WHERE id = $" .. idx ..
                    " RETURNING id, title, severity, status, updated_at"

        local res, err = db.query(sql, unpack(vals))
        if not res or #res == 0 then
            json.respond(404, { error = "Incident not found" })
            return
        end
        json.respond(200, { incident = res[1] })
        return
    end

    json.respond(200, { message = "Services updated" })
    return
end

-- Route: DELETE /admin/incidents/{id} - Delete incident (cascades)
if method == "DELETE" and incident_id and uri:match("^/admin/incidents/%d+$") then
    local res, err = db.query(
        "DELETE FROM taguato.incidents WHERE id = $1 RETURNING id, title",
        incident_id
    )
    if not res or #res == 0 then
        json.respond(404, { error = "Incident not found" })
        return
    end
    -- Audit log
    local audit = require "audit"
    audit.log(user.id, user.username, "incident_deleted", "incident", incident_id,
        { title = res[1].title }, ngx.var.remote_addr)

    json.respond(200, { deleted = res[1] })
    return
end

-- No route matched
json.respond(404, { error = "Not found" })
