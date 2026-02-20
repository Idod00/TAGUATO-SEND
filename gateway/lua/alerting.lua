-- External alerting via webhook (Slack, Discord, Teams, generic)
-- Sends notifications when services go down or circuit breaker opens.
-- Configure via env: ALERT_WEBHOOK_URL, ALERT_COOLDOWN_SECONDS

local cjson = require "cjson"
local http = require "resty.http"

local _M = {}

local COOLDOWN_DEFAULT = 300 -- 5 minutes between repeated alerts for same event

local function get_config()
    local url = os.getenv("ALERT_WEBHOOK_URL")
    if not url or url == "" then
        return nil
    end
    local cooldown = tonumber(os.getenv("ALERT_COOLDOWN_SECONDS")) or COOLDOWN_DEFAULT
    return { url = url, cooldown = cooldown }
end

-- Check cooldown: returns true if we should send (not in cooldown)
local function check_cooldown(key, cooldown)
    local dict = ngx.shared.alert_cooldown
    if not dict then return true end

    local last_sent = dict:get(key)
    if last_sent and (ngx.now() - last_sent) < cooldown then
        return false
    end
    dict:set(key, ngx.now(), cooldown)
    return true
end

-- Send webhook payload via resty.http (safe — no shell involved)
local function send_webhook(url, payload)
    local json_body = cjson.encode(payload)

    local httpc = http.new()
    httpc:set_timeout(10000)

    local res, err = httpc:request_uri(url, {
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
        },
        body = json_body,
        ssl_verify = false,
    })

    if not res then
        ngx.log(ngx.ERR, "alerting: webhook request failed: ", err)
        return false
    end

    if res.status >= 400 then
        ngx.log(ngx.ERR, "alerting: webhook returned HTTP ", res.status)
        return false
    end

    return true
end

-- Public: send a service down alert
function _M.service_down(service_name, details)
    local config = get_config()
    if not config then return end

    local key = "svc_down:" .. service_name
    if not check_cooldown(key, config.cooldown) then return end

    local payload = {
        text = "[TAGUATO-SEND] Service DOWN: " .. service_name .. (details and (" - " .. details) or ""),
        username = "TAGUATO-SEND Alerts",
        embeds = {
            {
                title = "Service DOWN: " .. service_name,
                description = details or "Service is not responding",
                color = 14495300,
            },
        },
    }

    ngx.timer.at(0, function()
        send_webhook(config.url, payload)
    end)
end

-- Public: send a service recovered alert
function _M.service_recovered(service_name)
    local config = get_config()
    if not config then return end

    local key = "svc_up:" .. service_name
    if not check_cooldown(key, config.cooldown) then return end

    local payload = {
        text = "[TAGUATO-SEND] Service RECOVERED: " .. service_name,
        username = "TAGUATO-SEND Alerts",
        embeds = {
            {
                title = "Service RECOVERED: " .. service_name,
                description = "Service is operational again",
                color = 5763719,
            },
        },
    }

    ngx.timer.at(0, function()
        send_webhook(config.url, payload)
    end)
end

-- Public: circuit breaker state change alert
function _M.circuit_breaker_open(failures)
    local config = get_config()
    if not config then return end

    local key = "cb_open"
    if not check_cooldown(key, config.cooldown) then return end

    local payload = {
        text = "[TAGUATO-SEND] Circuit Breaker OPEN after " .. tostring(failures) .. " consecutive failures",
        username = "TAGUATO-SEND Alerts",
        embeds = {
            {
                title = "Circuit Breaker OPEN",
                description = failures .. " consecutive upstream failures. Requests blocked for 30s.",
                color = 16776960,
            },
        },
    }

    ngx.timer.at(0, function()
        send_webhook(config.url, payload)
    end)
end

return _M
