-- SMTP wrapper using lua-resty-mail
local _M = {}

local function get_config()
    return {
        host = os.getenv("SMTP_HOST"),
        port = tonumber(os.getenv("SMTP_PORT")) or 587,
        username = os.getenv("SMTP_USER"),
        password = os.getenv("SMTP_PASSWORD"),
        from = os.getenv("SMTP_FROM"),
        secure = os.getenv("SMTP_SECURE") or "tls",
    }
end

function _M.is_configured()
    local cfg = get_config()
    return cfg.host and cfg.host ~= ""
        and cfg.from and cfg.from ~= ""
end

function _M.send(to, subject, text_body, html_body)
    local cfg = get_config()
    if not cfg.host or cfg.host == "" then
        return nil, "SMTP not configured"
    end

    local mail = require "resty.mail"

    local mailer_opts = {
        host = cfg.host,
        port = cfg.port,
        domain = cfg.host,
    }

    -- Configure security
    if cfg.secure == "ssl" then
        mailer_opts.ssl = true
        mailer_opts.starttls = false
    elseif cfg.secure == "tls" then
        mailer_opts.ssl = false
        mailer_opts.starttls = true
    else
        mailer_opts.ssl = false
        mailer_opts.starttls = false
    end

    -- Configure auth if credentials provided
    if cfg.username and cfg.username ~= "" then
        mailer_opts.auth_type = "plain"
        mailer_opts.username = cfg.username
        mailer_opts.password = cfg.password or ""
    end

    local mailer, err = mail.new(mailer_opts)
    if not mailer then
        return nil, "Failed to create mailer: " .. (err or "unknown")
    end

    local message = {
        from = cfg.from,
        to = { to },
        subject = subject,
    }

    if html_body then
        message.html = html_body
    end
    if text_body then
        message.text = text_body
    end

    local ok, send_err = mailer:send(message)
    if not ok then
        return nil, "Failed to send email: " .. (send_err or "unknown")
    end

    return true
end

return _M
