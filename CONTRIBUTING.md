# Contributing to TAGUATO-SEND

## Prerequisites

- Docker & Docker Compose
- Git
- bash, curl, jq (for running tests)

## Setup

```bash
git clone https://github.com/Idod00/TAGUATO-SEND.git
cd TAGUATO-SEND
cp .env.example .env  # adjust values as needed
docker compose up -d --build
```

The panel is available at `http://localhost`. Default admin credentials are in `.env` (`ADMIN_USERNAME` / `ADMIN_PASSWORD`).

## Branch Conventions

Always create a feature branch from `main`. Never push directly to `main`.

| Prefix | Use |
|--------|-----|
| `feat/` | New features |
| `fix/` | Bug fixes |
| `refactor/` | Code restructuring without behavior change |
| `docs/` | Documentation only |
| `ci/` | CI/CD and test infrastructure |
| `test/` | Adding or fixing tests |

Example: `feat/bulk-media-send`, `fix/uptime-worker-keepalive`

## Commit Conventions

We use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add bulk media messaging
fix: uptime worker pg connection closed before inserts
refactor: extract validation into shared module
test: add webhook isolation tests
docs: update API documentation
ci: add GitHub Actions workflow
```

- Keep the subject line under 72 characters
- Use imperative mood ("add", "fix", "update", not "added", "fixes")
- Add a body for non-trivial changes explaining **why**, not just what

## Development Workflow

### Rebuild gateway after Lua changes

```bash
docker compose up -d --build taguato-gateway
```

### View gateway logs

```bash
docker compose logs -f taguato-gateway
```

### Run tests

The test suite requires all services running:

```bash
docker compose up -d
./tests/run_all.sh
```

Tests are bash scripts in `tests/` using curl + jq. The suite creates temporary users (`ci_user1`, `ci_user2`, `ci_user3`) and cleans up after itself.

### Run a single test file

```bash
# Source helpers first, then run the specific test
source tests/helpers/common.sh
source tests/helpers/setup.sh
bash tests/07_webhooks.sh
source tests/helpers/teardown.sh
```

## Adding a Database Migration

1. Open `gateway/lua/migrations_list.lua`
2. Add a new entry at the end of the migrations table:

```lua
{
    name = "YYYYMMDD_description",
    sql = [[
        -- Your SQL here
        CREATE TABLE taguato.new_table (...);
    ]]
},
```

3. Migrations run automatically on gateway startup via `migrate_worker.lua`
4. Applied migrations are tracked in `taguato.schema_migrations`

## Adding a New Lua Endpoint

1. Create `gateway/lua/your_endpoint.lua` following the standard pattern:

```lua
local db = require "init"
local json = require "json"
local user = ngx.ctx.user
local method = ngx.req.get_method()
local uri = ngx.var.uri

if method == "GET" and uri == "/api/your-thing" then
    -- handler
    json.respond(200, { data = res })
    return
end

json.respond(404, { error = "Not found" })
```

2. Add the route in `gateway/nginx.conf` under the appropriate location block
3. Add tests in `tests/`

## Code Style

- **Indentation**: 4 spaces (Lua files)
- **Naming**: `snake_case` for variables and functions
- **Strings**: double quotes for SQL, double quotes for Lua strings
- **Empty arrays**: use `setmetatable({}, cjson.empty_array_mt)` for JSON `[]`
- **Pagination**: standard pattern with `?page=&limit=` returning `{ items, total, page, limit, pages }`
- **Error handling**: always return `json.respond(4xx/5xx, { error = "message" })`

## Pull Requests

1. Create a branch from `main`
2. Make your changes and add tests
3. Run `./tests/run_all.sh` — all tests must pass
4. Push your branch and create a PR targeting `main`
5. PR description should include a summary and test plan

## Security

If you find a security vulnerability, please **do not** open a public issue. Instead, contact the maintainers privately.
