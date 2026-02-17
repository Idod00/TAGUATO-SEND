# TAGUATO-SEND Security Audit Tracker

Registro completo de todos los items del audit de seguridad, su estado y resolucion.

## Resumen

| Severidad | Total | Resueltos | Diferidos |
|-----------|-------|-----------|-----------|
| Critica | 3 | 3 | 0 |
| Alta | 7 | 7 | 0 |
| Media | 10 | 8 | 2 |
| Baja | 7 | 4 | 3 |
| **Total** | **27** | **22** | **5** |

---

## Items Criticos - Resueltos

| # | Item | Commit | Detalle |
|---|------|--------|---------|
| 1 | SQL injection en queries dinamicas | `95e41c2` | Parametrized queries con pgmoon escape_literal |
| 2 | Redis sin autenticacion | `95e41c2` | `--requirepass` + auth en init.lua |
| 3 | Puertos internos expuestos | `95e41c2` | Comentados postgres/redis ports en docker-compose |

## Items Alta - Resueltos

| # | Item | Commit | Detalle |
|---|------|--------|---------|
| 4 | Sessions con MD5 (predecible) | `95e41c2` | SHA-256 via pgcrypto encode(digest()) |
| 5 | Headers de seguridad faltantes | `074f008` | X-Content-Type-Options, X-Frame-Options, HSTS, etc. |
| 6 | Race condition en instance create | `95e41c2` | Atomic INSERT con subquery + ON CONFLICT |
| 22 | Input validation faltante | `074f008` | Modulo validate.lua con sanitizacion |
| 23 | XSS en respuestas de error | `074f008` | Content-Type: application/json en todas las respuestas |
| 24 | Session invalidation faltante | `074f008` | Invalidar sesiones activas al cambiar password/desactivar |
| 25 | Brute force en login | `074f008` | Lockout despues de 5 intentos fallidos |

## Items Media - Resueltos

| # | Item | Commit | Detalle |
|---|------|--------|---------|
| 7 | Auth query en cada request | Este commit | Auth cache en shared dict (10s TTL) |
| 8 | Operaciones multi-query sin transaccion | Este commit | BEGIN/COMMIT/ROLLBACK helpers en admin.lua |
| 9 | Scheduled worker: envios duplicados tras crash | Este commit | Idempotency check + migration v6 |
| 13 | response_filter concatena strings (O(n^2)) | Este commit | Table buffer + table.concat |
| 14 | Nueva conexion DB por cada query | Este commit | get_db_cached() + release() por request |
| 15 | Sin circuit breaker para Evolution API | Este commit | circuit_breaker.lua (5 fallos, 30s reset) |
| 18 | SQL con datos sensibles en logs de error | Este commit | Log template SQL con placeholders |
| 36 | Index faltante en api_token | N/A | Ya existe (creado con la tabla) |

## Items Media - Diferidos

| # | Item | Razon |
|---|------|-------|
| 10 | CI/CD pipeline con security checks | Iniciativa separada, requiere Github Actions setup |
| 12 | Todos los workers en worker 0 | Arquitectural, bajo riesgo real; refactor requiere redesign |

## Items Baja - Resueltos

| # | Item | Commit | Detalle |
|---|------|--------|---------|
| 11 | Chart.js cargado desde CDN | Este commit | Bundle local en panel/js/ |
| 28 | PGPASSWORD visible en process listings | Este commit | PGPASSFILE con .pgpass temporal |
| 32 | Dead code: instance_filter.lua | Este commit | Archivo eliminado |
| 34 | install.sh con repo URL hardcodeada | Este commit | Env var + --repo= flag |

## Items Baja - Diferidos

| # | Item | Razon |
|---|------|-------|
| 16 | Metricas de health de workers | Requiere infraestructura de monitoreo (Prometheus/etc) |
| 17 | Sistema de alerting | Requiere integracion con servicio externo |
| 19-20 | Test coverage (unit + integration) | Iniciativa separada; requiere framework de testing Lua |
| 21 | Backup de volumenes Evolution | Este commit (resuelto) |
| 33 | Graceful shutdown de workers | Requiere signal handling en nginx + Dockerfile changes |
| 35 | API key almacenada en Lua env vars | Requiere refactor completo de init; riesgo bajo |

---

## Commits de Referencia

| Commit | Descripcion |
|--------|-------------|
| `95e41c2` | Harden security: Redis auth, hide ports, atomic inserts, SHA-256 sessions |
| `074f008` | Security hardening phase 1: fix SQL injection, add security headers, session invalidation |
| (pendiente) | Security hardening phase 2: medium and low severity items |

---

*Ultima actualizacion: 2026-02-17*
