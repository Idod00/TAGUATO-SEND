# 00 - Setup Inicial + Gateway Multi-tenant

**Estado:** Completado
**Commits:** `f23be7f`, `d2ac414`, `565e142`

## Objetivo
Setup inicial del proyecto: Docker Compose con Evolution API, PostgreSQL, Redis y OpenResty gateway multi-tenant.

## Archivos principales
- `docker-compose.yml` - 4 servicios (gateway, api, postgres, redis)
- `.env` / `.env.example` - Variables de entorno
- `db/init.sql` - Schema inicial (taguato.users, taguato.user_instances)
- `db/seed-admin.sh` - Seed del usuario admin
- `gateway/Dockerfile` - OpenResty alpine + pgmoon
- `gateway/nginx.conf` - Proxy reverso con auth
- `gateway/lua/` - init.lua, auth.lua, access.lua, admin.lua, json.lua, response_filter.lua

## Cambios clave
- Gateway en puerto 80, Evolution API en 8080 (interno)
- Auth via header `apikey: <user_token>`
- Admin bypass de filtros, users limitados por `max_instances`
- Response filter para `fetchInstances` (filtra por ownership)
