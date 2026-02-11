-- Webhook CRUD endpoints
-- GET /api/webhooks - List user webhooks
-- POST /api/webhooks - Create webhook (+ configure in Evolution API)
-- DELETE /api/webhooks/{id} - Delete webhook (+ remove from Evolution API)

local db = require "init"
local json = require "json"
local cjson = require "cjson"
local validate = require "validate"
local http = require "resty.http"

local empty_array_mt = cjson.empty_array_mt
local function as_array(t)
    if t == nil or (type(t) == "table" and #t == 0) then
        return setmetatable({}, empty_array_mt)
    end
    return t
end

local user = ngx.ctx.user
if not user then
    json.respond(401, { error = "Unauthorized" })
    return
end

local method = ngx.req.get_method()
local uri = ngx.var.uri

local webhook_id = uri:match("^/api/webhooks/(%d+)$")

-- GET /api/webhooks - List webhooks
if method == "GET" and uri == "/api/webhooks" then
    local res, err = db.query(
        [[SELECT id, instance_name, webhook_url, events, is_active, created_at, updated_at
          FROM taguato.user_webhooks
          WHERE user_id = $1
          ORDER BY created_at DESC]],
        user.id
    )
    if not res then
        json.respond(500, { error = "Failed to list webhooks" })
        return
    end
    json.respond(200, { webhooks = as_array(res) })
    return
end

-- POST /api/webhooks - Create webhook
if method == "POST" and uri == "/api/webhooks" then
    local body, err = json.read_body()
    if not body then
        json.respond(400, { error = "Invalid JSON body" })
        return
    end

    if not body.instance_name or body.instance_name == "" then
        json.respond(400, { error = "instance_name is required" })
        return
    end
    if not body.webhook_url or body.webhook_url == "" then
        json.respond(400, { error = "webhook_url is required" })
        return
    end

    -- Basic URL validation
    if not body.webhook_url:match("^https?://") then
        json.respond(400, { error = "webhook_url must start with http:// or https://" })
        return
    end

    -- Verify instance ownership (admin bypass)
    if user.role ~= "admin" then
        local own = db.query(
            "SELECT id FROM taguato.user_instances WHERE user_id = $1 AND instance_name = $2 LIMIT 1",
            user.id, body.instance_name
        )
        if not own or #own == 0 then
            json.respond(403, { error = "You do not own this instance" })
            return
        end
    end

    local events = body.events or {}
    if type(events) ~= "table" then
        events = {}
    end

    -- Convert events array to PostgreSQL array literal
    local events_pg = "{" .. table.concat(events, ",") .. "}"

    -- Insert webhook into DB
    local res, db_err = db.query(
        [[INSERT INTO taguato.user_webhooks (user_id, instance_name, webhook_url, events)
          VALUES ($1, $2, $3, $4)
          RETURNING id, instance_name, webhook_url, events, is_active, created_at]],
        user.id, body.instance_name, body.webhook_url, events_pg
    )

    if not res then
        if db_err and db_err:find("duplicate key") then
            json.respond(409, { error = "Webhook already exists for this instance" })
        else
            json.respond(500, { error = "Failed to create webhook" })
        end
        return
    end

    -- Configure webhook in Evolution API
    local api_key = os.getenv("AUTHENTICATION_API_KEY")
    if api_key then
        local httpc = http.new()
        httpc:set_timeout(5000)
        local webhook_body = {
            url = body.webhook_url,
            webhook_by_events = (#events > 0),
            webhook_base64 = false,
            events = events,
        }
        local api_res, api_err = httpc:request_uri(
            "http://taguato-api:8080/webhook/set/" .. body.instance_name,
            {
                method = "POST",
                headers = {
                    ["apikey"] = api_key,
                    ["Content-Type"] = "application/json",
                },
                body = cjson.encode(webhook_body),
            }
        )
        if not api_res or api_res.status >= 400 then
            ngx.log(ngx.WARN, "webhooks: failed to set webhook in Evolution API: ",
                api_err or (api_res and api_res.status))
        end
    end

    json.respond(201, { webhook = res[1] })
    return
end

-- DELETE /api/webhooks/{id} - Delete webhook
if method == "DELETE" and webhook_id then
    -- Find webhook and verify ownership
    local wh = db.query(
        "SELECT id, instance_name FROM taguato.user_webhooks WHERE id = $1 AND user_id = $2",
        webhook_id, user.id
    )
    if not wh or #wh == 0 then
        json.respond(404, { error = "Webhook not found" })
        return
    end

    local instance_name = wh[1].instance_name

    -- Delete from DB
    local res, err = db.query(
        "DELETE FROM taguato.user_webhooks WHERE id = $1 AND user_id = $2 RETURNING id",
        webhook_id, user.id
    )
    if not res or #res == 0 then
        json.respond(500, { error = "Failed to delete webhook" })
        return
    end

    -- Remove webhook from Evolution API
    local api_key = os.getenv("AUTHENTICATION_API_KEY")
    if api_key then
        local httpc = http.new()
        httpc:set_timeout(5000)
        local api_res, api_err = httpc:request_uri(
            "http://taguato-api:8080/webhook/set/" .. instance_name,
            {
                method = "POST",
                headers = {
                    ["apikey"] = api_key,
                    ["Content-Type"] = "application/json",
                },
                body = cjson.encode({
                    url = "",
                    webhook_by_events = false,
                    events = {},
                }),
            }
        )
        if not api_res or api_res.status >= 400 then
            ngx.log(ngx.WARN, "webhooks: failed to clear webhook in Evolution API: ",
                api_err or (api_res and api_res.status))
        end
    end

    json.respond(200, { deleted = { id = tonumber(webhook_id) } })
    return
end

json.respond(404, { error = "Not found" })
