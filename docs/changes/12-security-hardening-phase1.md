# 12 - Security Hardening Phase 1

**Estado:** Completado
**Fecha:** 2026-02-17

## Objetivo

Resolver los 10 items pendientes del issue #1 de seguridad (5 criticos + 5 alta severidad) que no fueron cubiertos en el commit anterior (`95e41c2`).

## Archivos modificados

| Archivo | Cambios |
|---------|---------|
| `db/seed-admin.sh` | SQL injection fix: heredoc sin interpolacion + psql -v variables |
| `gateway/nginx.conf` | Security headers via Lua, CORS configurable, trusted proxy RFC 1918, `env CORS_ORIGIN` |
| `gateway/lua/panel_auth.lua` | Invalidar sesiones al cambiar password + audit log |
| `gateway/lua/rate_limit.lua` | Shared dict fallback cuando Redis no disponible |
| `gateway/panel/js/api.js` | localStorage -> sessionStorage para tokens |
| `docker-compose.yml` | Resource limits en 4 servicios, Redis healthcheck sin password visible, CORS_ORIGIN env |
| `.env.example` | CORS_ORIGIN simplificado con documentacion |

## Detalle de cambios

### 1. SQL Injection en seed-admin.sh
- Heredoc cambiado de `EOSQL` (interpolado) a `'EOSQL'` (literal)
- Variables pasadas via `psql -v admin_user=... -v admin_pass=...`
- Dentro del bloque PL/pgSQL se usan `:'admin_user'` y `:'admin_pass'` (psql escapa automaticamente)
- Elimina riesgo de inyeccion si ADMIN_PASSWORD contiene comillas o caracteres SQL

### 2. Security Headers
- Headers de seguridad agregados via `header_filter_by_lua_block` en el server block:
  - `X-Content-Type-Options: nosniff`
  - `X-Frame-Options: DENY`
  - `X-XSS-Protection: 1; mode=block`
  - `Referrer-Policy: strict-origin-when-cross-origin`
  - `Strict-Transport-Security: max-age=31536000; includeSubDomains`
- Usando Lua block en vez de `add_header` para heredar correctamente a todos los locations

### 3. CORS configurable
- `Access-Control-Allow-Origin` ahora lee de `CORS_ORIGIN` env var (default `*`)
- `env CORS_ORIGIN;` en nginx.conf para exponerla a Lua
- Variable pasada via docker-compose.yml
- `.env.example` actualizado con documentacion

### 4. IP de reverse proxy
- Reemplazado `set_real_ip_from 10.100.0.9` (IP hardcodeada) por rangos RFC 1918:
  - `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`
- Cambiado `real_ip_header` de `X-Real-IP` a `X-Forwarded-For` (estandar)
- Cubre cualquier red Docker sin necesidad de conocer la IP exacta

### 5. Invalidar sesiones al cambiar password
- Despues de UPDATE exitoso: `UPDATE taguato.sessions SET is_active = false WHERE user_id = $1`
- Audit log del evento `password_changed`
- Mensaje cambiado a "Password changed successfully. Please login again."
- Fuerza re-login en todos los dispositivos del usuario

### 6. Token storage: sessionStorage
- 6 reemplazos de `localStorage` a `sessionStorage` en `api.js`
- Afecta keys: `taguato_token` y `taguato_user`
- `taguato_theme` en `app.js` permanece en localStorage (no sensible)
- Cerrar tab/navegador elimina la sesion automaticamente

### 7. Resource limits en containers
- `deploy.resources.limits` agregados a los 4 servicios:
  - gateway: 1 CPU, 512M
  - api: 2 CPU, 2G (WhatsApp sessions son memory-heavy)
  - postgres: 1 CPU, 1G
  - redis: 0.5 CPU, 256M
- Previene que un servicio consuma todos los recursos del host

### 8. Rate limiting shared dict fallback
- Nueva funcion `check_shared_dict()` usa `ngx.shared.rate_limit_store` (ya declarado)
- Cuando Redis falla, el rate limiting sigue funcionando via shared dict
- Usa `dict:incr(key, 1, 0, 1)` con init=0 y TTL=1 segundo
- Log level cambiado de ERR a WARN para errores de Redis (no es critico con fallback)

### 9. Redis password en healthcheck
- Cambiado de `redis-cli -a <password> ping` a `REDISCLI_AUTH=<password> redis-cli ping`
- `REDISCLI_AUTH` como env var no aparece en `ps aux` (a diferencia del flag `-a`)

## Deploy

```bash
# Si CORS_ORIGIN no esta en .env, agregarlo (opcional, default *)
# echo 'CORS_ORIGIN=https://tudominio.com' >> .env

# Rebuild y restart
docker compose build gateway
docker compose up -d
```

**Notas:**
- Los usuarios del panel deberan re-loguearse (sessionStorage reemplaza localStorage)
- Si un usuario cambia su password, todas sus sesiones se invalidaran
- Los resource limits se aplican inmediatamente al reiniciar

## Verificacion

1. `docker compose build gateway` - compila sin errores
2. `docker compose up -d` - todos los servicios arrancan
3. `curl -I http://localhost/health` - verifica security headers presentes
4. `docker compose exec taguato-redis ps aux` - password no visible en procesos
5. `docker stats` - muestra resource limits aplicados
6. Panel: login funciona, cerrar tab pierde sesion (sessionStorage)
7. Cambiar password -> todas las sesiones invalidadas, fuerza re-login
8. Seed admin con password con comillas funciona correctamente
