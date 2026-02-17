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

-- Get a DB connection cached in ngx.ctx for the duration of the request.
-- In timer context (workers), ngx.ctx is not available, so falls back to get_db().
function _M.get_db_cached()
    -- Timer context: no ngx.ctx available
    if not ngx.ctx then
        return _M.get_db()
    end
    if ngx.ctx._pg_conn then
        return ngx.ctx._pg_conn
    end
    local pg, err = _M.get_db()
    if not pg then
        return nil, err
    end
    ngx.ctx._pg_conn = pg
    return pg
end

-- Release the cached connection back to the pool (called from log_by_lua)
function _M.release()
    if ngx.ctx and ngx.ctx._pg_conn then
        ngx.ctx._pg_conn:keepalive(10000, 10)
        ngx.ctx._pg_conn = nil
    end
end

-- Transaction helpers (use cached connection so BEGIN/COMMIT share the same conn)
function _M.begin()
    local pg, err = _M.get_db_cached()
    if not pg then return nil, err end
    return pg:query("BEGIN")
end

function _M.commit()
    local pg, err = _M.get_db_cached()
    if not pg then return nil, err end
    return pg:query("COMMIT")
end

function _M.rollback()
    local pg, err = _M.get_db_cached()
    if not pg then return nil, err end
    return pg:query("ROLLBACK")
end

function _M.query(sql, ...)
    local pg, err = _M.get_db_cached()
    if not pg then
        return nil, err
    end

    -- Keep original SQL template (with $N placeholders) for safe error logging
    local sql_template = sql

    -- Escape parameters and build query by replacing $1, $2, etc.
    local args = {...}
    local nargs = select('#', ...)
    if nargs > 0 then
        local escaped = {}
        for i = 1, nargs do
            local v = args[i]
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
            parts[#parts + 1] = escaped[idx] or "NULL"
            pos = e + 1
        end
        sql = table.concat(parts)
    end

    local res, query_err = pg:query(sql)

    -- In timer context, return connection to pool immediately
    if not ngx.ctx or not ngx.ctx._pg_conn then
        pg:keepalive(10000, 10)
    end

    if not res then
        -- Log the template SQL (with placeholders) instead of expanded values
        local safe_sql = sql_template
        if #safe_sql > 200 then
            safe_sql = safe_sql:sub(1, 200) .. "..."
        end
        ngx.log(ngx.ERR, "Query failed: ", query_err, " SQL: ", safe_sql)
        return nil, query_err
    end

    return res
end

-- Redis connection helper with auth support
function _M.get_redis(timeout_ms)
    local redis = require "resty.redis"
    local red = redis:new()
    red:set_timeouts(timeout_ms or 3000, timeout_ms or 3000, timeout_ms or 3000)

    local redis_host = os.getenv("REDIS_HOST") or "taguato-redis"
    local redis_port = tonumber(os.getenv("REDIS_PORT")) or 6379

    local ok, err = red:connect(redis_host, redis_port)
    if not ok then
        return nil, err
    end

    local password = os.getenv("REDIS_PASSWORD")
    if password and password ~= "" then
        local auth_ok, auth_err = red:auth(password)
        if not auth_ok then
            red:close()
            return nil, "Redis auth failed: " .. (auth_err or "unknown")
        end
    end

    return red
end

return _M
