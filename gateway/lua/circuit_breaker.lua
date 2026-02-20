-- Circuit breaker for Evolution API
-- Tracks consecutive upstream failures in shared dict.
-- Trips after THRESHOLD consecutive failures, resets after RESET_TIME seconds.

local _M = {}

local THRESHOLD = 5       -- consecutive failures before tripping
local RESET_TIME = 30     -- seconds to wait before half-open (allow retry)

local FAILURES_KEY = "cb:failures"
local OPEN_UNTIL_KEY = "cb:open_until"

function _M.is_open()
    local dict = ngx.shared.circuit_breaker
    if not dict then return false end

    local open_until = dict:get(OPEN_UNTIL_KEY)
    if not open_until then return false end

    if ngx.now() < open_until then
        return true
    end

    -- Reset time expired: half-open, allow traffic through
    dict:delete(OPEN_UNTIL_KEY)
    dict:set(FAILURES_KEY, 0)
    return false
end

function _M.record_failure()
    local dict = ngx.shared.circuit_breaker
    if not dict then return end

    local new_val, err = dict:incr(FAILURES_KEY, 1, 0)
    if not new_val then return end

    if new_val >= THRESHOLD then
        dict:set(OPEN_UNTIL_KEY, ngx.now() + RESET_TIME)
        ngx.log(ngx.WARN, "circuit breaker OPEN: ", new_val, " consecutive upstream failures")
        -- External alert
        local ok, alerting = pcall(require, "alerting")
        if ok then alerting.circuit_breaker_open(new_val) end
    end
end

function _M.record_success()
    local dict = ngx.shared.circuit_breaker
    if not dict then return end

    -- Reset failure count on success
    local failures = dict:get(FAILURES_KEY)
    if failures and failures > 0 then
        dict:set(FAILURES_KEY, 0)
        -- If we were in half-open state, we're now closed
        dict:delete(OPEN_UNTIL_KEY)
    end
end

return _M
