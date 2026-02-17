-- Luacheck configuration for OpenResty/ngx_lua project
-- Reference: https://luacheck.readthedocs.io/

-- Use LuaJIT standard (supports goto, bit operations, etc.)
std = "luajit"

-- OpenResty globals (read-write)
globals = {
    "ngx",
}

-- Read-only globals
read_globals = {
    "ndk",
}

-- Ignore common patterns in this codebase
ignore = {
    "211",  -- unused local variable (idiomatic in Lua multi-return: local ok, err = ...)
    "212",  -- unused argument (common in callbacks)
    "213",  -- unused loop variable (for _, v in ipairs)
    "311",  -- value assigned to variable but unused (reassignment patterns)
    "631",  -- line too long
}

-- Max line length (relaxed for embedded SQL strings)
max_line_length = 200

-- Allow top-level variables used across file (script-style Lua files)
allow_defined_top = true
