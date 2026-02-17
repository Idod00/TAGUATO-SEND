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

    local key = "taguato:ratelimit:" .. user_id
    local current, err = red:incr(key)
    if not current then
        red:set_keepalive(10000, 10)
        ngx.log(ngx.WARN, "rate_limit: redis incr failed, using shared dict fallback: ", err)
        return check_shared_dict(user_id, limit)
    end

    if current == 1 then
        red:expire(key, 1)
    end

    red:set_keepalive(10000, 10)

    if current > limit then
        return false
    end

    return true
end

return _M
