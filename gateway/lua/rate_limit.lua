-- Per-user rate limiting using Redis sliding window
-- Called from access.lua after authentication

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

    local ok, err = red:connect(redis_host, redis_port)
    if not ok then
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
