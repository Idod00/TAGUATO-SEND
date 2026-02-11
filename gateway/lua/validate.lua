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

return _M
