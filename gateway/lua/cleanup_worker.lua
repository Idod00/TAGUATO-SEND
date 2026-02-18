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

-- Delete rows in batches to avoid long-running locks.
-- SQL must include "LIMIT $BATCH" placeholder inside the subquery.
-- Returns total number of rows deleted.
local function batched_delete(db, log, sql, batch_size, table_name)
    local total_deleted = 0
    local batch_sql = sql:gsub("%$BATCH", tostring(batch_size))

    for _ = 1, 100 do -- safety cap: max 100 iterations (500K rows)
        local res, err = db.query(batch_sql)
        if not res then
            log.err("cleanup_worker", "batched delete failed", { table = table_name, error = err })
            break
        end

        -- pgmoon returns affected_rows for DELETE without RETURNING
        -- With RETURNING, res is a table of rows
        local deleted = (type(res) == "table") and #res or 0
        if deleted == 0 then
            break
        end

        total_deleted = total_deleted + deleted

        -- Yield briefly between batches to let other queries through
        ngx.sleep(0.05)
    end

    return total_deleted
end

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

    -- 8. Cleanup expired/used password reset codes
    local pr_del, pr_err = db.query(
        [[DELETE FROM taguato.password_resets
          WHERE (used_at IS NOT NULL AND used_at < NOW() - INTERVAL '1 hour')
             OR expires_at < NOW() - INTERVAL '24 hours']]
    )
    if pr_del and type(pr_del) == "table" and #pr_del > 0 then
        log.info("cleanup_worker", "cleaned password_resets", { count = #pr_del })
    end
end

-- Heavy tasks: run once per cycle (every 6 hours via separate timer)
-- Uses batched deletes (5000 rows at a time) to avoid long table locks.
function _M.cleanup_tables()
    local db = require "init"
    local log = require "log"

    local batch_size = 5000

    -- 3. Delete old message_logs (>90 days)
    local ml_count = batched_delete(db, log,
        [[DELETE FROM taguato.message_logs
          WHERE id IN (
            SELECT id FROM taguato.message_logs
            WHERE created_at < NOW() - INTERVAL '90 days'
            ORDER BY id ASC
            LIMIT $BATCH
          )]],
        batch_size, "message_logs"
    )
    if ml_count > 0 then
        log.info("cleanup_worker", "purged old message_logs", { count = ml_count })
    end

    -- 4. Delete old audit_log (>180 days)
    local al_count = batched_delete(db, log,
        [[DELETE FROM taguato.audit_log
          WHERE id IN (
            SELECT id FROM taguato.audit_log
            WHERE created_at < NOW() - INTERVAL '180 days'
            ORDER BY id ASC
            LIMIT $BATCH
          )]],
        batch_size, "audit_log"
    )
    if al_count > 0 then
        log.info("cleanup_worker", "purged old audit_log", { count = al_count })
    end

    -- 5. Delete old reconnect_log (>90 days)
    local rl_count = batched_delete(db, log,
        [[DELETE FROM taguato.reconnect_log
          WHERE id IN (
            SELECT id FROM taguato.reconnect_log
            WHERE created_at < NOW() - INTERVAL '90 days'
            ORDER BY id ASC
            LIMIT $BATCH
          )]],
        batch_size, "reconnect_log"
    )
    if rl_count > 0 then
        log.info("cleanup_worker", "purged old reconnect_log", { count = rl_count })
    end

    -- 6. Delete old uptime_checks (>30 days)
    local uc_count = batched_delete(db, log,
        [[DELETE FROM taguato.uptime_checks
          WHERE id IN (
            SELECT id FROM taguato.uptime_checks
            WHERE checked_at < NOW() - INTERVAL '30 days'
            ORDER BY id ASC
            LIMIT $BATCH
          )]],
        batch_size, "uptime_checks"
    )
    if uc_count > 0 then
        log.info("cleanup_worker", "purged old uptime_checks", { count = uc_count })
    end

    -- Also clean inactive sessions older than 7 days
    batched_delete(db, log,
        [[DELETE FROM taguato.sessions
          WHERE id IN (
            SELECT id FROM taguato.sessions
            WHERE is_active = false AND created_at < NOW() - INTERVAL '7 days'
            ORDER BY id ASC
            LIMIT $BATCH
          )]],
        batch_size, "sessions"
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
            -- Failed: increment retry count, deactivate if max retries reached
            local err_msg = req_err or (res and "status " .. res.status) or "unknown"
            local new_retry = (wh.retry_count or 0) + 1
            if new_retry >= 3 then
                db.query(
                    [[UPDATE taguato.user_webhooks
                      SET retry_count = $1, last_error = $2, needs_sync = false, is_active = false, updated_at = NOW()
                      WHERE id = $3]],
                    new_retry, err_msg .. " (deactivated after max retries)", wh.id
                )
                log.warn("cleanup_worker", "webhook deactivated after max retries", {
                    webhook_id = wh.id, instance = wh.instance_name
                })
            else
                db.query(
                    [[UPDATE taguato.user_webhooks
                      SET retry_count = retry_count + 1, last_error = $1, updated_at = NOW()
                      WHERE id = $2]],
                    err_msg, wh.id
                )
                log.warn("cleanup_worker", "webhook sync failed", {
                    webhook_id = wh.id, instance = wh.instance_name,
                    retry = new_retry, error = err_msg
                })
            end
        end
    end
end

return _M
