-- Shared HTML email templates for TAGUATO-SEND
local _M = {}

local function base_html(title, body_content)
    return [[<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>]] .. title .. [[</title>
</head>
<body style="margin:0;padding:0;background-color:#f4f5f7;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color:#f4f5f7;padding:32px 16px;">
<tr><td align="center">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:600px;background-color:#ffffff;border-radius:8px;overflow:hidden;box-shadow:0 2px 8px rgba(0,0,0,0.08);">

<!-- Header -->
<tr><td style="background-color:#1a1a2e;padding:24px 32px;text-align:center;">
<h1 style="margin:0;color:#ffffff;font-size:22px;font-weight:600;letter-spacing:1px;">TAGUATO-SEND</h1>
</td></tr>

<!-- Body -->
<tr><td style="padding:32px;">
]] .. body_content .. [[
</td></tr>

<!-- Footer -->
<tr><td style="padding:16px 32px;background-color:#f8f9fa;border-top:1px solid #e9ecef;text-align:center;">
<p style="margin:0;color:#868e96;font-size:12px;">Este es un mensaje automatico de TAGUATO-SEND. No responda a este correo.</p>
</td></tr>

</table>
</td></tr>
</table>
</body>
</html>]]
end

function _M.recovery_code(code)
    local subject = "Codigo de recuperacion - TAGUATO-SEND"

    local text = "Su codigo de recuperacion es: " .. code
        .. "\n\nEste codigo expira en 15 minutos."
        .. "\nSi usted no solicito esto, ignore este correo."

    local body = [[
<h2 style="margin:0 0 16px;color:#1a1a2e;font-size:20px;">Recuperacion de contrasena</h2>
<p style="margin:0 0 24px;color:#495057;font-size:15px;line-height:1.6;">
Se solicito un codigo para restablecer su contrasena. Ingrese el siguiente codigo:</p>
<div style="text-align:center;margin:0 0 24px;">
<div style="display:inline-block;background-color:#f1f3f5;border:2px dashed #dee2e6;border-radius:8px;padding:16px 32px;">
<span style="font-family:'Courier New',Courier,monospace;font-size:32px;font-weight:700;letter-spacing:8px;color:#1a1a2e;">]] .. code .. [[</span>
</div>
</div>
<p style="margin:0 0 8px;color:#868e96;font-size:13px;">Este codigo expira en <strong>15 minutos</strong>.</p>
<p style="margin:0;color:#e03131;font-size:13px;font-weight:600;">No comparta este codigo con nadie.</p>
]]

    local html = base_html(subject, body)
    return subject, text, html
end

function _M.admin_reset_code(code, admin_username)
    local subject = "Restablecimiento de contrasena - TAGUATO-SEND"

    local text = "Un administrador (" .. admin_username .. ") ha solicitado restablecer su contrasena."
        .. "\nSu codigo de recuperacion es: " .. code
        .. "\n\nEste codigo expira en 15 minutos."
        .. "\nSi no esperaba este correo, contacte a su administrador."

    local body = [[
<h2 style="margin:0 0 16px;color:#1a1a2e;font-size:20px;">Restablecimiento de contrasena</h2>
<p style="margin:0 0 24px;color:#495057;font-size:15px;line-height:1.6;">
Un administrador (<strong>]] .. admin_username .. [[</strong>) ha solicitado restablecer su contrasena.
Ingrese el siguiente codigo para completar el proceso:</p>
<div style="text-align:center;margin:0 0 24px;">
<div style="display:inline-block;background-color:#f1f3f5;border:2px dashed #dee2e6;border-radius:8px;padding:16px 32px;">
<span style="font-family:'Courier New',Courier,monospace;font-size:32px;font-weight:700;letter-spacing:8px;color:#1a1a2e;">]] .. code .. [[</span>
</div>
</div>
<p style="margin:0 0 8px;color:#868e96;font-size:13px;">Este codigo expira en <strong>15 minutos</strong>.</p>
<p style="margin:0;color:#e03131;font-size:13px;font-weight:600;">No comparta este codigo con nadie.</p>
]]

    local html = base_html(subject, body)
    return subject, text, html
end

return _M
