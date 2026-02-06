-- PostgreSQL connection pool via pgmoon
local pgmoon = require "pgmoon"

local _M = {}

local pg_config = {
    host = os.getenv("PG_HOST") or "taguato-postgres",
    port = tonumber(os.getenv("PG_PORT")) or 5432,
    database = os.getenv("PG_DATABASE") or "evolution",
    user = os.getenv("PG_USER") or "taguato",
    password = os.getenv("PG_PASSWORD") or "taguato_secret",
}

function _M.get_db()
    local pg = pgmoon.new(pg_config)
    local ok, err = pg:connect()
    if not ok then
        ngx.log(ngx.ERR, "PostgreSQL connect failed: ", err)
        return nil, err
    end
    return pg
end

function _M.query(sql, ...)
    local pg, err = _M.get_db()
    if not pg then
        return nil, err
    end

    -- Escape parameters and build query by replacing $1, $2, etc.
    local args = {...}
    if #args > 0 then
        local escaped = {}
        for i, v in ipairs(args) do
            if v == nil then
                escaped[i] = "NULL"
            elseif type(v) == "number" then
                escaped[i] = tostring(v)
            elseif type(v) == "boolean" then
                escaped[i] = v and "TRUE" or "FALSE"
            else
                escaped[i] = pg:escape_literal(tostring(v))
            end
        end

        -- Build query by splitting on $N placeholders
        local parts = {}
        local pos = 1
        while pos <= #sql do
            local s, e, num = sql:find("%$(%d+)", pos)
            if not s then
                parts[#parts + 1] = sql:sub(pos)
                break
            end
            parts[#parts + 1] = sql:sub(pos, s - 1)
            local idx = tonumber(num)
            parts[#parts + 1] = escaped[idx] or ("$" .. num)
            pos = e + 1
        end
        sql = table.concat(parts)
    end

    local res, query_err = pg:query(sql)
    pg:keepalive(10000, 10)

    if not res then
        ngx.log(ngx.ERR, "Query failed: ", query_err, " SQL: ", sql)
        return nil, query_err
    end

    return res
end

return _M
