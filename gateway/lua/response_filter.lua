-- Response body filter for fetchInstances
-- Filters the response from Evolution API to only include user's instances

local cjson = require "cjson"

if not ngx.ctx.filter_instances then
    return
end

local user_instances = ngx.ctx.user_instances
if not user_instances then
    return
end

-- Collect chunks
local chunk = ngx.arg[1]
local eof = ngx.arg[2]

if not ngx.ctx.response_body then
    ngx.ctx.response_body = ""
end

if chunk then
    ngx.ctx.response_body = ngx.ctx.response_body .. chunk
end

if not eof then
    -- Not done yet, suppress output until we have the full body
    ngx.arg[1] = nil
    return
end

-- Full body received, filter it
local body = ngx.ctx.response_body
local ok, data = pcall(cjson.decode, body)

if not ok or type(data) ~= "table" then
    -- Can't parse, pass through as-is
    ngx.arg[1] = body
    return
end

-- Evolution API v2 returns array with "name" field per instance
local filtered = {}
for _, instance in ipairs(data) do
    local name = instance.name
    if name and user_instances[name] then
        filtered[#filtered + 1] = instance
    end
end

ngx.arg[1] = cjson.encode(filtered)
