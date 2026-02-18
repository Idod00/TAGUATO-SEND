-- Audit log module
-- Helper function to record audit events + GET /admin/audit endpoint

local db = require "init"
local json = require "json"
local cjson = require "cjson"

local _M = {}

local empty_array_mt = cjson.empty_array_mt
local function as_array(t)
    if t == nil or (type(t) == "table" and #t == 0) then
        return setmetatable({}, empty_array_mt)
    end
    return t
end

-- Record an audit event (used by other modules)
function _M.log(user_id, username, action, resource_type, resource_id, details, ip_address)
    local details_json = nil
    if details then
        local ok, encoded = pcall(cjson.encode, details)
        if ok then details_json = encoded end
    end
    db.query(
        [[INSERT INTO taguato.audit_log (user_id, username, action, resource_type, resource_id, details, ip_address)
          VALUES ($1, $2, $3, $4, $5, $6::jsonb, $7)]],
        user_id, username, action, resource_type, resource_id, details_json, ip_address
    )
end

-- GET /admin/audit endpoint handler
function _M.handle()
    local user = ngx.ctx.user
    if not user or user.role ~= "admin" then
        json.respond(403, { error = "Admin access required" })
        return
    end

    if ngx.req.get_method() ~= "GET" then
        json.respond(405, { error = "Method not allowed" })
        return
    end

    local args = ngx.req.get_uri_args()
    local page = tonumber(args.page) or 1
    local limit = tonumber(args.limit) or 50
    if limit > 100 then limit = 100 end
    local offset = (page - 1) * limit

    local conditions = {}
    local vals = {}
    local idx = 0

    if args.action and args.action ~= "" then
        idx = idx + 1
        conditions[#conditions + 1] = "action = $" .. idx
        vals[idx] = args.action
    end

    if args.username and args.username ~= "" then
        idx = idx + 1
        conditions[#conditions + 1] = "username = $" .. idx
        vals[idx] = args.username
    end

    if args.resource_type and args.resource_type ~= "" then
        idx = idx + 1
        conditions[#conditions + 1] = "resource_type = $" .. idx
        vals[idx] = args.resource_type
    end

    if args.date_from and args.date_from ~= "" then
        idx = idx + 1
        conditions[#conditions + 1] = "created_at >= $" .. idx .. "::timestamp"
        vals[idx] = args.date_from
    end

    if args.date_to and args.date_to ~= "" then
        idx = idx + 1
        conditions[#conditions + 1] = "created_at <= $" .. idx .. "::timestamp"
        vals[idx] = args.date_to
    end

    local where = ""
    if #conditions > 0 then
        where = " WHERE " .. table.concat(conditions, " AND ")
    end

    -- Count
    local count_sql = "SELECT COUNT(*) as total FROM taguato.audit_log" .. where
    local count_res
    if #vals > 0 then
        count_res = db.query(count_sql, unpack(vals))
    else
        count_res = db.query(count_sql)
    end
    local total = 0
    if count_res and #count_res > 0 then
        total = tonumber(count_res[1].total) or 0
    end

    -- Fetch
    idx = idx + 1
    vals[idx] = limit
    idx = idx + 1
    vals[idx] = offset

    local data_sql = "SELECT id, user_id, username, action, resource_type, resource_id, details, ip_address, created_at" ..
                     " FROM taguato.audit_log" .. where ..
                     " ORDER BY created_at DESC LIMIT $" .. (idx - 1) .. " OFFSET $" .. idx

    local res = db.query(data_sql, unpack(vals))

    -- Parse JSONB details
    if res then
        for _, row in ipairs(res) do
            if row.details and type(row.details) == "string" then
                local ok, parsed = pcall(cjson.decode, row.details)
                if ok then row.details = parsed end
            end
        end
    end

    json.respond(200, {
        logs = as_array(res),
        total = total,
        page = page,
        limit = limit,
        pages = math.ceil(total / limit),
    })
end

return _M
