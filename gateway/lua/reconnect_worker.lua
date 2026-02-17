-- Auto-reconnect worker
-- Runs on a timer, checks all instances, reconnects disconnected ones
-- Features: limit per cycle, skip instances with repeated failures

local log = require "log"

local _M = {}

function _M.check()
    local http = require "resty.http"
    local cjson = require "cjson"
    local db = require "init"

    local api_key = os.getenv("AUTHENTICATION_API_KEY")
    if not api_key then
        log.err("reconnect_worker", "AUTHENTICATION_API_KEY not set")
        return
    end

    local httpc = http.new()
    httpc:set_timeout(5000)

    -- Fetch all instances
    local res, err = httpc:request_uri("http://taguato-api:8080/instance/fetchInstances", {
        method = "GET",
        headers = { ["apikey"] = api_key },
    })

    if not res or res.status ~= 200 then
        log.err("reconnect_worker", "failed to fetch instances", { error = err or (res and res.status) })
        return
    end

    local ok, instances = pcall(cjson.decode, res.body)
    if not ok or type(instances) ~= "table" then
        log.err("reconnect_worker", "invalid instances response")
        return
    end

    -- Find instances that failed 5+ consecutive times in the last hour — skip them
    local skip_list = {}
    local recently_failed, _ = db.query(
        [[SELECT instance_name, COUNT(*) as fail_count
          FROM taguato.reconnect_log
          WHERE result = 'failed'
            AND created_at > NOW() - INTERVAL '1 hour'
          GROUP BY instance_name
          HAVING COUNT(*) >= 5]]
    )
    if recently_failed then
        for _, row in ipairs(recently_failed) do
            skip_list[row.instance_name] = true
        end
    end

    local processed = 0
    local max_per_cycle = 10

    for _, inst in ipairs(instances) do
        if processed >= max_per_cycle then
            log.info("reconnect_worker", "cycle limit reached", { processed = processed })
            break
        end

        local name = inst.instance and inst.instance.instanceName
        local state = inst.instance and inst.instance.state

        if name and state and state ~= "open" then
            -- Skip instances that have failed too many times recently
            if skip_list[name] then
                log.info("reconnect_worker", "skipping (too many recent failures)", { instance = name })
                goto continue
            end

            log.info("reconnect_worker", "attempting reconnect", { instance = name, state = state })

            local reconn_httpc = http.new()
            reconn_httpc:set_timeout(5000)

            local reconn_res, reconn_err = reconn_httpc:request_uri(
                "http://taguato-api:8080/instance/connect/" .. name,
                {
                    method = "GET",
                    headers = { ["apikey"] = api_key },
                }
            )

            local result = "unknown"
            local error_msg = nil

            if reconn_res and reconn_res.status == 200 then
                result = "reconnected"
                log.info("reconnect_worker", "reconnected", { instance = name })
            else
                result = "failed"
                error_msg = reconn_err or (reconn_res and "status " .. reconn_res.status) or "unknown error"
                log.warn("reconnect_worker", "failed to reconnect", { instance = name, error = error_msg })
            end

            -- Log to reconnect_log
            db.query(
                [[INSERT INTO taguato.reconnect_log (instance_name, previous_state, action, result, error_message)
                  VALUES ($1, $2, $3, $4, $5)]],
                name, state, "auto_reconnect", result, error_msg
            )

            processed = processed + 1
            ::continue::
        end
    end
end

return _M
