-- Admin CRUD endpoints for incident management
-- All endpoints require role=admin (enforced by auth.lua in nginx location)

local db = require "init"
local json = require "json"

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
    json.respond(200, { services = res })
    return
end

-- Route: GET /admin/incidents - List all incidents
if method == "GET" and uri == "/admin/incidents" then
    local res, err = db.query([[
        SELECT i.id, i.title, i.severity, i.status, i.created_at, i.updated_at, i.resolved_at,
               u.username as created_by_name
        FROM taguato.incidents i
        LEFT JOIN taguato.users u ON u.id = i.created_by
        ORDER BY
            CASE WHEN i.status != 'resolved' THEN 0 ELSE 1 END,
            i.created_at DESC
    ]])
    if not res then
        json.respond(500, { error = "Failed to list incidents" })
        return
    end

    -- Enrich with affected services and updates
    for _, inc in ipairs(res) do
        local svc_res = db.query([[
            SELECT s.id, s.name FROM taguato.incident_services isv
            JOIN taguato.services s ON s.id = isv.service_id
            WHERE isv.incident_id = $1
            ORDER BY s.display_order
        ]], inc.id)
        inc.affected_services = svc_res or {}

        local upd_res = db.query([[
            SELECT iu.id, iu.status, iu.message, iu.created_at,
                   u.username as created_by_name
            FROM taguato.incident_updates iu
            LEFT JOIN taguato.users u ON u.id = iu.created_by
            WHERE iu.incident_id = $1
            ORDER BY iu.created_at DESC
        ]], inc.id)
        inc.updates = upd_res or {}
    end

    json.respond(200, { incidents = res })
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
        json.respond(500, { error = "Failed to create incident: " .. (err or "unknown") })
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

    -- Insert update
    local res, err = db.query(
        [[INSERT INTO taguato.incident_updates (incident_id, status, message, created_by)
          VALUES ($1, $2, $3, $4)
          RETURNING id, status, message, created_at]],
        incident_id, status, message, user.id
    )
    if not res or #res == 0 then
        json.respond(500, { error = "Failed to add update: " .. (err or "unknown") })
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
    json.respond(200, { deleted = res[1] })
    return
end

-- No route matched
json.respond(404, { error = "Not found" })
