-- Response body filter for fetchInstances
-- Filters the response from Evolution API to only include user's instances
-- Uses table buffer instead of string concatenation for efficiency

local cjson = require "cjson"

if not ngx.ctx.filter_instances and not ngx.ctx.merge_telegram_instances then
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

local out = data

-- Optional: filter by ownership (non-admin users)
if ngx.ctx.filter_instances then
    local user_instances = ngx.ctx.user_instances
    if user_instances then
        local filtered = {}
        for _, instance in ipairs(data) do
            local name = instance.name
            if name and user_instances[name] then
                filtered[#filtered + 1] = instance
            end
        end
        out = filtered
    end
end

-- Optional: merge Telegram instances stored in DB (not backed by Evolution API)
if ngx.ctx.merge_telegram_instances then
    local rows = ngx.ctx.telegram_instances
    if type(rows) == "table" then
        for _, row in ipairs(rows) do
            local instance_name = row.instance_name or row
            out[#out + 1] = {
                name = instance_name,
                channelType = "telegram",
                integration = "TELEGRAM",
                instance = { instanceName = instance_name, state = "open" },
            }
        end
    end
end

ngx.arg[1] = cjson.encode(out)
