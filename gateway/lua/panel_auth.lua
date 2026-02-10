-- Panel authentication endpoints
-- POST /api/auth/login - Validate credentials, return token
-- GET /api/auth/me - Return current user profile
-- POST /api/auth/change-password - Change password (clears must_change_password flag)

local db = require "init"
local json = require "json"

local method = ngx.req.get_method()
local uri = ngx.var.uri

-- POST /api/auth/login
if method == "POST" and uri == "/api/auth/login" then
    local body, err = json.read_body()
    if not body then
        json.respond(400, { error = "Invalid JSON body" })
        return
    end

    local username = body.username
    local password = body.password

    if not username or not password then
        json.respond(400, { error = "username and password are required" })
        return
    end

    local res, err = db.query(
        [[SELECT id, username, role, api_token, max_instances, must_change_password
          FROM taguato.users
          WHERE username = $1
            AND password_hash = crypt($2, password_hash)
            AND is_active = true
          LIMIT 1]],
        username, password
    )

    if not res or #res == 0 then
        json.respond(401, { error = "Invalid username or password" })
        return
    end

    local user = res[1]

    -- Create session record
    local ip = ngx.var.remote_addr or "unknown"
    local ua = ngx.req.get_headers()["User-Agent"] or "unknown"
    local token_hash = ngx.md5(user.api_token)
    db.query(
        [[INSERT INTO taguato.sessions (user_id, token_hash, ip_address, user_agent)
          VALUES ($1, $2, $3, $4)]],
        user.id, token_hash, ip, ua
    )

    json.respond(200, {
        token = user.api_token,
        user = {
            id = user.id,
            username = user.username,
            role = user.role,
            max_instances = user.max_instances,
            must_change_password = user.must_change_password,
        }
    })
    return
end

-- GET /api/auth/me
if method == "GET" and uri == "/api/auth/me" then
    local token = ngx.req.get_headers()["apikey"]
    if not token or token == "" then
        json.respond(401, { error = "Missing apikey header" })
        return
    end

    local res, err = db.query(
        [[SELECT u.id, u.username, u.role, u.max_instances, u.is_active, u.must_change_password, u.created_at
          FROM taguato.users u
          WHERE u.api_token = $1
          LIMIT 1]],
        token
    )

    if not res or #res == 0 then
        json.respond(401, { error = "Invalid API token" })
        return
    end

    local user = res[1]
    if not user.is_active then
        json.respond(403, { error = "Account is disabled" })
        return
    end

    -- Fetch user instances
    local instances, _ = db.query(
        "SELECT instance_name, created_at FROM taguato.user_instances WHERE user_id = $1 ORDER BY created_at",
        user.id
    )

    json.respond(200, {
        user = {
            id = user.id,
            username = user.username,
            role = user.role,
            max_instances = user.max_instances,
            must_change_password = user.must_change_password,
            created_at = user.created_at,
            instances = instances or {},
        }
    })
    return
end

-- POST /api/auth/change-password
if method == "POST" and uri == "/api/auth/change-password" then
    local token = ngx.req.get_headers()["apikey"]
    if not token or token == "" then
        json.respond(401, { error = "Missing apikey header" })
        return
    end

    local body, err = json.read_body()
    if not body then
        json.respond(400, { error = "Invalid JSON body" })
        return
    end

    local current_password = body.current_password
    local new_password = body.new_password

    if not current_password or not new_password then
        json.respond(400, { error = "current_password and new_password are required" })
        return
    end

    if #new_password < 6 then
        json.respond(400, { error = "New password must be at least 6 characters" })
        return
    end

    -- Verify current password
    local res, err = db.query(
        [[SELECT id FROM taguato.users
          WHERE api_token = $1
            AND password_hash = crypt($2, password_hash)
            AND is_active = true
          LIMIT 1]],
        token, current_password
    )

    if not res or #res == 0 then
        json.respond(401, { error = "Current password is incorrect" })
        return
    end

    local user_id = res[1].id

    -- Update password and clear the flag
    local upd, err = db.query(
        [[UPDATE taguato.users
          SET password_hash = crypt($1, gen_salt('bf')),
              must_change_password = false,
              updated_at = NOW()
          WHERE id = $2]],
        new_password, user_id
    )

    if not upd then
        json.respond(500, { error = "Failed to update password" })
        return
    end

    json.respond(200, { message = "Password changed successfully" })
    return
end

json.respond(404, { error = "Not found" })
