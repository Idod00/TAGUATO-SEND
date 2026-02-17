-- Admin CRUD endpoints for user management
-- All endpoints require role=admin (enforced by nginx location config)

local db = require "init"
local json = require "json"
local validate = require "validate"

-- Verify admin role
local user = ngx.ctx.user
if not user or user.role ~= "admin" then
    json.respond(403, { error = "Admin access required" })
    return
end

local method = ngx.req.get_method()
local uri = ngx.var.uri

-- Extract user ID from URI: /admin/users/123
local user_id = uri:match("^/admin/users/(%d+)$")

-- Generate a random token via PostgreSQL pgcrypto
local function generate_token()
    local res = db.query("SELECT encode(gen_random_bytes(32), 'hex') as token")
    if res and #res > 0 then
        return res[1].token
    end
    -- Fallback: use ngx random (less secure but functional)
    local t = {}
    for i = 1, 64 do
        t[i] = string.format("%x", math.random(0, 15))
    end
    return table.concat(t)
end

-- Invalidate auth cache after user modifications
local function invalidate_auth_cache()
    local cache = ngx.shared.auth_cache
    if cache then
        cache:flush_all()
    end
end

-- POST /admin/users - Create user
if method == "POST" and uri == "/admin/users" then
    local body, err = json.read_body()
    if not body then
        json.respond(400, { error = "Invalid JSON body" })
        return
    end

    local username = body.username
    local password = body.password
    local max_instances = body.max_instances or 1
    local role = body.role or "user"

    if not username or not password then
        json.respond(400, { error = "username and password are required" })
        return
    end

    local uname_ok, uname_err = validate.validate_username(username)
    if not uname_ok then
        json.respond(400, { error = uname_err })
        return
    end

    local pw_ok, pw_err = validate.validate_password(password)
    if not pw_ok then
        json.respond(400, { error = pw_err })
        return
    end

    if role ~= "user" and role ~= "admin" then
        json.respond(400, { error = "role must be 'user' or 'admin'" })
        return
    end

    if max_instances ~= nil then
        local mi_ok, mi_err = validate.validate_positive_int(max_instances, "max_instances")
        if not mi_ok then
            json.respond(400, { error = mi_err })
            return
        end
    end

    local rate_limit_val = body.rate_limit

    -- Generate token
    local token = generate_token()

    -- Use transaction: INSERT user + audit log
    db.begin()

    local res, ins_err = db.query(
        [[INSERT INTO taguato.users (username, password_hash, role, api_token, max_instances, rate_limit)
          VALUES ($1, crypt($2, gen_salt('bf')), $3, $4, $5, $6)
          RETURNING id, username, role, api_token, max_instances, is_active, must_change_password, rate_limit, created_at]],
        username, password, role, token, max_instances, rate_limit_val
    )

    if not res then
        db.rollback()
        if ins_err and ins_err:find("duplicate key") then
            json.respond(409, { error = "Username already exists" })
        else
            json.respond(500, { error = "Failed to create user: " .. (ins_err or "unknown") })
        end
        return
    end

    -- Audit log (best-effort within transaction)
    local audit = require "audit"
    local audit_ok = pcall(audit.log, user.id, user.username, "user_created", "user", tostring(res[1].id),
        { username = res[1].username, role = res[1].role }, ngx.var.remote_addr)

    if audit_ok then
        db.commit()
    else
        -- Audit failed, but don't block the operation - commit user creation
        db.commit()
        ngx.log(ngx.WARN, "audit log failed for user_created, but user was created")
    end

    invalidate_auth_cache()
    json.respond(201, { user = res[1] })
    return
end

-- GET /admin/users - List users
if method == "GET" and uri == "/admin/users" then
    local res, err = db.query(
        "SELECT id, username, role, api_token, max_instances, is_active, must_change_password, rate_limit, created_at, updated_at FROM taguato.users ORDER BY id"
    )

    if not res then
        json.respond(500, { error = "Failed to list users" })
        return
    end

    json.respond(200, { users = res })
    return
end

