# 13 - Security Hardening: Items Medianos y Bajos

## Objetivo
Implementar los 12 items accionables de severidad media y baja restantes del audit de seguridad, complementando los dos commits previos de hardening (alto+critico).

## Items Implementados

### Fase 1: Fundacion
| # | Severidad | Descripcion | Archivo(s) |
|---|-----------|-------------|------------|
| 14 | Media | Reutilizar conexion DB por request (`get_db_cached`, `release()`) | `gateway/lua/init.lua`, `gateway/nginx.conf` |
| 7 | Media | Cache de auth token en shared dict (10s TTL) | `gateway/nginx.conf`, `gateway/lua/auth.lua`, `gateway/lua/access.lua` |
| 18 | Media | SQL con datos sensibles en error logs (usar template con placeholders) | `gateway/lua/init.lua` |

### Fase 2: Seguridad Core
| # | Severidad | Descripcion | Archivo(s) |
|---|-----------|-------------|------------|
| 8 | Media | Transacciones para operaciones multi-query en admin | `gateway/lua/init.lua`, `gateway/lua/admin.lua` |
| 13 | Media | response_filter acumula body con table buffer (no string concat) | `gateway/lua/response_filter.lua` |
| 15 | Media | Circuit breaker para Evolution API (5 fallos, 30s reset) | `gateway/lua/circuit_breaker.lua`, `gateway/lua/access.lua`, `gateway/nginx.conf` |

### Fase 3: Integridad de Datos
| # | Severidad | Descripcion | Archivo(s) |
|---|-----------|-------------|------------|
| 9 | Media | Prevencion de envios duplicados en scheduled worker | `gateway/lua/scheduled_worker.lua`, `gateway/lua/migrations_list.lua` |
| 28 | Baja | Password de DB oculto en process listings (PGPASSFILE) | `gateway/lua/backup_worker.lua` |

### Fase 4: Frontend + Infraestructura
| # | Severidad | Descripcion | Archivo(s) |
|---|-----------|-------------|------------|
| 11 | Baja | Chart.js servido localmente (sin CDN) | `gateway/panel/status/index.html`, `gateway/panel/js/chart.umd.min.js` |
| 21 | Baja | Backup de volumenes Evolution API | `docker-compose.yml`, `gateway/lua/backup_worker.lua` |

### Fase 5: Limpieza
| # | Severidad | Descripcion | Archivo(s) |
|---|-----------|-------------|------------|
| 32 | Baja | Eliminado dead code `instance_filter.lua` | eliminado |
| 34 | Baja | install.sh repo URL configurable (`--repo=` flag + env var) | `install.sh` |

## Archivos Modificados

| Archivo | Cambio |
|---------|--------|
| `gateway/lua/init.lua` | conn reuse (`get_db_cached`/`release`), SQL log masking, transaction helpers |
| `gateway/nginx.conf` | shared dicts (auth_cache, circuit_breaker), log_by_lua_block, proxy timeouts |
| `gateway/lua/auth.lua` | auth cache lookup/store |
| `gateway/lua/access.lua` | auth cache, circuit breaker check |
| `gateway/lua/admin.lua` | transactions (BEGIN/COMMIT/ROLLBACK), cache invalidation |
| `gateway/lua/response_filter.lua` | table buffer en vez de string concat |
| `gateway/lua/circuit_breaker.lua` | **nuevo** - circuit breaker module |
| `gateway/lua/scheduled_worker.lua` | idempotency check antes de enviar |
| `gateway/lua/migrations_list.lua` | migration v6: scheduled_message_id column |
| `gateway/lua/backup_worker.lua` | PGPASSFILE, volume backup |
| `docker-compose.yml` | evolution volumes mounted ro in gateway |
| `gateway/panel/status/index.html` | Chart.js local path |
| `gateway/panel/js/chart.umd.min.js` | **nuevo** - Chart.js 4.4.7 bundle |
| `install.sh` | `--repo=URL` flag + TAGUATO_REPO_URL env var |
| `gateway/lua/instance_filter.lua` | **eliminado** - dead code |

## Items No Implementados (Diferidos)

| # | Razon |
|---|-------|
| 10 | CI/CD pipeline - iniciativa separada |
| 12 | Workers en worker 0 - arquitectural, bajo riesgo |
| 16 | Metricas de workers - requiere infra de monitoreo |
| 17 | Alerting system - requiere integracion externa |
| 19-20 | Test coverage - iniciativa separada |
| 33 | Graceful shutdown - requiere cambios en Dockerfile |
| 35 | API key en Lua env vars - requiere refactor de init |
| 36 | Index en api_token - ya existe |

## Notas de Deploy
- Migration v6 se ejecuta automaticamente al arrancar (migrate_worker)
- Los volumenes de Evolution se montan read-only: no hay riesgo de corrupcion
- El circuit breaker se auto-resetea despues de 30 segundos
- Auth cache tiene TTL de 10 segundos, se invalida en operaciones admin
