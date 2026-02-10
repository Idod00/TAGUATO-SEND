-- Combined access handler: auth + instance filtering
-- This runs both auth.lua and instance_filter.lua logic in sequence,
-- since nginx only allows one access_by_lua_file per location.

-- Step 1: Authenticate
local db = require "init"
local json = require "json"

local token = ngx.req.get_headers()["apikey"]

if not token or token == "" then
    json.respond(401, { error = "Missing apikey header" })
    return
end

local res, err = db.query(
    "SELECT id, username, role, max_instances, is_active, rate_limit FROM taguato.users WHERE api_token = $1 LIMIT 1",
    token
)

if not res or #res == 0 then
    json.respond(401, { error = "Invalid API token" })
    return
end

local user = res[1]

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
    if user.max_instances > 0 then
        local count = count_user_instances()
        if count >= user.max_instances then
            json.respond(403, {
                error = "Instance limit reached",
                current = count,
                max = user.max_instances
            })
            return
        end
    end

    local body, err = json.read_body()
    if not body or not body.instanceName then
        json.respond(400, { error = "instanceName is required" })
        return
    end

    local instance_name = body.instanceName

    -- Check if instance name is already taken
    local existing = db.query(
        "SELECT user_id FROM taguato.user_instances WHERE instance_name = $1",
        instance_name
    )
    if existing and #existing > 0 then
        json.respond(409, { error = "Instance name already in use" })
        return
    end

    -- Register ownership
    local ins_res, ins_err = db.query(
        "INSERT INTO taguato.user_instances (user_id, instance_name) VALUES ($1, $2)",
        user.id, instance_name
    )
    if not ins_res then
        json.respond(500, { error = "Failed to register instance" })
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
