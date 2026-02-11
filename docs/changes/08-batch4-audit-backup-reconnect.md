# 08 - Batch 4: Audit Log + Backup Admin + Reconnect Worker

**Estado:** Completado
**Commit:** `a74202e`

## Objetivo
Log de auditoria para acciones admin, gestion de backups de DB y auto-reconexion de instancias desconectadas.

## Archivos creados/modificados
- `gateway/lua/audit.lua` - **Nuevo** - Modulo de auditoria (registro + consulta)
- `gateway/lua/backup_admin.lua` - **Nuevo** - Listar y crear backups de PostgreSQL
- `gateway/lua/reconnect_worker.lua` - **Nuevo** - Worker que reconecta instancias caidas cada 3 min
- `gateway/nginx.conf` - Locations para `/admin/audit`, `/admin/backup` + timer reconnect
- `gateway/panel/index.html` - Secciones de auditoria y backups
- `gateway/panel/js/api.js` - `getAuditLogs`, `listBackups`, `createBackup`
- `gateway/panel/js/app.js` - Logica de auditoria (filtros, paginacion), backups
- `db/init.sql` - Tablas: `audit_log`, `reconnect_log`

## Cambios clave
- Audit log registra: user_created/updated/deleted, login, incidents, backups
- Backup via `pg_dump` ejecutado desde Lua
- Reconnect worker usa `resty.http` para detectar instancias desconectadas y reconectarlas
- Dashboard muestra reconexiones recientes
