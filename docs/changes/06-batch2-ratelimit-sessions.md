# 06 - Batch 2: Rate Limiting por Usuario + Sesiones

**Estado:** Completado
**Commit:** `3944940`

## Objetivo
Rate limiting configurable por usuario y gestion de sesiones activas.

## Archivos creados/modificados
- `gateway/lua/sessions.lua` - **Nuevo** - CRUD de sesiones (user + admin)
- `gateway/nginx.conf` - Locations para `/api/sessions` y `/admin/sessions`
- `gateway/panel/index.html` - Seccion de sesiones
- `gateway/panel/js/api.js` - Funciones de sesiones
- `gateway/panel/js/app.js` - Logica de sesiones, revocacion
- `db/init.sql` - Tabla `sessions`, columna `rate_limit` en users

## Cambios clave
- Rate limit por usuario (columna `rate_limit` en users, NULL = sin limite)
- Tabla de sesiones con tracking de IP, user agent, ultima actividad
- Admin puede ver y revocar todas las sesiones
- Users pueden ver y revocar sus propias sesiones
