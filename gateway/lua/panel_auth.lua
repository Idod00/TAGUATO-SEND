-- Panel authentication endpoints
-- POST /api/auth/login - Validate credentials, return token
-- GET /api/auth/me - Return current user profile
-- POST /api/auth/change-password - Change password (clears must_change_password flag)

local db = require "init"
local json = require "json"
local validate = require "validate"

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

    -- Check if account is locked (brute-force protection)
    local lock_res = db.query(
        [[SELECT id, failed_login_attempts, locked_until
          FROM taguato.users WHERE username = $1 AND is_active = true LIMIT 1]],
        username
    )
    if lock_res and #lock_res > 0 then
        local lu = lock_res[1].locked_until
        if lu then
            -- Check if lock is still active
            local still_locked = db.query(
                "SELECT ($1::timestamp > NOW()) as locked", lu
            )
            if still_locked and #still_locked > 0 and still_locked[1].locked then
                json.respond(429, { error = "Account temporarily locked. Try again in 15 minutes." })
                return
            end
        end
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
        -- Increment failed attempts and possibly lock
        if lock_res and #lock_res > 0 then
            db.query(
                [[UPDATE taguato.users
                  SET failed_login_attempts = failed_login_attempts + 1,
                      locked_until = CASE WHEN failed_login_attempts + 1 >= 5
                                          THEN NOW() + INTERVAL '15 minutes'
                                          ELSE locked_until END
                  WHERE id = $1]],
                lock_res[1].id
            )
        end
        json.respond(401, { error = "Invalid username or password" })
        return
    end

    -- Reset failed attempts on successful login
    db.query(
        "UPDATE taguato.users SET failed_login_attempts = 0, locked_until = NULL WHERE id = $1",
        res[1].id
    )

    local user = res[1]

    -- Audit log
    local audit = require "audit"
    audit.log(user.id, user.username, "user_login", "session", nil, nil, ngx.var.remote_addr)

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

    local pw_ok, pw_err = validate.validate_password(new_password)
    if not pw_ok then
        json.respond(400, { error = pw_err })
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
