-- Cleanup worker: periodic maintenance tasks
-- Runs every 5 minutes on worker 0
--
-- Tasks:
-- 1. Expire stale web panel sessions (24h TTL)
-- 2. Reset stuck 'processing' scheduled messages (>10 min)
-- 3. Cleanup old message_logs (90 days)
-- 4. Cleanup old audit_log (180 days)
-- 5. Cleanup old reconnect_log (90 days)
-- 6. Cleanup old uptime_checks (30 days)
-- 7. Retry failed webhook configurations (needs_sync, max 3 retries)

local _M = {}

-- Lightweight tasks: run every cycle (5 min)
function _M.check()
    local db = require "init"
    local log = require "log"

    -- 1. Expire stale sessions
    local expired, err = db.query(
        [[UPDATE taguato.sessions
          SET is_active = false
          WHERE is_active = true AND expires_at < NOW()
          RETURNING id]]
    )
    if expired and #expired > 0 then
        log.info("cleanup_worker", "expired sessions", { count = #expired })
    end

    -- 2. Reset stuck 'processing' scheduled messages (>10 minutes)
    local stuck, err2 = db.query(
        [[UPDATE taguato.scheduled_messages
          SET status = 'pending', updated_at = NOW()
          WHERE status = 'processing' AND updated_at < NOW() - INTERVAL '10 minutes'
          RETURNING id]]
    )
    if stuck and #stuck > 0 then
        log.warn("cleanup_worker", "reset stuck scheduled messages", { count = #stuck })
    end

    -- 7. Retry failed webhook configurations
    _M.retry_webhooks()
end

-- Heavy tasks: run once per cycle (every 6 hours via separate timer)
function _M.cleanup_tables()
    local db = require "init"
    local log = require "log"

    -- 3. Delete old message_logs (>90 days)
    local ml, err = db.query(
        [[DELETE FROM taguato.message_logs
          WHERE created_at < NOW() - INTERVAL '90 days'
          RETURNING id]]
    )
    if ml and #ml > 0 then
        log.info("cleanup_worker", "purged old message_logs", { count = #ml })
    end

    -- 4. Delete old audit_log (>180 days)
    local al, err2 = db.query(
        [[DELETE FROM taguato.audit_log
          WHERE created_at < NOW() - INTERVAL '180 days'
          RETURNING id]]
    )
    if al and #al > 0 then
        log.info("cleanup_worker", "purged old audit_log", { count = #al })
    end

    -- 5. Delete old reconnect_log (>90 days)
    local rl, err3 = db.query(
        [[DELETE FROM taguato.reconnect_log
          WHERE created_at < NOW() - INTERVAL '90 days'
          RETURNING id]]
    )
    if rl and #rl > 0 then
        log.info("cleanup_worker", "purged old reconnect_log", { count = #rl })
    end

    -- 6. Delete old uptime_checks (>30 days)
    local uc, err4 = db.query(
        [[DELETE FROM taguato.uptime_checks
          WHERE checked_at < NOW() - INTERVAL '30 days'
          RETURNING id]]
    )
    if uc and #uc > 0 then
        log.info("cleanup_worker", "purged old uptime_checks", { count = #uc })
    end

    -- Also clean inactive sessions older than 7 days
    db.query(
        [[DELETE FROM taguato.sessions
          WHERE is_active = false AND created_at < NOW() - INTERVAL '7 days']]
    )
end

-- Retry webhook configurations that failed
function _M.retry_webhooks()
    local db = require "init"
    local log = require "log"
    local http = require "resty.http"
    local cjson = require "cjson"

    local api_key = os.getenv("AUTHENTICATION_API_KEY")
    if not api_key then return end

    -- Find webhooks that need sync (max 3 retries)
    local pending, err = db.query(
        [[SELECT id, instance_name, webhook_url, events, retry_count
          FROM taguato.user_webhooks
          WHERE needs_sync = true AND retry_count < 3 AND is_active = true
          ORDER BY retry_count ASC
          LIMIT 5]]
    )

    if not pending or #pending == 0 then return end

    for _, wh in ipairs(pending) do
        local httpc = http.new()
        httpc:set_timeout(5000)

        local events = wh.events or {}
        local webhook_body = {
            url = wh.webhook_url,
            webhook_by_events = (type(events) == "table" and #events > 0),
            webhook_base64 = false,
            events = events,
        }

        local res, req_err = httpc:request_uri(
            "http://taguato-api:8080/webhook/set/" .. wh.instance_name,
            {
                method = "POST",
                headers = {
                    ["apikey"] = api_key,
                    ["Content-Type"] = "application/json",
                },
                body = cjson.encode(webhook_body),
            }
        )

        if res and res.status < 400 then
            -- Success: clear sync flag
            db.query(
                [[UPDATE taguato.user_webhooks
                  SET needs_sync = false, retry_count = 0, last_error = NULL, updated_at = NOW()
                  WHERE id = $1]],
                wh.id
            )
            log.info("cleanup_worker", "webhook sync succeeded", { webhook_id = wh.id, instance = wh.instance_name })
        else
            -- Failed: increment retry count
            local err_msg = req_err or (res and "status " .. res.status) or "unknown"
            db.query(
                [[UPDATE taguato.user_webhooks
                  SET retry_count = retry_count + 1, last_error = $1, updated_at = NOW()
                  WHERE id = $2]],
                err_msg, wh.id
            )
            log.warn("cleanup_worker", "webhook sync failed", {
                webhook_id = wh.id, instance = wh.instance_name,
                retry = wh.retry_count + 1, error = err_msg
            })
        end
    end
end

return _M
