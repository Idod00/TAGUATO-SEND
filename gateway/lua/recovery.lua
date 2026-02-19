-- Password recovery module
-- POST /api/auth/forgot-password  - Request a reset code
-- POST /api/auth/verify-reset-code - Verify code, get reset_token
-- POST /api/auth/reset-password   - Reset password with reset_token

local _M = {}

-- Rate limit helper: max N requests per key per window (seconds) using Redis
-- Uses atomic Lua script to avoid race conditions between get+incr
local function check_rate_limit(key, max_requests, window_seconds)
    local db = require "init"
    local red, err = db.get_redis(2000)
    if not red then
        ngx.log(ngx.WARN, "recovery rate limit: Redis unavailable: ", err)
        return true
    end

    local redis_key = "recovery_rl:" .. key
    local script = [[
        local current = redis.call('incr', KEYS[1])
        if current == 1 then
            redis.call('expire', KEYS[1], ARGV[1])
        end
        return current
    ]]
    local current, eval_err = red:eval(script, 1, redis_key, window_seconds)
    if not current then
        ngx.log(ngx.WARN, "recovery rate limit: Redis eval failed: ", eval_err)
        red:set_keepalive(10000, 10)
        return true
    end

    red:set_keepalive(10000, 10)
    return current <= max_requests
end

-- Send recovery code via WhatsApp using the admin's designated instance
local function send_whatsapp(phone_number, code)
    local instance = os.getenv("RECOVERY_ADMIN_INSTANCE")
    if not instance or instance == "" then
        return nil, "RECOVERY_ADMIN_INSTANCE not configured"
    end

    local api_key = os.getenv("AUTHENTICATION_API_KEY")
    if not api_key then
        return nil, "Internal API key not configured"
    end

    local http = require "resty.http"
    local cjson = require "cjson"
    local httpc = http.new()
    httpc:set_timeout(5000)

    -- Check if the admin instance is connected
    local state_res, state_err = httpc:request_uri(
        "http://taguato-api:8080/instance/connectionState/" .. instance,
        {
            method = "GET",
            headers = { ["apikey"] = api_key },
        }
    )

    if not state_res or state_res.status ~= 200 then
        return nil, "Failed to check instance state"
    end

    local state_ok, state_data = pcall(cjson.decode, state_res.body)
    if not state_ok then
        return nil, "Invalid instance state response"
    end

    local state = state_data and state_data.instance and state_data.instance.state
    if state ~= "open" then
        return nil, "Admin WhatsApp instance is not connected"
    end

    local msg_body = cjson.encode({
        number = phone_number,
        text = "Your password recovery code is: *" .. code .. "*\n\nThis code expires in 15 minutes. If you did not request this, ignore this message.",
    })

    local send_res, send_err = httpc:request_uri(
        "http://taguato-api:8080/message/sendText/" .. instance,
        {
            method = "POST",
            headers = {
                ["apikey"] = api_key,
                ["Content-Type"] = "application/json",
            },
            body = msg_body,
        }
    )

    if not send_res or send_res.status >= 400 then
        return nil, "Failed to send WhatsApp message: " .. (send_err or ("status " .. (send_res and send_res.status or "?")))
    end

    return true
end

