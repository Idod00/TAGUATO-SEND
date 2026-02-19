# TAGUATO-SEND

WhatsApp messaging system: Evolution API + OpenResty Gateway, multi-tenant.

## Architecture

```
Browser → OpenResty Gateway (:80) → Evolution API (:8080 internal)
                ↓
          PostgreSQL (:5432) + Redis (:6379)
```

- **Gateway** validates tokens, enforces ownership, rate limits, proxies to API
- **Admin** bypasses all instance filtering; **Users** limited by `max_instances`
- Auth: `apikey: <session_token>` header (ephemeral sessions, not permanent tokens)

## Quick Commands

```bash
docker compose up -d --build taguato-gateway  # Rebuild + restart gateway
./tests/run_all.sh                            # Run full test suite (269 tests)
docker compose logs -f taguato-gateway        # View gateway logs
```

## Tech Stack

- **Gateway**: OpenResty (nginx + LuaJIT), pgmoon for PostgreSQL, resty.redis
- **API**: Evolution API v2.3.7 (Docker image)
- **DB**: PostgreSQL 15 with pgcrypto, schema `taguato.*`
- **Cache**: Redis (auth cache, status cache, rate limiting)

## File Structure

### Lua Endpoints (`gateway/lua/`)

| File | Route | Description |
|------|-------|-------------|
| `admin.lua` | `/admin/users*` | User CRUD (admin only) |
| `auth.lua` | (access phase) | Token validation, role check |
| `panel_auth.lua` | `/api/auth/*` | Login, logout, change-password, recovery |
| `session_auth.lua` | (module) | Session token validation |
| `sessions.lua` | `/api/sessions`, `/admin/sessions` | Session management |
| `access.lua` | (access phase) | Auth + instance ownership for proxied routes |
| `templates.lua` | `/api/templates*` | Message templates CRUD |
| `contacts.lua` | `/api/contacts*` | Contact lists CRUD |
| `webhooks.lua` | `/api/webhooks*` | Webhook CRUD + Evolution API sync |
| `scheduled.lua` | `/api/scheduled*` | Scheduled messages CRUD |
| `message_log.lua` | `/api/messages/log*` | Message logging |
| `export.lua` | `/api/messages/export` | CSV export |
| `incidents_admin.lua` | `/admin/incidents*` | Incident management |
| `maintenance_admin.lua` | `/admin/maintenance*` | Maintenance windows |
| `status_api.lua` | `/api/status` | Public status page API |
| `dashboard_api.lua` | `/admin/dashboard` | Admin dashboard stats |
| `user_dashboard.lua` | `/api/user/dashboard` | User dashboard stats |
| `instance_stats.lua` | `/api/instance/*` | Per-instance stats |
| `backup_admin.lua` | `/admin/backup*` | Backup management |
| `audit.lua` | `/admin/audit` | Audit log viewer |

### Lua Infrastructure (`gateway/lua/`)

| File | Purpose |
|------|---------|
| `init.lua` | DB connection pool (pgmoon), Redis helper, query wrapper |
| `json.lua` | JSON read/respond helpers |
| `validate.lua` | Input validation (username, password, email, phone, webhook URL, enum) |
| `rate_limit.lua` | Per-user rate limiting |
| `circuit_breaker.lua` | Upstream circuit breaker |
| `response_filter.lua` | Filter fetchInstances by ownership |
| `smtp.lua` | SMTP email sending |
| `recovery.lua` | Password recovery (email + WhatsApp) |
| `migrate_worker.lua` | Auto-migration on startup |
| `migrations_list.lua` | Migration definitions |
| `uptime_worker.lua` | Periodic uptime checks (5min) |
| `reconnect_worker.lua` | Auto-reconnect WhatsApp (3min) |
| `scheduled_worker.lua` | Process pending scheduled messages (1min) |
| `backup_worker.lua` | Periodic DB backup |
| `cleanup_worker.lua` | Session expiry, webhook retry, log purge |
| `logrotate_worker.lua` | Nginx log rotation (24h) |

### Tests (`tests/`)

Tests are bash scripts using curl + jq. Run with `./tests/run_all.sh`.

