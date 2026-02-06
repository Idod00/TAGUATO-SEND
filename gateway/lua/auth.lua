-- Authentication middleware
-- Reads apikey header, validates against taguato.users table,
-- sets ngx.ctx.user with user info for downstream handlers.

local db = require "init"
local json = require "json"

local token = ngx.req.get_headers()["apikey"]

if not token or token == "" then
    json.respond(401, { error = "Missing apikey header" })
    return
end

local res, err = db.query(
    "SELECT id, username, role, max_instances, is_active FROM taguato.users WHERE api_token = $1 LIMIT 1",
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

-- Store user context for downstream handlers
ngx.ctx.user = {
    id = user.id,
    username = user.username,
    role = user.role,
    max_instances = user.max_instances,
}
