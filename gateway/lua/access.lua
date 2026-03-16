-- Combined access handler: auth + instance filtering + circuit breaker
-- This runs auth, circuit breaker check, and instance_filter logic in sequence,
-- since nginx only allows one access_by_lua_file per location.
-- Uses auth_cache shared dict to reduce DB queries (10s TTL).

-- Step 0: Circuit breaker check
local cb = require "circuit_breaker"
if cb.is_open() then
    local json = require "json"
    json.respond(503, { error = "Service temporarily unavailable, please retry later" })
    return
end

-- Step 1: Authenticate via session token
local db = require "init"
local json = require "json"
local session_auth = require "session_auth"

local token = ngx.req.get_headers()["apikey"]

if not token or token == "" then
    json.respond(401, { error = "Missing apikey header" })
    return
end

local user, auth_err = session_auth.validate(token)
if not user then
    json.respond(401, { error = "Invalid or expired session token" })
    return
end

if not user.is_active then
    json.respond(403, { error = "Account is disabled" })
    return
end

ngx.ctx.user = {
    id = user.id,
    username = user.username,
    role = user.role,
    max_instances = user.max_instances,
    rate_limit = user.rate_limit and tonumber(user.rate_limit) or nil,
}

-- Step 2: Per-user rate limiting
local user_rate_limit = user.rate_limit and tonumber(user.rate_limit) or nil
if user_rate_limit and user_rate_limit > 0 then
    local rate_limiter = require "rate_limit"
    if not rate_limiter.check(user.id, user_rate_limit) then
        json.respond(429, { error = "Rate limit exceeded", limit = user_rate_limit })
        return
    end
end

-- Step 3: Instance filtering (from instance_filter.lua)

local method = ngx.req.get_method()
local uri = ngx.var.uri
local is_admin = user.role == "admin"

-- Helper: check if user owns an instance
local function user_owns_instance(instance_name)
    local res = db.query(
        "SELECT id FROM taguato.user_instances WHERE user_id = $1 AND instance_name = $2",
        user.id, instance_name
    )
    return res and #res > 0
end

local function get_instance_channel_type(instance_name)
    local res = db.query(
        "SELECT channel_type FROM taguato.user_instances WHERE instance_name = $1",
        instance_name
    )
    if res and #res > 0 then
        return res[1].channel_type
    end
    return nil
end

local function telegram_secret()
    local secret = os.getenv("TELEGRAM_TOKEN_SECRET")
    if secret and secret ~= "" then
        return secret
    end
    return os.getenv("AUTHENTICATION_API_KEY")
end

local function get_telegram_bot_token(instance_name)
    local secret = telegram_secret()
    if not secret or secret == "" then
        return nil, "Telegram token secret is not configured"
    end
    local res = db.query(
        [[SELECT pgp_sym_decrypt(decode(bot_token_enc, 'base64'), $2::text)::text AS bot_token
          FROM taguato.telegram_instances
          WHERE instance_name = $1]],
        instance_name, secret
    )
    if not res or #res == 0 or not res[1].bot_token then
        return nil, "Telegram bot token not found for instance"
    end
    return res[1].bot_token
end

local function telegram_api_request(bot_token, method, payload, opts)
    local http = require "resty.http"
    local cjson = require "cjson"

    local httpc = http.new()
    httpc:set_timeout(20000)

    local api_url = "https://api.telegram.org/bot" .. bot_token .. "/" .. method
    local req = {
        method = "POST",
        ssl_verify = true,
        headers = {},
    }

    if opts and opts.content_type then
        req.headers["Content-Type"] = opts.content_type
    else
        req.headers["Content-Type"] = "application/json"
    end

    if opts and opts.body then
        req.body = opts.body
    else
        req.body = cjson.encode(payload or {})
    end

    local res, err = httpc:request_uri(api_url, req)
    if not res then
        return nil, { error = "Telegram request failed", details = err }
    end

    local ok, decoded = pcall(cjson.decode, res.body or "")
    if res.status ~= 200 then
        return nil, {
            error = "Telegram API error",
            status = res.status,
            details = ok and decoded or (res.body or ""),
        }
    end

    if ok and decoded and decoded.ok then
        return decoded.result, nil
    end

    return nil, { error = "Unexpected Telegram response", details = ok and decoded or (res.body or "") }
end

local function parse_data_url(data_url)
    if type(data_url) ~= "string" then return nil end
    local mime, b64 = data_url:match("^data:([^;]+);base64,(.+)$")
    if not mime or not b64 then return nil end
    local bin = ngx.decode_base64(b64)
    if not bin then return nil end
    return { mime = mime, data = bin }