| File | What it tests |
|------|---------------|
| `helpers/common.sh` | Test framework: do_get/post/put/delete, assert_* functions |
| `helpers/setup.sh` | Creates ci_user1, ci_user2, ci_user3 + login tokens |
| `helpers/teardown.sh` | Cleans test data |
| `01_health.sh` | Health check + status endpoint |
| `02_auth.sh` | Login, /me, change-password, brute-force lockout |
| `03_admin_users.sh` | Admin user CRUD, pagination, search, deactivate |
| `04_instances.sh` | Instance CRUD, ownership, limit enforcement |
| `05_templates.sh` | Template CRUD, pagination, isolation |
| `06_contacts.sh` | Contact lists + items CRUD, isolation |
| `07_webhooks.sh` | Webhook CRUD + PUT update, isolation |
| `08_scheduled.sh` | Scheduled messages CRUD + pagination |
| `09_message_log.sh` | Message logging + CSV export |
| `10_sessions.sh` | Session management, admin pagination |
| `11_dashboard.sh` | User + admin dashboards |
| `12_incidents.sh` | Incident CRUD, timeline, pagination |
| `13_maintenance.sh` | Maintenance CRUD, pagination |
| `14_audit.sh` | Audit log filtering |
| `15_security.sh` | SQL injection, headers, CORS, rate limiting |
| `16_validation.sh` | Boundary value testing |
| `17_multi_tenant.sh` | Cross-user isolation |

### Database (`db/`)

Schema: `taguato.*` in PostgreSQL 15. Key tables:

- `users` — id, username, password_hash, role, api_token, max_instances, rate_limit, email, phone_number
- `user_instances` — user_id, instance_name (ownership tracking)
- `sessions` — session tokens, ip, user_agent, last_active
- `message_templates` — user-scoped templates
- `contact_lists` / `contact_list_items` — user-scoped contacts
- `user_webhooks` — webhook config per instance
- `scheduled_messages` — pending/sent/failed scheduled messages
- `message_logs` — sent message history
- `audit_log` — admin action audit trail
- `services` — monitored services (Gateway, API, PostgreSQL, Redis)
- `incidents` / `incident_updates` / `incident_services` — incident management
- `scheduled_maintenances` / `maintenance_services` — maintenance windows
- `uptime_checks` — periodic health check results
- `reconnect_log` — WhatsApp reconnection attempts
- `schema_migrations` — applied migration tracking
- `password_resets` — recovery codes

## Patterns & Conventions

### Lua Endpoint Pattern
```lua
local db = require "init"
local json = require "json"
local user = ngx.ctx.user  -- set by auth.lua in access phase
local method = ngx.req.get_method()
local uri = ngx.var.uri

if method == "GET" and uri == "/api/thing" then
    -- handler
    json.respond(200, { things = res })
    return
end

json.respond(404, { error = "Not found" })
```

### Pagination Pattern (standard for all list endpoints)
```lua
local args = ngx.req.get_uri_args()
local page = tonumber(args.page) or 1
local limit = tonumber(args.limit) or 50
if limit > 100 then limit = 100 end
local offset = (page - 1) * limit
-- COUNT query → total
-- Data query with LIMIT $x OFFSET $y
json.respond(200, { items = res, total = total, page = page, limit = limit, pages = math.ceil(total / limit) })
```

### Dynamic UPDATE Pattern
```lua
local sets, vals, idx = {}, {}, 0
if body.field then
    idx = idx + 1
    sets[#sets+1] = "field = $" .. idx
    vals[idx] = body.field
end
-- Add WHERE param last
idx = idx + 1; vals[idx] = id
local sql = "UPDATE ... SET " .. table.concat(sets, ", ") .. " WHERE id = $" .. idx
```

### Empty Array Serialization
```lua
local empty_array_mt = cjson.empty_array_mt
local function as_array(t)
    if t == nil or (type(t) == "table" and #t == 0) then
        return setmetatable({}, empty_array_mt)
    end
    return t
end
```

### N+1 Prevention (json_agg)
```sql
SELECT ...,
    COALESCE((SELECT json_agg(row_to_json(sub)) FROM (...) sub), '[]') as field
FROM main_table
```
Then decode in Lua: `pcall(cjson.decode, row.field)`

## Important Notes

- **pgmoon** param replacement uses `string.find` loop (not gsub) to avoid `%` issues
- nginx allows ONE `access_by_lua_file` per location → auth + filter combined in `access.lua`
- `AUTHENTICATION_API_KEY` is the internal key for gateway→API communication (never exposed to users)
- Tests require Docker running: `docker compose up -d` before `./tests/run_all.sh`
- All user-facing endpoints require `apikey` header with session token
- Admin endpoints are under `/admin/*`, user endpoints under `/api/*`
