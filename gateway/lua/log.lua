-- Structured logging helper
-- Emits JSON-formatted log lines via ngx.log
local cjson = require "cjson"

local _M = {}

local function emit(level, module, msg, data)
    local entry = {
        module = module,
        msg = msg,
    }
    if data and type(data) == "table" then
        for k, v in pairs(data) do
            entry[k] = v
        end
    end
    local ok, json_str = pcall(cjson.encode, entry)
    if ok then
        ngx.log(level, json_str)
    else
        ngx.log(level, module, ": ", msg)
    end
end

function _M.info(module, msg, data)
    emit(ngx.INFO, module, msg, data)
end

function _M.warn(module, msg, data)
    emit(ngx.WARN, module, msg, data)
end

function _M.err(module, msg, data)
    emit(ngx.ERR, module, msg, data)
end

return _M
