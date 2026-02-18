-- Per-user rate limiting using Redis sliding window
-- Falls back to ngx.shared.rate_limit_store when Redis is unavailable
-- Called from access.lua after authentication

local _M = {}

local function check_shared_dict(user_id, limit)
    local dict = ngx.shared.rate_limit_store
    if not dict then
        return true -- no shared dict configured, fail open
    end

    local key = "rl:" .. user_id
    local newval, err = dict:incr(key, 1, 0, 1)
    if not newval then
        ngx.log(ngx.WARN, "rate_limit: shared dict incr failed: ", err)
        return true
    end

    return newval <= limit
end

function _M.check(user_id, limit)
    if not limit or limit <= 0 then
        return true -- no limit configured
    end

    local db = require "init"
    local red, err = db.get_redis(1000)
    if not red then
        ngx.log(ngx.WARN, "rate_limit: redis unavailable, using shared dict fallback: ", err)
        return check_shared_dict(user_id, limit)
    end

    -- Atomic incr+expire via Lua script to avoid race conditions
    local key = "taguato:ratelimit:" .. user_id
    local script = [[
        local current = redis.call('incr', KEYS[1])
        if current == 1 then
            redis.call('expire', KEYS[1], ARGV[1])
        end
        return current
    ]]
    local current, err = red:eval(script, 1, key, 1)
    if not current then
        red:set_keepalive(10000, 10)
        ngx.log(ngx.WARN, "rate_limit: redis eval failed, using shared dict fallback: ", err)
        return check_shared_dict(user_id, limit)
    end

    red:set_keepalive(10000, 10)

    return current <= limit
end

return _M
