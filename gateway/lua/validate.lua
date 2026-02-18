-- Shared validation module
local _M = {}

-- Validate password: min 8 chars, 1 uppercase, 1 lowercase, 1 number
function _M.validate_password(pw)
    if not pw or type(pw) ~= "string" then
        return false, "Password is required"
    end
    if #pw < 8 then
        return false, "Password must be at least 8 characters"
    end
    if not pw:match("[A-Z]") then
        return false, "Password must contain at least one uppercase letter"
    end
    if not pw:match("[a-z]") then
        return false, "Password must contain at least one lowercase letter"
    end
    if not pw:match("[0-9]") then
        return false, "Password must contain at least one number"
    end
    return true
end

-- Validate phone number: 8-20 digits only
function _M.validate_phone(num)
    if not num or type(num) ~= "string" then
        return false, "Phone number is required"
    end
    local digits = num:gsub("%s+", "")
    if not digits:match("^%d+$") then
        return false, "Phone number must contain only digits"
    end
    if #digits < 8 or #digits > 20 then
        return false, "Phone number must be between 8 and 20 digits"
    end
    return true
end

-- Validate string: type, min and max length
function _M.validate_string(val, name, min_len, max_len)
    if not val or type(val) ~= "string" then
        return false, name .. " is required"
    end
    local len = #val
    if min_len and len < min_len then
        return false, name .. " must be at least " .. min_len .. " characters"
    end
    if max_len and len > max_len then
        return false, name .. " must be at most " .. max_len .. " characters"
    end
    return true
end

-- Validate positive integer
function _M.validate_positive_int(val, name)
    if val == nil then
        return false, name .. " is required"
    end
    local num = tonumber(val)
    if not num or num ~= math.floor(num) or num < 1 then
        return false, name .. " must be a positive integer"
    end
    return true
end

-- Validate username: 3-50 chars, alphanumeric + underscore
function _M.validate_username(val)
    if not val or type(val) ~= "string" then
        return false, "Username is required"
    end
    if #val < 3 or #val > 50 then
        return false, "Username must be between 3 and 50 characters"
    end
    if not val:match("^[a-zA-Z0-9_]+$") then
        return false, "Username must contain only letters, numbers and underscores"
    end
    return true
end

-- Validate instance name: 1-100 chars, alphanumeric + underscore + hyphen, must start with alphanumeric
function _M.validate_instance_name(val)
    if not val or type(val) ~= "string" then
        return false, "Instance name is required"
    end
    if #val < 1 or #val > 100 then
        return false, "Instance name must be between 1 and 100 characters"
    end
    if not val:match("^[a-zA-Z0-9][a-zA-Z0-9_%-]*$") then
        return false, "Instance name must start with a letter or number and contain only letters, numbers, underscores and hyphens"
    end
    return true
end

-- Validate webhook URL: must be external (reject internal IPs, Docker hosts, metadata)
function _M.validate_webhook_url(url)
    if not url or type(url) ~= "string" then
        return false, "webhook_url is required"
    end
    if not url:match("^https?://") then
        return false, "webhook_url must start with http:// or https://"
    end

    -- Extract hostname from URL
    local host = url:match("^https?://([^/:]+)")
    if not host then
        return false, "Invalid webhook URL"
    end

    local host_lower = host:lower()

    -- Block localhost variants
    if host_lower == "localhost" or host_lower == "127.0.0.1" or host_lower == "::1"
        or host_lower == "0.0.0.0" then
        return false, "webhook_url cannot point to localhost"
    end

    -- Block Docker internal hostnames
    local blocked_hosts = {
        ["taguato-api"] = true, ["taguato-postgres"] = true,
        ["taguato-redis"] = true, ["taguato-gateway"] = true,
    }
    if blocked_hosts[host_lower] then
        return false, "webhook_url cannot point to internal services"
    end

    -- Block cloud metadata endpoints
    if host_lower == "169.254.169.254" or host_lower == "metadata.google.internal" then
        return false, "webhook_url cannot point to cloud metadata"
    end

    -- Block RFC1918 private IPs and link-local
    local ip_parts = { host:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$") }
    if #ip_parts == 4 then
        local a, b = tonumber(ip_parts[1]), tonumber(ip_parts[2])
        if a == 10                                    -- 10.0.0.0/8
            or (a == 172 and b >= 16 and b <= 31)     -- 172.16.0.0/12
            or (a == 192 and b == 168)                -- 192.168.0.0/16
            or (a == 169 and b == 254)                -- 169.254.0.0/16 link-local
            or a == 127 then                          -- 127.0.0.0/8
            return false, "webhook_url cannot point to private/internal IP addresses"
        end
    end

    return true
end

-- Validate enum value against allowed list
function _M.validate_enum(val, name, allowed)
    if not val or type(val) ~= "string" then
        return false, name .. " is required"
    end
    for _, v in ipairs(allowed) do
        if val == v then return true end
    end
    return false, name .. " must be one of: " .. table.concat(allowed, ", ")
end

-- Validate email: basic pattern, max 255 chars
function _M.validate_email(val)
    if not val or type(val) ~= "string" then
        return false, "Email is required"
    end
    if #val > 255 then
        return false, "Email must be at most 255 characters"
    end
    if not val:match("^[%w%._%+%-]+@[%w%.%-]+%.[%a]+$") then
        return false, "Invalid email format"
    end
    return true
end

return _M
