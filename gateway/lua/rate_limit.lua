-- Per-user rate limiting using Redis sliding window
-- Called from access.lua after authentication
-- Falls back to lua_shared_dict when Redis is unavailable.
-- Set RATE_LIMIT_FAIL_MODE=closed to reject requests when both Redis and shared dict fail.

local _M = {}

function _M.check(user_id, limit)
    if not limit or limit <= 0 then
        return true -- no limit configured
    end

    local redis = require "resty.redis"
    local red = redis:new()
    red:set_timeout(1000)

    local redis_host = os.getenv("REDIS_HOST") or "taguato-redis"
    local redis_port = tonumber(os.getenv("REDIS_PORT")) or 6379
    local fail_mode = os.getenv("RATE_LIMIT_FAIL_MODE") or "open"

    local ok, err = red:connect(redis_host, redis_port)
    if not ok then
        ngx.log(ngx.ERR, "rate_limit: redis connect failed: ", err, " — falling back to shared dict")

        -- Fallback to nginx shared dict
        local rate_store = ngx.shared.rate_limit_store
        if rate_store then
            local key = "rl:redis_fallback:" .. user_id
            local current = rate_store:get(key)
            if current then
                if current >= limit then
                    return false
                end
                rate_store:incr(key, 1)
            else
                rate_store:set(key, 1, 60)
            end
            return true
        end

        -- Both Redis and shared dict unavailable
        if fail_mode == "closed" then
            ngx.log(ngx.ERR, "rate_limit: all backends unavailable, rejecting request (fail_mode=closed)")
            return false
        end
        return true
    end

    local key = "taguato:ratelimit:" .. user_id
    local current, incr_err = red:incr(key)
    if not current then
        red:set_keepalive(10000, 10)
        if fail_mode == "closed" then
            return false
        end
        return true
    end

    if current == 1 then
        red:expire(key, 60)
    end

    red:set_keepalive(10000, 10)

    if current > limit then
        return false
    end

    return true
end

return _M