end

local function guess_filename(mediatype, mime, file_name)
    if file_name and file_name ~= "" then
        return file_name
    end
    local ext = "bin"
    if mime == "image/jpeg" then ext = "jpg"
    elseif mime == "image/png" then ext = "png"
    elseif mime == "image/webp" then ext = "webp"
    elseif mime == "video/mp4" then ext = "mp4"
    elseif mime == "audio/mpeg" then ext = "mp3"
    elseif mime == "audio/ogg" then ext = "ogg"
    elseif mime == "application/pdf" then ext = "pdf"
    end
    local base = mediatype or "file"
    return base .. "." .. ext
end

local function build_multipart_form(fields, file_field)
    local boundary = "----taguato" .. tostring(ngx.time()) .. tostring(math.random(100000, 999999))
    local parts = {}

    local function add(s)
        parts[#parts + 1] = s
    end

    local function add_field(name, value)
        add("--" .. boundary .. "\r\n")
        add('Content-Disposition: form-data; name="' .. name .. '"\r\n\r\n')
        add(tostring(value) .. "\r\n")
    end

    for k, v in pairs(fields or {}) do
        if v ~= nil and tostring(v) ~= "" then
            add_field(k, v)
        end
    end

    if file_field then
        add("--" .. boundary .. "\r\n")
        add('Content-Disposition: form-data; name="' .. file_field.name .. '"; filename="' .. file_field.filename .. '"\r\n')
        add("Content-Type: " .. file_field.mime .. "\r\n\r\n")
        add(file_field.data)
        add("\r\n")
    end

    add("--" .. boundary .. "--\r\n")
    return table.concat(parts), "multipart/form-data; boundary=" .. boundary
end

-- Helper: count user instances
local function count_user_instances()
    local res = db.query(
        "SELECT COUNT(*) as count FROM taguato.user_instances WHERE user_id = $1",
        user.id
    )
    if res and #res > 0 then
        return tonumber(res[1].count)
    end
    return 0
end

-- Helper: get user's instance names as a set
local function get_user_instance_names()
    local res = db.query(
        "SELECT instance_name FROM taguato.user_instances WHERE user_id = $1",
        user.id
    )
    local names = {}
    if res then
        for _, row in ipairs(res) do
            names[row.instance_name] = true
        end
    end
    return names
end

-- Extract instance name from URI: /something/action/instance-name
local function extract_instance_from_uri()
    return uri:match("^/[^/]+/[^/]+/([^/]+)$")
end

-- ============ TELEGRAM MESSAGE SEND (intercept, no upstream) ============
local send_text_instance = uri:match("^/message/sendText/([^/]+)$")
if send_text_instance and method == "POST" then
    local channel_type = get_instance_channel_type(send_text_instance) or "whatsapp"
    if channel_type == "telegram" then
        if not is_admin and not user_owns_instance(send_text_instance) then
            json.respond(403, { error = "You don't own this instance" })
            return
        end

        local body = json.read_body()
        if not body then
            json.respond(400, { error = "Invalid JSON body" })
            return
        end

        local chat_id = body.number
        local text = body.text
        if not chat_id or tostring(chat_id) == "" then
            json.respond(400, { error = "chat_id (number) is required for Telegram" })
            return
        end
        if not text or tostring(text) == "" then
            json.respond(400, { error = "text is required" })
            return
        end

        local bot_token, tok_err = get_telegram_bot_token(send_text_instance)
        if not bot_token then
            json.respond(500, { error = tok_err or "Failed to load Telegram bot token" })
            return
        end

        local result, req_err = telegram_api_request(bot_token, "sendMessage", { chat_id = chat_id, text = text })
        if not result then
            json.respond(502, req_err or { error = "Telegram request failed" })
            return
        end

        json.respond(200, { ok = true, result = result })
        return
    end
end

local send_media_instance = uri:match("^/message/sendMedia/([^/]+)$")
if send_media_instance and method == "POST" then
    local channel_type = get_instance_channel_type(send_media_instance) or "whatsapp"
    if channel_type == "telegram" then
        if not is_admin and not user_owns_instance(send_media_instance) then
            json.respond(403, { error = "You don't own this instance" })
            return
        end

        local body = json.read_body()
        if not body then
            json.respond(400, { error = "Invalid JSON body" })
            return
        end

        local chat_id = body.number
        local mediatype = body.mediatype
        local media = body.media
        local caption = body.caption
        local file_name = body.fileName

        if not chat_id or tostring(chat_id) == "" then
            json.respond(400, { error = "chat_id (number) is required for Telegram" })
            return
        end
        if not mediatype or tostring(mediatype) == "" then
            json.respond(400, { error = "mediatype is required" })
            return
        end
        if not media or tostring(media) == "" then
            json.respond(400, { error = "media is required" })
            return
        end

        local api_method, file_field
        if mediatype == "image" then
            api_method = "sendPhoto"
            file_field = "photo"
        elseif mediatype == "document" then
            api_method = "sendDocument"
            file_field = "document"
        elseif mediatype == "audio" then
            api_method = "sendAudio"
            file_field = "audio"
        elseif mediatype == "video" then
            api_method = "sendVideo"
            file_field = "video"
        else
            json.respond(400, { error = "Invalid mediatype" })
            return
        end

        local bot_token, tok_err = get_telegram_bot_token(send_media_instance)
        if not bot_token then
            json.respond(500, { error = tok_err or "Failed to load Telegram bot token" })
            return
        end

        local data_url = parse_data_url(media)
        if data_url then
            local filename = guess_filename(mediatype, data_url.mime, file_name)
            local mp_body, mp_ct = build_multipart_form(
                { chat_id = chat_id, caption = caption },
                { name = file_field, filename = filename, mime = data_url.mime, data = data_url.data }
            )
            local result, req_err = telegram_api_request(bot_token, api_method, nil, {
                content_type = mp_ct,
                body = mp_body,
            })
            if not result then
                json.respond(502, req_err or { error = "Telegram request failed" })
                return
            end
            json.respond(200, { ok = true, result = result })
            return
        end

        -- URL / file_id
        local payload = { chat_id = chat_id, caption = caption }
        payload[file_field] = media
        local result, req_err = telegram_api_request(bot_token, api_method, payload)
        if not result then
            json.respond(502, req_err or { error = "Telegram request failed" })
            return
        end
        json.respond(200, { ok = true, result = result })
        return
    end
end

-- ============ INSTANCE CREATE ============
if uri == "/instance/create" and method == "POST" then
    local body, err = json.read_body()
    if not body or not body.instanceName then
        json.respond(400, { error = "instanceName is required" })
        return
    end

    local instance_name = body.instanceName

    -- Admin: proxy WhatsApp instance creation directly to Evolution API (no ownership insert)
    if is_admin and body.integration ~= "TELEGRAM" then
        ngx.req.set_body_data(json.encode(body))
        ngx.req.set_header("apikey", os.getenv("AUTHENTICATION_API_KEY"))
        return
    end

    -- Validate instance name format
    local validate = require "validate"
    local name_ok, name_err = validate.validate_instance_name(instance_name)
    if not name_ok then
        json.respond(400, { error = name_err })
        return
    end

    -- Determine channel type and validate accordingly
    local channel_type = "whatsapp"
    if body.integration == "TELEGRAM" then
        channel_type = "telegram"
        if not body.token or body.token == "" then
            json.respond(400, { error = "token is required for Telegram instances" })
            return
        end
        local token_ok, token_err = validate.validate_telegram_token(body.token)
        if not token_ok then
            json.respond(400, { error = token_err })
            return
        end
    end

    local ins_res, ins_err
    local max_instances = is_admin and 1000000 or user.max_instances

    if channel_type == "telegram" then
        local secret = telegram_secret()
        if not secret or secret == "" then
            json.respond(500, { error = "Telegram token secret is not configured" })
            return
        end

        -- Create ownership record + store encrypted bot token atomically (no upstream call to Evolution API)
        ins_res, ins_err = db.query(
            [[WITH ins AS (
                  INSERT INTO taguato.user_instances (user_id, instance_name, channel_type)
                  SELECT $1, $2, 'telegram'
                  WHERE (SELECT COUNT(*) FROM taguato.user_instances WHERE user_id = $1) < $3
                  ON CONFLICT (instance_name) DO NOTHING
                  RETURNING instance_name
              )
              INSERT INTO taguato.telegram_instances (instance_name, bot_token_enc)
              SELECT ins.instance_name,
                     encode(pgp_sym_encrypt($4::text, $5::text, 'cipher-algo=aes256'), 'base64')
              FROM ins
              RETURNING instance_name]],
            user.id, instance_name, max_instances, body.token, secret
        )
    else
        -- Atomic insert: check limit + uniqueness in one query
        ins_res, ins_err = db.query(
            [[INSERT INTO taguato.user_instances (user_id, instance_name, channel_type)
              SELECT $1, $2, 'whatsapp'
              WHERE (SELECT COUNT(*) FROM taguato.user_instances WHERE user_id = $1) < $3
              ON CONFLICT (instance_name) DO NOTHING
              RETURNING id]],
            user.id, instance_name, max_instances
        )
    end

    if not ins_res or #ins_res == 0 then
        -- Determine if it was a limit issue or a duplicate name
        local existing = db.query(
            "SELECT user_id FROM taguato.user_instances WHERE instance_name = $1",
            instance_name
        )
        if existing and #existing > 0 then
            json.respond(409, { error = "Instance name already in use" })
        else
            local count = count_user_instances()
            json.respond(403, {
                error = "Instance limit reached",
                current = count,
                max = user.max_instances
            })
        end
        return
    end

    if channel_type == "telegram" then
        json.respond(201, {
            message = "Instance created",
            channel_type = "telegram",
            instance_name = instance_name,
        })
        return
    end

    -- WhatsApp instance: proxy to Evolution API
    ngx.req.set_body_data(json.encode(body))
    ngx.req.set_header("apikey", os.getenv("AUTHENTICATION_API_KEY"))
    return
end

-- ============ INSTANCE DELETE ============
local delete_instance = uri:match("^/instance/delete/([^/]+)$")
if delete_instance and method == "DELETE" then
    if not is_admin and not user_owns_instance(delete_instance) then
        json.respond(403, { error = "You don't own this instance" })
        return
    end

    local channel_type = get_instance_channel_type(delete_instance) or "whatsapp"

    if is_admin then
        db.query(
            "DELETE FROM taguato.user_instances WHERE instance_name = $1",
            delete_instance
        )
    else
        db.query(
            "DELETE FROM taguato.user_instances WHERE user_id = $1 AND instance_name = $2",
            user.id, delete_instance
        )
    end

    if channel_type == "telegram" then
        json.respond(200, { message = "Instance deleted", instance = delete_instance })
        return
    end

    ngx.req.set_header("apikey", os.getenv("AUTHENTICATION_API_KEY"))
    return
end

-- Telegram connection state stub (bots are always "open" from the panel perspective)
local conn_state_instance = uri:match("^/instance/connectionState/([^/]+)$")
if conn_state_instance and method == "GET" then
    local channel_type = get_instance_channel_type(conn_state_instance) or "whatsapp"
    if channel_type == "telegram" then
        if not is_admin and not user_owns_instance(conn_state_instance) then
            json.respond(403, { error = "You don't own this instance" })
            return
        end
        json.respond(200, { instance = { instanceName = conn_state_instance, state = "open" } })
        return
    end
end

-- ============ FETCH INSTANCES (needs response filtering) ============
if uri == "/instance/fetchInstances" and method == "GET" then
    -- Evolution API may gzip the response if Accept-Encoding is forwarded.
    -- Our body_filter needs plain JSON to merge/filter instances.
    ngx.req.set_header("Accept-Encoding", "identity")
    ngx.req.set_header("apikey", os.getenv("AUTHENTICATION_API_KEY"))
    ngx.ctx.merge_telegram_instances = true
    if is_admin then
        ngx.ctx.telegram_scope = "all"
        ngx.ctx.telegram_instances = db.query(
            [[SELECT instance_name FROM taguato.user_instances
              WHERE channel_type = 'telegram'
              ORDER BY created_at DESC]]
        ) or {}
    else
        ngx.ctx.filter_instances = true
        ngx.ctx.user_instances = get_user_instance_names()
        ngx.ctx.telegram_scope = "user"
        ngx.ctx.telegram_user_id = user.id
        ngx.ctx.telegram_instances = db.query(
            [[SELECT instance_name FROM taguato.user_instances
              WHERE user_id = $1 AND channel_type = 'telegram'
              ORDER BY created_at DESC]],
            user.id
        ) or {}
    end
    return
end

-- ============ INSTANCE-SPECIFIC OPERATIONS ============
local instance_name = extract_instance_from_uri()
if instance_name then
    if not is_admin and not user_owns_instance(instance_name) then
        json.respond(403, { error = "You don't own this instance" })
        return
    end

    ngx.req.set_header("apikey", os.getenv("AUTHENTICATION_API_KEY"))
    return
end

-- ============ DEFAULT: proxy with API key ============
ngx.req.set_header("apikey", os.getenv("AUTHENTICATION_API_KEY"))
