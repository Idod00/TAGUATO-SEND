-- Log rotation worker
-- Rotates nginx access and error logs inside the container
-- Keeps last 7 rotated files, signals nginx to reopen log files

local _M = {}

function _M.rotate()
    local log = require "log"
    local log_dir = "/usr/local/openresty/nginx/logs"
    local max_rotated = 7

    local files = { "access.log", "error.log" }

    for _, filename in ipairs(files) do
        local path = log_dir .. "/" .. filename

        -- Check if file exists and has content
        local f = io.open(path, "r")
        if f then
            local size = f:seek("end")
            f:close()

            -- Only rotate if file is > 10MB
            if size and size > 10 * 1024 * 1024 then
                -- Rotate: rename current to .1, shift older ones
                for i = max_rotated, 1, -1 do
                    local old = path .. "." .. i
                    local new = path .. "." .. (i + 1)
                    os.rename(old, new)
                end
                os.rename(path, path .. ".1")

                -- Delete oldest if exceeds max
                os.remove(path .. "." .. (max_rotated + 1))
            end
        end
    end

    -- Signal nginx to reopen log files (creates fresh files)
    local ok = os.execute("/usr/local/openresty/bin/openresty -s reopen 2>/dev/null")
    if ok then
        log.info("logrotate_worker", "log rotation completed")
    else
        log.warn("logrotate_worker", "failed to signal nginx reopen")
    end
end

return _M
