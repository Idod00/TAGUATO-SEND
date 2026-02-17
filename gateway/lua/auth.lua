-- Authentication middleware
-- Reads apikey header, validates against taguato.users table,
-- sets ngx.ctx.user with user info for downstream handlers.
-- Enforces per-user rate limiting via lua_shared_dict.
-- Uses auth_cache shared dict to reduce DB queries (10s TTL).

local db = require "init"
local json = require "json"
local cjson = require "cjson"

local token = ngx.req.get_headers()["apikey"]

if not token or token == "" then
    json.respond(401, { error = "Missing apikey header" })
    return
end

-- Check auth cache first
local cache = ngx.shared.auth_cache
local cached, user

if cache then
    local cached_json = cache:get("auth:" .. token)
    if cached_json then
        local ok, data = pcall(cjson.decode, cached_json)
        if ok and data then
            cached = true
            user = data
        end
    end
end

if not cached then
    local res, err = db.query(
        "SELECT id, username, role, max_instances, is_active, rate_limit FROM taguato.users WHERE api_token = $1 LIMIT 1",
        token
    )

    if not res or #res == 0 then
        json.respond(401, { error = "Invalid API token" })
        return
    end

    user = res[1]

    -- Cache the result for 10 seconds
    if cache then
        cache:set("auth:" .. token, cjson.encode(user), 10)
    end
end

if not user.is_active then
    json.respond(403, { error = "Account is disabled" })
    return
end

-- Per-user rate limiting (skip for admins)
local user_rate_limit = user.rate_limit and tonumber(user.rate_limit) or nil
if user_rate_limit and user_rate_limit > 0 and user.role ~= "admin" then
    local rate_store = ngx.shared.rate_limit_store
    if rate_store then
        local key = "rl:" .. user.id
        local current, flags = rate_store:get(key)
        if current then
            if current >= user_rate_limit then
                ngx.header["Retry-After"] = "60"
                json.respond(429, {
                    error = "Rate limit exceeded",
                    limit = user_rate_limit,
                    window = "60s",
                })
                return
            end
            rate_store:incr(key, 1)
        else
            -- New window: set counter with 60-second expiry
            rate_store:set(key, 1, 60)
        end
    end
end

-- Store user context for downstream handlers
ngx.ctx.user = {
    id = user.id,
    username = user.username,
    role = user.role,
    max_instances = user.max_instances,
    rate_limit = user_rate_limit,
}
