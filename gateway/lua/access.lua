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

-- Admin bypasses all instance filtering
if user.role == "admin" then
    ngx.req.set_header("apikey", os.getenv("AUTHENTICATION_API_KEY"))
    return
end

local method = ngx.req.get_method()
local uri = ngx.var.uri

-- Helper: check if user owns an instance
local function user_owns_instance(instance_name)
    local res = db.query(
        "SELECT id FROM taguato.user_instances WHERE user_id = $1 AND instance_name = $2",
        user.id, instance_name
    )
    return res and #res > 0
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

-- ============ INSTANCE CREATE ============
if uri == "/instance/create" and method == "POST" then
    local body, err = json.read_body()
    if not body or not body.instanceName then
        json.respond(400, { error = "instanceName is required" })
        return
    end

    local instance_name = body.instanceName

    -- Validate instance name format
    local validate = require "validate"
    local name_ok, name_err = validate.validate_instance_name(instance_name)
    if not name_ok then
        json.respond(400, { error = name_err })
        return
    end

    -- Atomic insert: check limit + uniqueness in one query
    local ins_res, ins_err = db.query(
        [[INSERT INTO taguato.user_instances (user_id, instance_name)
          SELECT $1, $2
          WHERE (SELECT COUNT(*) FROM taguato.user_instances WHERE user_id = $1) < $3
          ON CONFLICT (instance_name) DO NOTHING
          RETURNING id]],
        user.id, instance_name, user.max_instances
    )

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

    -- Re-set body since we consumed it
    ngx.req.set_body_data(json.encode(body))
    ngx.req.set_header("apikey", os.getenv("AUTHENTICATION_API_KEY"))
    return
end

-- ============ INSTANCE DELETE ============
local delete_instance = uri:match("^/instance/delete/([^/]+)$")
if delete_instance and method == "DELETE" then
    if not user_owns_instance(delete_instance) then
        json.respond(403, { error = "You don't own this instance" })
        return
    end

    db.query(
        "DELETE FROM taguato.user_instances WHERE user_id = $1 AND instance_name = $2",
        user.id, delete_instance
    )

    ngx.req.set_header("apikey", os.getenv("AUTHENTICATION_API_KEY"))
    return
end

-- ============ FETCH INSTANCES (needs response filtering) ============
if uri == "/instance/fetchInstances" and method == "GET" then
    ngx.req.set_header("apikey", os.getenv("AUTHENTICATION_API_KEY"))
    ngx.ctx.filter_instances = true
    ngx.ctx.user_instances = get_user_instance_names()
    return
end

-- ============ INSTANCE-SPECIFIC OPERATIONS ============
local instance_name = extract_instance_from_uri()
if instance_name then
    if not user_owns_instance(instance_name) then
        json.respond(403, { error = "You don't own this instance" })
        return
    end

    ngx.req.set_header("apikey", os.getenv("AUTHENTICATION_API_KEY"))
    return
end

-- ============ DEFAULT: proxy with API key ============
ngx.req.set_header("apikey", os.getenv("AUTHENTICATION_API_KEY"))
