-- JSON helpers using cjson (bundled with OpenResty)
local cjson = require "cjson"

local _M = {}

function _M.encode(data)
    return cjson.encode(data)
end

function _M.decode(str)
    local ok, data = pcall(cjson.decode, str)
    if not ok then
        return nil, "invalid JSON"
    end
    return data
end

function _M.respond(status, data)
    ngx.status = status
    ngx.header["Content-Type"] = "application/json"
    ngx.say(cjson.encode(data))
    ngx.exit(status)
end

function _M.read_body()
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    if not body then
        return nil, "empty body"
    end
    return _M.decode(body)
end

return _M
