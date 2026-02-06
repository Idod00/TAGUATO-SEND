# TAGUATO-SEND

Sistema de envío de mensajes automáticos por WhatsApp con gateway multi-tenant y API REST.

Basado en [Evolution API](https://github.com/EvolutionAPI/evolution-api) con un gateway OpenResty que agrega autenticación multi-usuario y control de acceso por instancia.

## Requisitos

- Docker y Docker Compose
- Puerto 80 (Gateway), 5432 (PostgreSQL), 6379 (Redis) disponibles

## Arquitectura

```
Cliente (puerto 80)
    │
    ▼
┌─────────────────────────────┐
│  OpenResty Gateway (:80)    │
│  - Auth por token           │
│  - Admin CRUD               │
│  - Filtrado de instancias   │
└──────────┬──────────────────┘
           │ (red interna)
    ┌──────┼──────────┐
    ▼      ▼          ▼
 API:8080  PG:5432  Redis:6379
```

- **Admin**: acceso total a todas las instancias y gestión de usuarios
- **Usuario**: acceso solo a sus propias instancias (limite configurable)
- Formato de auth: `apikey: <token_del_usuario>`

## Instalación

```bash
# 1. Clonar el repositorio
git clone <url-del-repo> && cd TAGUATO-SEND

# 2. Configurar variables de entorno
cp .env.example .env
# Editar .env: cambiar AUTHENTICATION_API_KEY, POSTGRES_PASSWORD, ADMIN_PASSWORD

# 3. Levantar servicios
./scripts/start.sh

# 4. Obtener el token del admin (primera vez)
docker compose logs taguato-postgres | grep "API Token"
```

## Servicios

| Servicio | Puerto | Descripción |
|----------|--------|-------------|
| Gateway | 80 | OpenResty - punto de entrada único |
| API | 8080 (interno) | Evolution API (no expuesto) |
| PostgreSQL | 5432 | Base de datos |
| Redis | 6379 | Cache |

## Obtener Token del Admin

En la primera ejecución, el token del admin se genera automáticamente y se muestra en los logs de PostgreSQL:

```bash
docker compose logs taguato-postgres | grep "API Token"
# Output: NOTICE:  API Token: <tu-token-admin>
```

Guarda este token, es tu clave de acceso como administrador.

## Gestión de Usuarios (Admin)

### Crear usuario

```bash
curl -X POST http://localhost/admin/users \
  -H "apikey: TOKEN_ADMIN" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "empresa1",
    "password": "password_seguro",
    "max_instances": 3
  }'
```

Respuesta:
```json
{
  "user": {
    "id": 2,
    "username": "empresa1",
    "role": "user",
    "api_token": "abc123...",
    "max_instances": 3,
    "is_active": true
  }
}
```

### Listar usuarios

```bash
curl http://localhost/admin/users \
  -H "apikey: TOKEN_ADMIN"
```

### Ver usuario con sus instancias

```bash
curl http://localhost/admin/users/2 \
  -H "apikey: TOKEN_ADMIN"
```

### Actualizar usuario

```bash
curl -X PUT http://localhost/admin/users/2 \
  -H "apikey: TOKEN_ADMIN" \
  -H "Content-Type: application/json" \
  -d '{
    "max_instances": 5,
    "is_active": true
  }'
```

Campos actualizables: `max_instances`, `is_active`, `role`, `password`, `regenerate_token` (boolean).

### Eliminar usuario

```bash
curl -X DELETE http://localhost/admin/users/2 \
  -H "apikey: TOKEN_ADMIN"
```

## API REST (Usuarios)

Cada usuario usa su propio token (obtenido al crear el usuario):

```
apikey: TOKEN_DEL_USUARIO
```

### Crear instancia WhatsApp

```bash
curl -X POST http://localhost/instance/create \
  -H "apikey: TOKEN_USUARIO" \
  -H "Content-Type: application/json" \
  -d '{
    "instanceName": "mi-whatsapp",
    "integration": "WHATSAPP-BAILEYS",
    "qrcode": true
  }'
```

> El usuario solo puede crear hasta `max_instances` instancias.

### Obtener QR para vincular

```bash
curl http://localhost/instance/connect/mi-whatsapp \
  -H "apikey: TOKEN_USUARIO"
```

### Ver estado de conexión

```bash
curl http://localhost/instance/connectionState/mi-whatsapp \
  -H "apikey: TOKEN_USUARIO"
```

### Listar mis instancias

```bash
curl http://localhost/instance/fetchInstances \
  -H "apikey: TOKEN_USUARIO"
```

> Solo devuelve las instancias que pertenecen al usuario.

### Enviar mensaje de texto

```bash
curl -X POST http://localhost/message/sendText/mi-whatsapp \
  -H "apikey: TOKEN_USUARIO" \
  -H "Content-Type: application/json" \
  -d '{
    "number": "595981123456",
    "text": "Hola desde TAGUATO-SEND!"
  }'
```

> **Nota:** El número debe incluir código de país sin `+`. Paraguay: `595`, Argentina: `54`, Brasil: `55`.

### Enviar imagen

```bash
curl -X POST http://localhost/message/sendMedia/mi-whatsapp \
  -H "apikey: TOKEN_USUARIO" \
  -H "Content-Type: application/json" \
  -d '{
    "number": "595981123456",
    "mediatype": "image",
    "media": "https://ejemplo.com/imagen.jpg",
    "caption": "Mira esta imagen"
  }'
```

### Enviar documento

```bash
curl -X POST http://localhost/message/sendMedia/mi-whatsapp \
  -H "apikey: TOKEN_USUARIO" \
  -H "Content-Type: application/json" \
  -d '{
    "number": "595981123456",
    "mediatype": "document",
    "media": "https://ejemplo.com/archivo.pdf",
    "fileName": "reporte.pdf"
  }'
```

### Configurar webhook

```bash
curl -X POST http://localhost/webhook/set/mi-whatsapp \
  -H "apikey: TOKEN_USUARIO" \
  -H "Content-Type: application/json" \
  -d '{
    "url": "https://tu-servidor.com/webhook",
    "webhook_by_events": false,
    "webhook_base64": false,
    "events": [
      "MESSAGES_UPSERT",
      "CONNECTION_UPDATE",
      "QRCODE_UPDATED"
    ]
  }'
```

### Eliminar instancia

```bash
curl -X DELETE http://localhost/instance/delete/mi-whatsapp \
  -H "apikey: TOKEN_USUARIO"
```

## Endpoints del Gateway

### Admin (requiere role=admin)

| Método | Endpoint | Descripción |
|--------|----------|-------------|
| POST | `/admin/users` | Crear usuario |
| GET | `/admin/users` | Listar usuarios |
| GET | `/admin/users/{id}` | Ver usuario + instancias |
| PUT | `/admin/users/{id}` | Actualizar usuario |
| DELETE | `/admin/users/{id}` | Eliminar usuario |

### Health check (sin auth)

| Método | Endpoint | Descripción |
|--------|----------|-------------|
| GET | `/health` | Estado del gateway |

### Proxied (filtrado por usuario)

Todos los endpoints de Evolution API pasan por el gateway:
- **Admin**: acceso total sin restricción
- **Usuario**: solo opera sobre sus propias instancias
- Crear instancia verifica limite de `max_instances`
- `fetchInstances` filtra la respuesta para mostrar solo las del usuario

## Control de Acceso

| Acción | Admin | Usuario |
|--------|-------|---------|
| Crear instancia | Sin limite | Hasta max_instances |
| Ver instancias | Todas | Solo las propias |
| Operar instancia | Cualquiera | Solo las propias |
| Manager web | Acceso total | Bloqueado |
| Swagger docs | Acceso total | Bloqueado |
| Gestionar usuarios | CRUD completo | Sin acceso |

## Scripts de Utilidad

```bash
./scripts/start.sh             # Iniciar todos los servicios
./scripts/stop.sh              # Detener todos los servicios
./scripts/logs.sh              # Ver logs de todos los servicios
./scripts/logs.sh taguato-api  # Ver logs solo de la API
./scripts/backup-db.sh         # Crear backup de la base de datos
```

## Estructura del Proyecto

```
TAGUATO-SEND/
├── docker-compose.yml         # Orquestación de servicios
├── .env                       # Variables de entorno (no se commitea)
├── .env.example               # Template de variables
├── .gitignore                 # Exclusiones de Git
├── README.md                  # Esta documentación
├── db/
│   ├── init.sql               # Schema de tablas multi-tenant
│   └── seed-admin.sh          # Seed del usuario admin
├── gateway/
│   ├── Dockerfile             # OpenResty + pgmoon
│   ├── nginx.conf             # Configuración del gateway
│   └── lua/
│       ├── access.lua         # Auth + filtro combinado
│       ├── admin.lua          # CRUD de usuarios
│       ├── auth.lua           # Middleware de autenticación
│       ├── init.lua           # Pool de conexiones PG
│       ├── instance_filter.lua # Filtro de instancias (ref)
│       ├── json.lua           # Helpers JSON
│       └── response_filter.lua # Filtro de respuestas
└── scripts/
    ├── start.sh               # Iniciar servicios
    ├── stop.sh                # Detener servicios
    ├── logs.sh                # Ver logs
    └── backup-db.sh           # Backup de DB
```
