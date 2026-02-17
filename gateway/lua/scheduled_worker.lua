-- Scheduled messages worker
-- Runs on a timer, picks up pending messages and sends them
-- Idempotent: checks message_logs before sending to prevent duplicates on crash recovery

local _M = {}

function _M.check()
    local http = require "resty.http"
    local cjson = require "cjson"
    local db = require "init"
    local log = require "log"

    local api_key = os.getenv("AUTHENTICATION_API_KEY")
    if not api_key then
        log.err("scheduled_worker", "AUTHENTICATION_API_KEY not set")
        return
    end

    -- Fetch pending messages that are due (includes 'processing' for crash recovery)
    local pending, err = db.query(
        [[SELECT id, user_id, instance_name, message_type, message_content, recipients, scheduled_at
          FROM taguato.scheduled_messages
          WHERE status IN ('pending', 'processing') AND scheduled_at <= NOW()
          ORDER BY scheduled_at ASC
          LIMIT 5]]
    )

    if not pending or #pending == 0 then
        return
    end

    for _, msg in ipairs(pending) do
        -- Mark as processing
        db.query(
            "UPDATE taguato.scheduled_messages SET status = 'processing', updated_at = NOW() WHERE id = $1",
            msg.id
        )

        local ok_parse, recipients = pcall(cjson.decode, msg.recipients)
        if not ok_parse or type(recipients) ~= "table" then
            log.err("scheduled_worker", "invalid recipients JSON", { message_id = msg.id })
            db.query(
                "UPDATE taguato.scheduled_messages SET status = 'failed', results = $1, updated_at = NOW() WHERE id = $2",
                cjson.encode({ total = 0, sent = 0, failed = 0, errors = { "Invalid recipients JSON" } }),
                msg.id
            )
            goto continue
        end

        local total = #recipients
        local sent_count = 0
        local failed_count = 0
        local skipped_count = 0
        local errors = {}

        for i, number in ipairs(recipients) do
            number = tostring(number):gsub("^%s+", ""):gsub("%s+$", "")
            if number == "" then
                goto next_recipient
            end

            -- Idempotency check: skip if already sent for this scheduled message
            local already_sent = db.query(
                "SELECT id FROM taguato.message_logs WHERE scheduled_message_id = $1 AND phone_number = $2 AND status = 'sent' LIMIT 1",
                msg.id, number
            )
            if already_sent and #already_sent > 0 then
                sent_count = sent_count + 1
                skipped_count = skipped_count + 1
                goto next_recipient
            end

            local httpc = http.new()
            httpc:set_timeout(10000)

            local send_ok = false
            local send_err = nil

            if msg.message_type == "text" then
                local res, req_err = httpc:request_uri(
                    "http://taguato-api:8080/message/sendText/" .. msg.instance_name,
                    {
                        method = "POST",
                        headers = {
                            ["apikey"] = api_key,
                            ["Content-Type"] = "application/json",
                        },
                        body = cjson.encode({ number = number, text = msg.message_content }),
                    }
                )
                if res and res.status >= 200 and res.status < 300 then
                    send_ok = true
                else
                    send_err = req_err or (res and "status " .. res.status) or "unknown error"
                end
            else
                -- Media message: message_content is JSON with media details
                local media_ok, media_body = pcall(cjson.decode, msg.message_content)
                if media_ok and type(media_body) == "table" then
                    media_body.number = number
                    local res, req_err = httpc:request_uri(
                        "http://taguato-api:8080/message/sendMedia/" .. msg.instance_name,
                        {
                            method = "POST",
                            headers = {
                                ["apikey"] = api_key,
                                ["Content-Type"] = "application/json",
                            },
                            body = cjson.encode(media_body),
                        }
                    )
                    if res and res.status >= 200 and res.status < 300 then
                        send_ok = true
                    else
                        send_err = req_err or (res and "status " .. res.status) or "unknown error"
                    end
                else
                    send_err = "invalid media content JSON"
                end
            end

            if send_ok then
                sent_count = sent_count + 1
                -- Log to message_logs with scheduled_message_id for idempotency
                db.query(
                    [[INSERT INTO taguato.message_logs (user_id, instance_name, phone_number, message_type, status, scheduled_message_id)
                      VALUES ($1, $2, $3, $4, 'sent', $5)]],
                    msg.user_id, msg.instance_name, number, msg.message_type, msg.id
                )
            else
                failed_count = failed_count + 1
                errors[#errors + 1] = number .. ": " .. (send_err or "unknown")
                db.query(
                    [[INSERT INTO taguato.message_logs (user_id, instance_name, phone_number, message_type, status, error_message, scheduled_message_id)
                      VALUES ($1, $2, $3, $4, 'failed', $5, $6)]],
                    msg.user_id, msg.instance_name, number, msg.message_type, send_err, msg.id
                )
            end

            -- Delay between sends (1 second)
            if i < total then
                ngx.sleep(1)
            end

            ::next_recipient::
        end

        -- Update final status
        local final_status = (failed_count == total) and "failed" or "completed"
        local results = cjson.encode({
            total = total,
            sent = sent_count,
            failed = failed_count,
            skipped = skipped_count,
            errors = errors,
        })

        db.query(
            "UPDATE taguato.scheduled_messages SET status = $1, results = $2, updated_at = NOW() WHERE id = $3",
            final_status, results, msg.id
        )

        log.info("scheduled_worker", "message processed", {
            message_id = msg.id, status = final_status, sent = sent_count, failed = failed_count, skipped = skipped_count
        })

        ::continue::
    end

    -- Cleanup: delete completed/cancelled/failed messages older than 30 days
    db.query(
        [[DELETE FROM taguato.scheduled_messages
          WHERE status IN ('completed', 'cancelled', 'failed')
          AND updated_at < NOW() - INTERVAL '30 days']]
    )
end

return _M