-- GET /admin/users/{id} - Get user with instances
if method == "GET" and user_id then
    local res, err = db.query(
        "SELECT id, username, role, api_token, max_instances, is_active, must_change_password, rate_limit, created_at, updated_at FROM taguato.users WHERE id = $1",
        user_id
    )

    if not res or #res == 0 then
        json.respond(404, { error = "User not found" })
        return
    end

    local found_user = res[1]

    -- Fetch instances
    local instances, err = db.query(
        "SELECT instance_name, created_at FROM taguato.user_instances WHERE user_id = $1 ORDER BY created_at",
        user_id
    )

    found_user.instances = instances or {}
    json.respond(200, { user = found_user })
    return
end

-- PUT /admin/users/{id} - Update user
if method == "PUT" and user_id then
    local body, err = json.read_body()
    if not body then
        json.respond(400, { error = "Invalid JSON body" })
        return
    end

    -- Build SET clause dynamically
    local sets = {}
    local vals = {}
    local idx = 0

    if body.max_instances ~= nil then
        idx = idx + 1
        sets[#sets + 1] = "max_instances = $" .. idx
        vals[idx] = body.max_instances
    end

    if body.is_active ~= nil then
        idx = idx + 1
        sets[#sets + 1] = "is_active = $" .. idx
        vals[idx] = body.is_active
    end

    if body.role ~= nil then
        if body.role ~= "user" and body.role ~= "admin" then
            json.respond(400, { error = "role must be 'user' or 'admin'" })
            return
        end
        idx = idx + 1
        sets[#sets + 1] = "role = $" .. idx
        vals[idx] = body.role
    end

    if body.rate_limit ~= nil then
        idx = idx + 1
        sets[#sets + 1] = "rate_limit = $" .. idx
        vals[idx] = body.rate_limit
    end

    if body.password ~= nil then
        local pw_ok, pw_err = validate.validate_password(body.password)
        if not pw_ok then
            json.respond(400, { error = pw_err })
            return
        end
        idx = idx + 1
        sets[#sets + 1] = "password_hash = crypt($" .. idx .. ", gen_salt('bf'))"
        vals[idx] = body.password
        -- Force password change on next login
        sets[#sets + 1] = "must_change_password = true"
    end

    if body.regenerate_token then
        local new_token = generate_token()
        idx = idx + 1
        sets[#sets + 1] = "api_token = $" .. idx
        vals[idx] = new_token
    end

    if #sets == 0 then
        json.respond(400, { error = "No fields to update" })
        return
    end

    -- Add updated_at
    sets[#sets + 1] = "updated_at = NOW()"

    -- Add WHERE clause
    idx = idx + 1
    vals[idx] = user_id

    local sql = "UPDATE taguato.users SET " .. table.concat(sets, ", ") ..
                " WHERE id = $" .. idx ..
                " RETURNING id, username, role, api_token, max_instances, is_active, must_change_password, rate_limit, updated_at"

    -- Use transaction: UPDATE user + audit log
    db.begin()

    local res, upd_err = db.query(sql, unpack(vals))

    if not res or #res == 0 then
        db.rollback()
        json.respond(404, { error = "User not found" })
        return
    end

    -- Audit log (best-effort)
    local audit = require "audit"
    pcall(audit.log, user.id, user.username, "user_updated", "user", user_id, body, ngx.var.remote_addr)

    db.commit()
    invalidate_auth_cache()
    json.respond(200, { user = res[1] })
    return
end

-- DELETE /admin/users/{id} - Delete user
if method == "DELETE" and user_id then
    -- Prevent deleting yourself
    if tonumber(user_id) == user.id then
        json.respond(400, { error = "Cannot delete your own account" })
        return
    end

    -- Use transaction: DELETE user + audit log
    db.begin()

    local res, del_err = db.query(
        "DELETE FROM taguato.users WHERE id = $1 RETURNING id, username",
        user_id
    )

    if not res or #res == 0 then
        db.rollback()
        json.respond(404, { error = "User not found" })
        return
    end

    -- Audit log (best-effort)
    local audit = require "audit"
    pcall(audit.log, user.id, user.username, "user_deleted", "user", user_id,
        { username = res[1].username }, ngx.var.remote_addr)

    db.commit()
    invalidate_auth_cache()
    json.respond(200, { deleted = res[1] })
    return
end

-- If we got here, no route matched
json.respond(404, { error = "Not found" })
