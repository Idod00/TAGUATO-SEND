# 11 - Security Hardening

**Estado:** Completado
**Fecha:** 2026-02-17

## Objetivo

Resolver 6 problemas de prioridad alta que afectan seguridad y resiliencia del sistema.

## Archivos modificados

| Archivo | Cambios |
|---------|---------|
| `test.sh` | Token leido de env/`.env` en vez de hardcoded |
| `db/init.sql` | UNIQUE(instance_name) standalone |
| `gateway/lua/migrations_list.lua` | v4: unique constraint, v5: invalidar sesiones MD5 |
| `gateway/lua/access.lua` | INSERT atomico + validacion instanceName |
| `gateway/lua/validate.lua` | Nueva funcion `validate_instance_name` |
| `gateway/lua/panel_auth.lua` | SHA-256 en vez de MD5 para session hash |
| `gateway/lua/init.lua` | Helper `get_redis()` con auth |
| `gateway/lua/rate_limit.lua` | Usa `get_redis()` |
| `gateway/lua/uptime_worker.lua` | Redis auth inline |
| `gateway/lua/status_api.lua` | 3 conexiones Redis via `get_redis()` |
| `gateway/nginx.conf` | `env REDIS_PASSWORD` |
| `docker-compose.yml` | Ports PG/Redis comentados, `requirepass`, `REDIS_PASSWORD` |
| `.env.example` | `REDIS_PASSWORD`, ports comentados, `CACHE_REDIS_URI` actualizado |

## Detalle de cambios

### 1. Token hardcodeado en test.sh
- Se reemplazo el token admin hardcodeado por lectura desde variable de entorno o `.env`
- Validacion con `exit 1` si no se encuentra

### 2. Race condition en creacion de instancias
- Constraint `UNIQUE(instance_name)` standalone en schema (ademas del existente compuesto)
- Migracion v4 para instalaciones existentes
- INSERT atomico en `access.lua`: verifica limite y unicidad en una sola query
- Si falla, determina si fue por limite o nombre duplicado para mensaje correcto

### 3. PostgreSQL/Redis no expuestos por defecto
- Secciones `ports` de postgres y redis comentadas en `docker-compose.yml`
- Variables en `.env.example` comentadas con nota de debug

### 4. Redis requirepass
- `redis-server --requirepass` en docker-compose
- Healthcheck actualizado con `-a <password>`
- `REDIS_PASSWORD` pasado al gateway como env var
- Helper `get_redis()` en `init.lua` centraliza connect + auth + timeout
- `rate_limit.lua` y `status_api.lua` migrados a usar `get_redis()`
- `uptime_worker.lua` usa auth inline (no puede usar init.lua pool en timer context)

### 5. Validacion de instanceName
- Patron: `^[a-zA-Z0-9][a-zA-Z0-9_%-]*$`, longitud 1-100
- Se valida antes del INSERT en la seccion INSTANCE CREATE de `access.lua`

### 6. SHA-256 en vez de MD5 para sessions
- Helper `sha256_hex()` usando `resty.sha256` + `resty.string` (incluidos en OpenResty)
- Reemplaza `ngx.md5()` en login y `/auth/me`
- `token_hash VARCHAR(64)` encaja exacto con SHA-256 hex
- Migracion v5 invalida sesiones existentes (hash MD5 incompatible)

## Deploy

```bash
# Agregar REDIS_PASSWORD al .env existente
echo 'REDIS_PASSWORD=tu_password_seguro' >> .env

# Actualizar CACHE_REDIS_URI en .env para incluir password
# redis://:tu_password_seguro@taguato-redis:6379/0

# Rebuild y restart
docker compose build gateway
docker compose up -d
```

**Nota:** Las sesiones del panel se invalidaran (migracion v5). Los usuarios deben re-loguearse.

## Verificacion

1. `docker compose build gateway` - compila sin errores
2. `docker compose up -d` - todos los servicios arrancan
3. `curl http://localhost/health` - gateway responde OK
4. Redis requiere password: `docker compose exec taguato-redis redis-cli PING` falla
5. PostgreSQL no accesible externamente: `nc -z localhost 5432` falla
6. Login en panel funciona (sesiones SHA-256)
7. Crear instancia con nombre invalido es rechazado
8. `ADMIN_TOKEN=<token> ./test.sh` pasa
