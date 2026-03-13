-- TOTP (RFC 6238) - Time-based One-Time Password
-- Uses ngx.hmac_sha1 built into OpenResty/lua-nginx-module
-- Compatible with Google Authenticator, Authy, Microsoft Authenticator, Aegis, etc.

local _M = {}

local bit    = require "bit"
local bor    = bit.bor
local band   = bit.band
local lshift = bit.lshift
local rshift = bit.rshift

local BASE32 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

-- Encode binary string → base32 (no padding)
function _M.base32_encode(s)
    local result = {}
    local buf    = 0
    local bits   = 0
    for i = 1, #s do
        buf  = bor(lshift(buf, 8), string.byte(s, i))
        bits = bits + 8
        while bits >= 5 do
            bits = bits - 5
            local idx = band(rshift(buf, bits), 0x1F) + 1
            result[#result + 1] = BASE32:sub(idx, idx)
        end
    end
    if bits > 0 then
        local idx = band(lshift(buf, 5 - bits), 0x1F) + 1
        result[#result + 1] = BASE32:sub(idx, idx)
    end
    return table.concat(result)
end

-- Decode base32 → binary string (strips padding and spaces)
function _M.base32_decode(s)
    s = s:upper():gsub("[^A-Z2-7]", "")
    local result = {}
    local buf    = 0
    local bits   = 0
    for i = 1, #s do
        local val = BASE32:find(s:sub(i, i), 1, true)
        if not val then return nil end
        val  = val - 1
        buf  = bor(lshift(buf, 5), val)
        bits = bits + 5
        if bits >= 8 then
            bits = bits - 8
            result[#result + 1] = string.char(band(rshift(buf, bits), 0xFF))
        end
    end
    return table.concat(result)
end

-- Encode counter as 8-byte big-endian (handles up to 2^53 safely in LuaJIT doubles)
local function int_to_bytes8(n)
    local b = {}
    for i = 8, 1, -1 do
        b[i] = string.char(n % 256)
        n    = math.floor(n / 256)
    end
    return table.concat(b)
end

-- Generate a 6-digit TOTP code for the given base32 secret and unix timestamp
function _M.generate(secret, t)
    t = t or ngx.time()
    local key = _M.base32_decode(secret)
    if not key or #key == 0 then return nil end

    local counter = math.floor(t / 30)
    local msg     = int_to_bytes8(counter)
    local hmac    = ngx.hmac_sha1(key, msg)   -- 20 raw bytes

    -- Dynamic truncation (RFC 4226 §5.4)
    local offset = band(string.byte(hmac, 20), 0x0F)
    local b0 = string.byte(hmac, offset + 1)
    local b1 = string.byte(hmac, offset + 2)
    local b2 = string.byte(hmac, offset + 3)
    local b3 = string.byte(hmac, offset + 4)

    local code = bor(
        bor(lshift(band(b0, 0x7F), 24), lshift(b1, 16)),
        bor(lshift(b2, 8), b3)
    ) % 1000000

    return string.format("%06d", code)
end

-- Verify a code — accepts ±1 step (±30 s) to tolerate clock drift
function _M.verify(secret, code, t)
    if not code or type(code) ~= "string" or #code ~= 6 then return false end
    t = t or ngx.time()
    for step = -1, 1 do
        if _M.generate(secret, t + step * 30) == code then
            return true
        end
    end
    return false
end

return _M
