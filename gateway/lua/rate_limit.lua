-- Per-user rate limiting using Redis sliding window
-- Called from access.lua after authentication

local _M = {}

function _M.check(user_id, limit)
    if not limit or limit <= 0 then
        return true -- no limit configured
    end

    local db = require "init"
    local red, err = db.get_redis(1000)
    if not red then
        ngx.log(ngx.ERR, "rate_limit: redis connect failed: ", err)
        return true -- fail open on redis error
    end

    local key = "taguato:ratelimit:" .. user_id
    local current, err = red:incr(key)
    if not current then
        red:set_keepalive(10000, 10)
        return true
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
