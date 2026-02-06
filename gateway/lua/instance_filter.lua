-- Instance filtering middleware
-- Runs after auth.lua, before proxying to Evolution API.
-- Controls instance access based on user ownership.

local db = require "init"
local json = require "json"

local user = ngx.ctx.user
if not user then
    json.respond(401, { error = "Not authenticated" })
    return
end

-- Admin bypasses all instance filtering
if user.role == "admin" then
    -- Set the real Evolution API key for proxying
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

-- Helper: get list of user's instance names
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

-- Extract instance name from URI patterns like:
--   /instance/connect/my-instance
--   /message/sendText/my-instance
--   /webhook/set/my-instance
local function extract_instance_from_uri()
    -- Match patterns: /something/action/instance-name
    local instance = uri:match("^/[^/]+/[^/]+/([^/]+)$")
    return instance
end

-- ============ INSTANCE CREATE ============
if uri == "/instance/create" and method == "POST" then
    -- Check instance limit
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

    -- Read body to get instanceName
    local body, err = json.read_body()
    if not body or not body.instanceName then
        json.respond(400, { error = "instanceName is required" })
        return
    end

    local instance_name = body.instanceName

    -- Check if instance name is already taken by another user
    local existing = db.query(
        "SELECT user_id FROM taguato.user_instances WHERE instance_name = $1",
        instance_name
    )
    if existing and #existing > 0 then
        json.respond(409, { error = "Instance name already in use" })
        return
    end

    -- Register instance ownership
    local res, err = db.query(
        "INSERT INTO taguato.user_instances (user_id, instance_name) VALUES ($1, $2)",
        user.id, instance_name
    )

    if not res then
        json.respond(500, { error = "Failed to register instance" })
        return
    end

    -- Re-set the body (since we consumed it)
    ngx.req.set_body_data(json.encode(body))

    -- Set the real API key and let it proxy
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

    -- Remove ownership record
    db.query(
        "DELETE FROM taguato.user_instances WHERE user_id = $1 AND instance_name = $2",
        user.id, delete_instance
    )

    ngx.req.set_header("apikey", os.getenv("AUTHENTICATION_API_KEY"))
    return
end

-- ============ FETCH INSTANCES ============
if uri == "/instance/fetchInstances" and method == "GET" then
    -- We need to proxy the request, then filter the response
    -- Use a subrequest approach: proxy first, then filter
    ngx.req.set_header("apikey", os.getenv("AUTHENTICATION_API_KEY"))

    -- Store the user's instance names for the response filter
    ngx.ctx.filter_instances = true
    ngx.ctx.user_instances = get_user_instance_names()
    return
end

-- ============ INSTANCE-SPECIFIC OPERATIONS ============
-- Routes that include instance name in URI
local instance_name = extract_instance_from_uri()
if instance_name then
    if not user_owns_instance(instance_name) then
        json.respond(403, { error = "You don't own this instance" })
        return
    end

    ngx.req.set_header("apikey", os.getenv("AUTHENTICATION_API_KEY"))
    return
end

-- ============ OTHER ROUTES ============
-- For any other route, set the API key and proxy
-- Routes without instance names (like /instance/fetchInstances handled above)
ngx.req.set_header("apikey", os.getenv("AUTHENTICATION_API_KEY"))
