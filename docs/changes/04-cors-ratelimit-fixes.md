# 04 - CORS + Rate Limiting + Fixes

**Estado:** Completado
**Commits:** `1edf22a`, `2d1b3b6`

## Objetivo
Correccion de bugs y mejoras de infraestructura: CORS, rate limiting para envio de mensajes, fixes de serializacion.

## Archivos principales
- `gateway/nginx.conf` - CORS headers, rate limit zone `msg_send`, OPTIONS handling
- `gateway/lua/status_api.lua` - Fix serializacion de arrays vacios
- `gateway/panel/index.html` - Fix ubicacion de status page

## Cambios clave
- CORS headers globales (`Access-Control-Allow-Origin: *`)
- Rate limit para `/message/`: 5 req/s burst 10
- Fix: `cjson.empty_array_mt` para arrays vacios en JSON
- Dashboard auto-refresh cada 30s
- Bulk cancel button funcional
