# Registro de Cambios - TAGUATO-SEND

## [1.1.0] - 2026-02-06

### Gateway Multi-Tenant con OpenResty

Se implementó un gateway con OpenResty que se interpone entre los clientes y la Evolution API,
agregando autenticación multi-usuario y control de acceso por instancia de WhatsApp.

#### Agregado

- **Gateway OpenResty** (puerto 80) como punto de entrada único
  - Autenticación por token individual (`apikey: <token>`)
  - Filtrado de instancias por propiedad del usuario
  - Proxy reverso a Evolution API (puerto 8080, ahora solo interno)
  - Health check en `/health` sin autenticación

- **API de administración** (`/admin/users`)
  - `POST /admin/users` - Crear usuario con token auto-generado
  - `GET /admin/users` - Listar todos los usuarios
  - `GET /admin/users/{id}` - Ver usuario con sus instancias
  - `PUT /admin/users/{id}` - Actualizar (max_instances, is_active, role, password, regenerate_token)
  - `DELETE /admin/users/{id}` - Eliminar usuario (con protección contra auto-eliminación)

- **Control de acceso por instancia**
  - Usuarios solo pueden crear/ver/operar sus propias instancias
  - Limite configurable de instancias por usuario (`max_instances`)
  - Respuesta de `fetchInstances` filtrada para mostrar solo instancias propias
  - Protección de nombres: un nombre de instancia no puede ser usado por dos usuarios

- **Schema de base de datos** (schema PostgreSQL `taguato`)
  - Tabla `taguato.users` - Usuarios con tokens, roles, limites
  - Tabla `taguato.user_instances` - Relación usuario-instancia
  - Contraseñas hasheadas con bcrypt (`pgcrypto`)
  - Tokens generados con `gen_random_bytes(32)`
  - Schema separado para no conflictuar con Prisma de Evolution API

- **Seed automático del admin**
  - Script `db/seed-admin.sh` ejecutado en primer inicio de PostgreSQL
  - Credenciales configurables via `ADMIN_USERNAME` y `ADMIN_PASSWORD` en `.env`
  - Token del admin visible en logs: `docker compose logs taguato-postgres | grep "API Token"`

- **Archivos nuevos**
  - `gateway/Dockerfile` - OpenResty alpine-fat + pgmoon
  - `gateway/nginx.conf` - Configuración de rutas y proxy
  - `gateway/lua/access.lua` - Auth + filtro de instancias combinado
  - `gateway/lua/admin.lua` - CRUD de usuarios
  - `gateway/lua/auth.lua` - Middleware de autenticación (para `/admin/`)
  - `gateway/lua/init.lua` - Pool de conexiones PostgreSQL via pgmoon
  - `gateway/lua/json.lua` - Helpers JSON (encode/decode/respond/read_body)
  - `gateway/lua/response_filter.lua` - Filtro de respuesta para fetchInstances
  - `gateway/lua/instance_filter.lua` - Referencia de lógica de filtrado
  - `db/init.sql` - Schema de tablas multi-tenant
  - `db/seed-admin.sh` - Seed del usuario administrador

#### Modificado

- **docker-compose.yml**
  - Agregado servicio `taguato-gateway` (OpenResty) en puerto 80
  - Puerto 8080 de `taguato-api` ya no se expone externamente
  - PostgreSQL configurado con auth `md5` (compatibilidad con pgmoon)
  - Volúmenes para scripts de inicialización de DB (`init.sql`, `seed-admin.sh`)
  - Variables de entorno `ADMIN_USERNAME` y `ADMIN_PASSWORD` para PostgreSQL
  - Imagen de API actualizada a `evoapicloud/evolution-api:v2.3.7`

- **.env.example**
  - Reemplazado `API_PORT` y `MANAGER_PORT` por `GATEWAY_PORT`
  - Agregados `ADMIN_USERNAME` y `ADMIN_PASSWORD`

- **.gitignore**
  - Excepción para `db/init.sql` (antes bloqueado por regla `*.sql`)

- **README.md**
  - Documentación completa reescrita para reflejar arquitectura multi-tenant
  - Secciones de gestión de usuarios (admin)
  - Tabla de control de acceso por rol
  - Todos los ejemplos de curl actualizados al puerto 80

#### Notas técnicas

- nginx solo permite un `access_by_lua_file` por location, por lo que auth y filtro de instancias se combinaron en `access.lua`
- La sustitución de parámetros SQL usa `string.find` en loop (no `gsub`) para evitar problemas con el carácter `%` en valores escapados
- Se requiere la directiva `env` en nginx.conf para que las variables de entorno sean accesibles desde Lua en OpenResty
- El resolver DNS de Docker (`127.0.0.11`) se configura en nginx.conf para que pgmoon pueda resolver hostnames de la red interna

---

## [1.0.1] - 2026-02-06

### Corrección del Manager

- Eliminado contenedor separado de Evolution Manager (estaba roto)
- Se usa el manager integrado en Evolution API (`/manager`)

---

## [1.0.0] - 2026-02-06

### Lanzamiento Inicial

- Docker Compose con Evolution API, PostgreSQL y Redis
- Configuración via `.env`
- Scripts de utilidad (start, stop, logs, backup)
- Documentación de API REST en español
