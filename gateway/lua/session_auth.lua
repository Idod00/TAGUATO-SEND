-- Shared session-based authentication module
-- Validates ephemeral session tokens (not permanent api_token).
-- Used by access.lua, auth.lua, panel_auth.lua, and nginx.conf inline blocks.

local db = require "init"
local cjson = require "cjson"

local _M = {}

local function sha256_hex(input)
    local sha256 = require "resty.sha256"
    local str = require "resty.string"
    local sha = sha256:new()
    sha:update(input)
    return str.to_hex(sha:final())
end

_M.sha256_hex = sha256_hex

-- validate(token) -> user_data or nil, error
-- Hashes the raw token, looks up active session joined with users,
-- caches result in ngx.shared.auth_cache for 10s.
function _M.validate(token)
    if not token or token == "" then
        return nil, "missing token"
    end

    local token_hash = sha256_hex(token)
    local cache_key = "sess:" .. token_hash

    -- Check cache first
    local cache = ngx.shared.auth_cache
    if cache then
        local cached_json = cache:get(cache_key)
        if cached_json then
            local ok, data = pcall(cjson.decode, cached_json)
            if ok and data then
                return data
            end
        end
    end

    -- DB lookup: session JOIN users
    local res, err = db.query(
        [[SELECT u.id, u.username, u.role, u.max_instances, u.is_active,
                 u.rate_limit, u.must_change_password, u.email, u.phone_number,
                 u.created_at,
                 s.id AS session_id, s.expires_at
          FROM taguato.sessions s
          JOIN taguato.users u ON u.id = s.user_id
          WHERE s.token_hash = $1
            AND s.is_active = true
            AND s.expires_at > NOW()
          ORDER BY s.created_at DESC
          LIMIT 1]],
        token_hash
    )

    if not res or #res == 0 then
        return nil, "invalid or expired session"
    end

    local row = res[1]
    local user = {
        id = row.id,
        username = row.username,
        role = row.role,
        max_instances = row.max_instances,
        is_active = row.is_active,
        rate_limit = row.rate_limit,
        must_change_password = row.must_change_password,
        email = row.email,
        phone_number = row.phone_number,
        created_at = row.created_at,
        session_id = row.session_id,
        token_hash = token_hash,
    }

    -- Cache for 10 seconds
    if cache then
        cache:set(cache_key, cjson.encode(user), 10)
    end

    return user
end

-- touch(session_id) -> extends expires_at by 24h (sliding window)
function _M.touch(session_id)
    if not session_id then return end
    db.query(
        [[UPDATE taguato.sessions
          SET last_active = NOW(), expires_at = NOW() + INTERVAL '24 hours'
          WHERE id = $1]],
        session_id
    )
end

-- invalidate_by_hash(token_hash) -> deactivate session with this hash
function _M.invalidate_by_hash(token_hash)
    if not token_hash then return end
    db.query(
        "UPDATE taguato.sessions SET is_active = false WHERE token_hash = $1 AND is_active = true",
        token_hash
    )
    -- Clear from cache
    local cache = ngx.shared.auth_cache
    if cache then
        cache:delete("sess:" .. token_hash)
    end
end

-- invalidate_user(user_id) -> deactivate all sessions for a user
function _M.invalidate_user(user_id)
    if not user_id then return end
    db.query(
        "UPDATE taguato.sessions SET is_active = false WHERE user_id = $1 AND is_active = true",
        user_id
    )
    -- Flush cache (can't know which cache keys belong to this user)
    local cache = ngx.shared.auth_cache
    if cache then
        cache:flush_all()
    end
end

return _M
