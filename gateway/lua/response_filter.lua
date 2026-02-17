-- Response body filter for fetchInstances
-- Filters the response from Evolution API to only include user's instances
-- Uses table buffer instead of string concatenation for efficiency

local cjson = require "cjson"

if not ngx.ctx.filter_instances then
    return
end

local user_instances = ngx.ctx.user_instances
if not user_instances then
    return
end

-- Collect chunks using table buffer (avoids O(n^2) string concat)
local chunk = ngx.arg[1]
local eof = ngx.arg[2]

if not ngx.ctx.response_chunks then
    ngx.ctx.response_chunks = {}
end

if chunk and chunk ~= "" then
    local chunks = ngx.ctx.response_chunks
    chunks[#chunks + 1] = chunk
end

if not eof then
    -- Not done yet, suppress output until we have the full body
    ngx.arg[1] = nil
    return
end

-- Full body received, filter it
local body = table.concat(ngx.ctx.response_chunks or {})
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
