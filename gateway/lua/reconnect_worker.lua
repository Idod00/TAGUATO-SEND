-- Auto-reconnect worker
-- Runs on a timer, checks all instances, reconnects disconnected ones

local _M = {}

function _M.check()
    local http = require "resty.http"
    local cjson = require "cjson"

    local api_key = os.getenv("AUTHENTICATION_API_KEY")
    if not api_key then
        ngx.log(ngx.ERR, "reconnect_worker: AUTHENTICATION_API_KEY not set")
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
        ngx.log(ngx.ERR, "reconnect_worker: failed to fetch instances: ", err or (res and res.status))
        return
    end

    local ok, instances = pcall(cjson.decode, res.body)
    if not ok or type(instances) ~= "table" then
        ngx.log(ngx.ERR, "reconnect_worker: invalid instances response")
        return
    end

    -- Database for logging
    local db = require "init"

    for _, inst in ipairs(instances) do
        local name = inst.instance and inst.instance.instanceName
        local state = inst.instance and inst.instance.state

        if name and state and state ~= "open" then
            ngx.log(ngx.INFO, "reconnect_worker: attempting reconnect for ", name, " (state: ", state, ")")

            local reconn_res, reconn_err = httpc:request_uri(
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
                ngx.log(ngx.INFO, "reconnect_worker: reconnected ", name)
            else
                result = "failed"
                error_msg = reconn_err or (reconn_res and "status " .. reconn_res.status) or "unknown error"
                ngx.log(ngx.WARN, "reconnect_worker: failed to reconnect ", name, ": ", error_msg)
            end

            -- Log to reconnect_log
            db.query(
                [[INSERT INTO taguato.reconnect_log (instance_name, previous_state, action, result, error_message)
                  VALUES ($1, $2, $3, $4, $5)]],
                name, state, "auto_reconnect", result, error_msg
            )
        end
    end
end

return _M