function _M.handle()
    local db = require "init"
    local json = require "json"
    local validate = require "validate"

    local method = ngx.req.get_method()
    local uri = ngx.var.uri

    -- =============================================
    -- POST /api/auth/forgot-password
    -- =============================================
    if method == "POST" and uri == "/api/auth/forgot-password" then
        local body, err = json.read_body()
        if not body then
            json.respond(400, { error = "Invalid JSON body" })
            return
        end

        local identifier = body.username or body.email
        if not identifier or identifier == "" then
            json.respond(400, { error = "username or email is required" })
            return
        end

        -- Rate limit by IP: 3 requests per hour
        local ip = ngx.var.remote_addr or "unknown"
        if not check_rate_limit("ip:" .. ip, 3, 3600) then
            json.respond(200, { message = "If the account exists, a recovery code has been sent." })
            return
        end

        -- Look up user by username or email
        local user_res = db.query(
            [[SELECT id, username, email, phone_number
              FROM taguato.users
              WHERE (username = $1 OR email = $1) AND is_active = true
              LIMIT 1]],
            identifier
        )

        -- Anti-enumeration: always return the same success response
        if not user_res or #user_res == 0 then
            json.respond(200, { message = "If the account exists, a recovery code has been sent." })
            return
        end

        local found_user = user_res[1]

        -- Rate limit by user: 3 requests per hour
        if not check_rate_limit("user:" .. found_user.id, 3, 3600) then
            json.respond(200, { message = "If the account exists, a recovery code has been sent." })
            return
        end

        -- Determine delivery method
        local smtp = require "smtp"
        local delivery_method
        if found_user.email and found_user.email ~= "" and smtp.is_configured() then
            delivery_method = "email"
        elseif found_user.phone_number and found_user.phone_number ~= "" then
            delivery_method = "whatsapp"
        else
            ngx.log(ngx.WARN, "password recovery: no delivery method for user ", found_user.id)
            json.respond(200, { message = "If the account exists, a recovery code has been sent." })
            return
        end

        -- Invalidate previous unused codes for this user
        db.query(
            [[UPDATE taguato.password_resets
              SET used_at = NOW()
              WHERE user_id = $1 AND used_at IS NULL]],
            found_user.id
        )

        -- Generate 6-digit code
        local code_res = db.query(
            "SELECT LPAD(FLOOR(RANDOM()*1000000)::int::text, 6, '0') as code"
        )
        local code = code_res and code_res[1] and code_res[1].code
        if not code then
            ngx.log(ngx.ERR, "password recovery: failed to generate code")
            json.respond(200, { message = "If the account exists, a recovery code has been sent." })
            return
        end

        -- Store the reset record
        local insert_res = db.query(
            [[INSERT INTO taguato.password_resets (user_id, reset_code, method)
              VALUES ($1, $2, $3)
              RETURNING id]],
            found_user.id, code, delivery_method
        )

        if not insert_res or #insert_res == 0 then
            ngx.log(ngx.ERR, "password recovery: failed to insert reset record")
            json.respond(200, { message = "If the account exists, a recovery code has been sent." })
            return
        end

        -- Send the code
        local send_ok, send_err
        if delivery_method == "email" then
            local email_templates = require "email_templates"
            local subject, text, html = email_templates.recovery_code(code)
            send_ok, send_err = smtp.send(found_user.email, subject, text, html)
        else
            send_ok, send_err = send_whatsapp(found_user.phone_number, code)
        end

        if not send_ok then
            ngx.log(ngx.ERR, "password recovery: failed to send code via ", delivery_method, ": ", send_err)
        end

        -- Audit log
        local audit = require "audit"
        pcall(audit.log, found_user.id, found_user.username, "password_reset_requested", "user", tostring(found_user.id),
            { method = delivery_method }, ip)

        json.respond(200, { message = "If the account exists, a recovery code has been sent." })
        return
    end

    -- =============================================
    -- POST /api/auth/verify-reset-code
    -- =============================================
    if method == "POST" and uri == "/api/auth/verify-reset-code" then
        local body, err = json.read_body()
        if not body then
            json.respond(400, { error = "Invalid JSON body" })
            return
        end

        local identifier = body.username or body.email
        local code = body.code

        if not identifier or identifier == "" then
            json.respond(400, { error = "username or email is required" })
            return
        end
        if not code or code == "" then
            json.respond(400, { error = "code is required" })
            return
        end

        -- Find the user
        local user_res = db.query(
            [[SELECT id FROM taguato.users
              WHERE (username = $1 OR email = $1) AND is_active = true
              LIMIT 1]],
            identifier
        )

        if not user_res or #user_res == 0 then
            json.respond(400, { error = "Invalid code or expired" })
            return
        end

        local found_user = user_res[1]

        -- Find the active reset record
        local reset_res = db.query(
            [[SELECT id, reset_code, attempts
              FROM taguato.password_resets
              WHERE user_id = $1
                AND used_at IS NULL
                AND expires_at > NOW()
              ORDER BY created_at DESC
              LIMIT 1]],
            found_user.id
        )

        if not reset_res or #reset_res == 0 then
            json.respond(400, { error = "Invalid code or expired" })
            return
        end

        local reset = reset_res[1]

        -- Check max attempts
        if (reset.attempts or 0) >= 5 then
            db.query("UPDATE taguato.password_resets SET used_at = NOW() WHERE id = $1", reset.id)
            json.respond(400, { error = "Too many attempts. Please request a new code." })
            return
        end

        -- Increment attempts
        db.query(
            "UPDATE taguato.password_resets SET attempts = attempts + 1 WHERE id = $1",
            reset.id
        )

        -- Check the code
        if reset.reset_code ~= code then
            json.respond(400, { error = "Invalid code or expired" })
            return
        end

        -- Code is valid - generate a reset_token
        local token_res = db.query("SELECT encode(gen_random_bytes(32), 'hex') as token")
        if not token_res or #token_res == 0 then
            json.respond(500, { error = "Failed to generate reset token" })
            return
        end

        local reset_token = token_res[1].token

        -- Store the token (extends expiry by 10 minutes for the reset step)
        db.query(
            [[UPDATE taguato.password_resets
              SET reset_token = $1, expires_at = NOW() + INTERVAL '10 minutes'
              WHERE id = $2]],
            reset_token, reset.id
        )

        json.respond(200, { reset_token = reset_token })
        return
    end

    -- =============================================
    -- POST /api/auth/reset-password
    -- =============================================
    if method == "POST" and uri == "/api/auth/reset-password" then
        local body, err = json.read_body()
        if not body then
            json.respond(400, { error = "Invalid JSON body" })
            return
        end

        local reset_token = body.reset_token
        local new_password = body.new_password

        if not reset_token or reset_token == "" then
            json.respond(400, { error = "reset_token is required" })
            return
        end
        if not new_password or new_password == "" then
            json.respond(400, { error = "new_password is required" })
            return
        end

        local pw_ok, pw_err = validate.validate_password(new_password)
        if not pw_ok then
            json.respond(400, { error = pw_err })
            return
        end

        -- Find the valid reset record by token
        local reset_res = db.query(
            [[SELECT pr.id, pr.user_id, u.username
              FROM taguato.password_resets pr
              JOIN taguato.users u ON u.id = pr.user_id
              WHERE pr.reset_token = $1
                AND pr.used_at IS NULL
                AND pr.expires_at > NOW()
              LIMIT 1]],
            reset_token
        )

        if not reset_res or #reset_res == 0 then
            json.respond(400, { error = "Invalid or expired reset token" })
            return
        end

        local reset = reset_res[1]

        -- Update the password
        db.begin()

        local upd_res, upd_err = db.query(
            [[UPDATE taguato.users
              SET password_hash = crypt($1, gen_salt('bf')),
                  must_change_password = false,
                  failed_login_attempts = 0,
                  locked_until = NULL,
                  updated_at = NOW()
              WHERE id = $2]],
            new_password, reset.user_id
        )

        if not upd_res then
            db.rollback()
            json.respond(500, { error = "Failed to update password" })
            return
        end

        -- Mark reset as used
        db.query("UPDATE taguato.password_resets SET used_at = NOW() WHERE id = $1", reset.id)

        -- Invalidate all active sessions for this user
        db.query("UPDATE taguato.sessions SET is_active = false WHERE user_id = $1", reset.user_id)

        -- Audit log
        local audit = require "audit"
        pcall(audit.log, reset.user_id, reset.username, "password_reset_completed", "user",
            tostring(reset.user_id), nil, ngx.var.remote_addr)

        db.commit()

        -- Flush auth cache
        local cache = ngx.shared.auth_cache
        if cache then
            cache:flush_all()
        end

        json.respond(200, { message = "Password has been reset successfully. Please login with your new password." })
        return
    end

    local json = require "json"
    json.respond(404, { error = "Not found" })
end

return _M
