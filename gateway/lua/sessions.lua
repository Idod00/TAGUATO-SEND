-- CRUD endpoints for user sessions
-- GET /api/sessions - List own sessions
-- DELETE /api/sessions/{id} - Revoke a session
-- Admin: GET /admin/sessions - List all sessions
-- Admin: DELETE /admin/sessions/{id} - Revoke any session

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

-- Admin routes
local admin_session_id = uri:match("^/admin/sessions/(%d+)$")

if uri:match("^/admin/sessions") then
    if user.role ~= "admin" then
        json.respond(403, { error = "Admin access required" })
        return
    end

    -- GET /admin/sessions - List all active sessions (paginated)
    if method == "GET" and uri == "/admin/sessions" then
        local args = ngx.req.get_uri_args()
        local page = tonumber(args.page) or 1
        local limit = tonumber(args.limit) or 50
        if limit > 100 then limit = 100 end
        local offset = (page - 1) * limit

        -- Count total
        local count_res = db.query(
            "SELECT COUNT(*) as total FROM taguato.sessions WHERE is_active = true"
        )
        local total = 0
        if count_res and #count_res > 0 then
            total = tonumber(count_res[1].total) or 0
        end

        -- Fetch page
        local res, err = db.query([[
            SELECT s.id, s.user_id, u.username, s.ip_address, s.user_agent,
                   s.last_active, s.is_active, s.created_at
            FROM taguato.sessions s
            JOIN taguato.users u ON u.id = s.user_id
            WHERE s.is_active = true
            ORDER BY s.last_active DESC
            LIMIT $1 OFFSET $2
        ]], limit, offset)
        if not res then
            json.respond(500, { error = "Failed to list sessions" })
            return
        end

        json.respond(200, {
            sessions = as_array(res),
            total = total,
            page = page,
            limit = limit,
            pages = math.ceil(total / limit),
        })
        return
    end

    -- DELETE /admin/sessions/{id} - Revoke any session
    if method == "DELETE" and admin_session_id then
        local res, err = db.query(
            "UPDATE taguato.sessions SET is_active = false WHERE id = $1 RETURNING id, user_id",
            admin_session_id
        )
        if not res or #res == 0 then
            json.respond(404, { error = "Session not found" })
            return
        end
        json.respond(200, { revoked = res[1] })
        return
    end

    json.respond(404, { error = "Not found" })
    return
end

-- User routes
local session_id = uri:match("^/api/sessions/(%d+)$")

-- GET /api/sessions - List own sessions
if method == "GET" and uri == "/api/sessions" then
    local res, err = db.query([[
        SELECT id, ip_address, user_agent, last_active, is_active, created_at
        FROM taguato.sessions
        WHERE user_id = $1 AND is_active = true
        ORDER BY last_active DESC
    ]], user.id)
    if not res then
        json.respond(500, { error = "Failed to list sessions" })
        return
    end
    json.respond(200, { sessions = as_array(res) })
    return
end

-- DELETE /api/sessions/{id} - Revoke own session
if method == "DELETE" and session_id then
    local res, err = db.query(
        "UPDATE taguato.sessions SET is_active = false WHERE id = $1 AND user_id = $2 RETURNING id",
        session_id, user.id
    )
    if not res or #res == 0 then
        json.respond(404, { error = "Session not found" })
        return
    end
    json.respond(200, { revoked = { id = tonumber(session_id) } })
    return
end

json.respond(404, { error = "Not found" })
