<p align="center">
  <img src="gateway/panel/img/logo.png" alt="TAGUATO-SEND" width="120">
</p>

<h1 align="center">TAGUATO-SEND</h1>

<p align="center">
  <strong>Plataforma multi-tenant de mensajeria WhatsApp con gateway inteligente y panel de gestion</strong>
</p>

<p align="center">
  <a href="#-inicio-rapido">Inicio Rapido</a> &bull;
  <a href="#-features">Features</a> &bull;
  <a href="#%EF%B8%8F-arquitectura">Arquitectura</a> &bull;
  <a href="#-panel-de-gestion">Panel</a> &bull;
  <a href="#-api-rest">API</a> &bull;
  <a href="#-documentacion">Docs</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white" alt="Docker">
  <img src="https://img.shields.io/badge/OpenResty-Gateway-4FC08D?logo=nginx&logoColor=white" alt="OpenResty">
  <img src="https://img.shields.io/badge/Evolution_API-v2.3.7-25D366?logo=whatsapp&logoColor=white" alt="Evolution API">
  <img src="https://img.shields.io/badge/PostgreSQL-15-4169E1?logo=postgresql&logoColor=white" alt="PostgreSQL">
  <img src="https://img.shields.io/badge/Redis-Cache-DC382D?logo=redis&logoColor=white" alt="Redis">
  <img src="https://img.shields.io/badge/Lua-Scripting-2C2D72?logo=lua&logoColor=white" alt="Lua">
</p>

---

## Que es TAGUATO-SEND?

TAGUATO-SEND es una plataforma completa para gestionar envios de mensajes por WhatsApp. Construida sobre [Evolution API](https://github.com/EvolutionAPI/evolution-api), agrega un gateway inteligente con OpenResty que permite administrar multiples usuarios, cada uno con sus propias instancias de WhatsApp, limites y permisos.

Todo se despliega con un solo comando via Docker Compose. Incluye un panel web completo para que los usuarios gestionen sus instancias, envien mensajes (individuales, masivos y programados), y el administrador controle todo el sistema.

---

## Features

### Mensajeria
- **Envio individual** &mdash; Texto y multimedia (imagen, documento, audio, video)
- **Envio masivo** &mdash; Hasta 500 destinatarios con barra de progreso y cancelacion
- **Envios programados** &mdash; Agenda mensajes para fecha/hora futura, ejecutados server-side por un worker automatico
- **Plantillas** &mdash; Mensajes reutilizables con formato WhatsApp (negrita, cursiva, tachado, monoespaciado)
- **Listas de contactos** &mdash; Organiza destinatarios en listas reutilizables

### Multi-tenant
- **Aislamiento por usuario** &mdash; Cada usuario solo ve y opera sus propias instancias
- **Limite de instancias** &mdash; Configurable por usuario (`max_instances`)
- **Rate limiting** &mdash; Global y por usuario, configurable
- **Sesiones efimeras** &mdash; Login con username/password, tokens de sesion con TTL de 24h (sliding window)

### Seguridad
- **Recuperacion de contrasena** &mdash; Flujo de 3 pasos via email (SMTP) o WhatsApp
- **Proteccion brute-force** &mdash; Bloqueo de cuenta tras intentos fallidos
- **Circuit breaker** &mdash; Proteccion automatica contra fallos en cascada del upstream
- **Alertas externas** &mdash; Notificaciones via webhook (Slack, Discord, Teams) cuando un servicio cae

### Administracion
- **Dashboard** &mdash; Metricas en tiempo real: usuarios, instancias, uptime
- **Gestion de usuarios** &mdash; CRUD completo con roles (admin/user), email y telefono
- **Auditoria** &mdash; Log de todas las acciones administrativas con filtros por fecha
- **Backups** &mdash; Creacion y restauracion de backups de PostgreSQL desde el panel
- **Sesiones** &mdash; Ver y revocar sesiones activas de cualquier usuario
- **Reset de contrasena** &mdash; Admin puede resetear la contrasena de cualquier usuario via email

### Monitoreo
- **Pagina de estado publica** &mdash; Muestra salud de los 4 servicios en tiempo real
- **Auto-reconexion** &mdash; Worker que detecta instancias desconectadas y las reconecta automaticamente
- **Incidentes** &mdash; Creacion y seguimiento con timeline de updates
- **Mantenimientos programados** &mdash; Notificacion publica de ventanas de mantenimiento
- **Uptime tracking** &mdash; Registro historico de disponibilidad
- **Alertas webhook** &mdash; Notificaciones automaticas de caida/recuperacion de servicios

### Panel Web
- **Responsive** &mdash; Funciona en desktop y mobile
- **Tema oscuro** &mdash; Toggle con persistencia en localStorage
- **Emoji picker** &mdash; Selector de emojis integrado en todos los textareas
- **Formato WhatsApp** &mdash; Toolbar de formateo rapido
- **Documentacion API** &mdash; Referencia interactiva integrada en el panel

---

## Arquitectura

```
                         Puerto 80
                            |
                  +---------v----------+
                  |                    |
                  |   OpenResty        |
                  |   Gateway          |
                  |                    |
                  |  - Auth por token  |
                  |  - Multi-tenant    |
                  |  - Rate limiting   |
                  |  - Panel web       |
                  |  - Workers         |
                  |                    |
                  +----+-----+--------+
                       |     |
              +--------+     +--------+
              |                       |
     +--------v--------+    +--------v--------+
     |                  |    |                 |
     |  Evolution API   |    |   PostgreSQL    |
     |  (interno:8080)  |    |   (:5432)       |
     |                  |    |                 |
     |  WhatsApp Engine |    |  Usuarios       |
     |  Baileys         |    |  Instancias     |
     |                  |    |  Logs           |
     +------------------+    |  Auditoria      |
                             |  Templates      |
              +---------+    |  Contactos      |
              |         |    |  Programados    |
     +--------v-------+ |   +-----------------+
     |                 | |
     |   Redis         | |
     |   (:6379)       +-+
     |                 |
     |   Cache         |
     +------------ ----+
```

| Servicio | Puerto | Descripcion |
|----------|--------|-------------|
| **Gateway** | `80` | OpenResty - punto de entrada unico, panel web, API |
| **Evolution API** | `8080` (interno) | Motor de WhatsApp via Baileys (no expuesto) |
| **PostgreSQL** | `5432` | Base de datos principal con schema `taguato` |
| **Redis** | `6379` | Cache y sesiones de WhatsApp |

---

## Inicio Rapido

### Instalacion con un comando

**Linux / macOS:**
```bash
curl -fsSL https://raw.githubusercontent.com/Idod00/TAGUATO-SEND/main/install.sh -o install.sh && bash install.sh
```

**Windows (PowerShell como Administrador):**
```powershell
irm https://raw.githubusercontent.com/Idod00/TAGUATO-SEND/main/install.ps1 -OutFile install.ps1; .\install.ps1
```

**Ya tienes el repo clonado?**
```bash
./install.sh           # Linux/macOS
.\install.ps1          # Windows
```

> El script verifica dependencias, genera claves seguras, configura `.env` y despliega todo automaticamente.

---

### Requisitos

- Docker y Docker Compose
- Puerto 80 disponible

### Instalacion

```bash
# 1. Clonar el repositorio
git clone https://github.com/Idod00/TAGUATO-SEND.git
cd TAGUATO-SEND

# 2. Configurar variables de entorno
cp .env.example .env
# Editar .env: cambiar AUTHENTICATION_API_KEY, POSTGRES_PASSWORD, ADMIN_PASSWORD

# 3. Levantar servicios
./scripts/start.sh
```

> **Nota:** Las credenciales del admin se configuran en `.env` (`ADMIN_USERNAME` / `ADMIN_PASSWORD`). Usalas para iniciar sesion en el panel.

### Acceder al panel

Abre `http://localhost/panel/` e ingresa con las credenciales del admin configuradas en `.env`.

---

## Panel de Gestion

El panel web permite gestionar todo el sistema desde el navegador. Accesible en `/panel/`.

### Para usuarios

| Seccion | Descripcion |
|---------|-------------|
| **Instancias** | Crear, conectar (QR) y eliminar instancias WhatsApp |
| **Mensajes** | Enviar texto y multimedia a un destinatario |
| **Envio Masivo** | Enviar a multiples numeros con progreso en tiempo real |
| **Programados** | Agendar envios para fecha/hora futura |
| **Plantillas** | Crear y gestionar mensajes reutilizables |
| **Contactos** | Organizar numeros en listas reutilizables |
| **Historial** | Ver log de todos los envios con filtros |
| **Sesiones** | Ver y revocar sesiones activas |
| **API Docs** | Documentacion interactiva de la API |

### Para administradores (adicional)

| Seccion | Descripcion |
|---------|-------------|
| **Dashboard** | Metricas: usuarios, instancias, uptime, actividad reciente |
| **Admin** | CRUD de usuarios con roles y limites |
| **Auditoria** | Log de acciones administrativas con filtros |
| **Backups** | Crear y listar backups de la base de datos |
| **Status** | Gestion de incidentes, mantenimientos y salud de servicios |

---

## API REST

La autenticacion usa sesiones efimeras. Primero hace login para obtener un token de sesion:

```bash
# Login → obtener token de sesion
curl -X POST http://localhost/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username": "tu_usuario", "password": "tu_contrasena"}'
# Respuesta: { "token": "abc123...", "user": { ... } }
```

Luego usa el token en el header `apikey`:

```
apikey: <session_token>
```

### Instancias

```bash
# Crear instancia
curl -X POST http://localhost/instance/create \
  -H "apikey: TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"instanceName": "mi-whatsapp", "integration": "WHATSAPP-BAILEYS"}'

# Conectar (obtener QR)
curl http://localhost/instance/connect/mi-whatsapp -H "apikey: TOKEN"

# Listar instancias
curl http://localhost/instance/fetchInstances -H "apikey: TOKEN"
```

### Mensajes

```bash
# Texto
curl -X POST http://localhost/message/sendText/mi-whatsapp \
  -H "apikey: TOKEN" -H "Content-Type: application/json" \
  -d '{"number": "595981123456", "text": "Hola desde TAGUATO-SEND!"}'

# Media (imagen, documento, audio, video)
curl -X POST http://localhost/message/sendMedia/mi-whatsapp \
  -H "apikey: TOKEN" -H "Content-Type: application/json" \
  -d '{"number": "595981123456", "mediatype": "image", "media": "https://ejemplo.com/img.jpg"}'
```

### Envios programados

```bash
# Crear envio programado
curl -X POST http://localhost/api/scheduled \
  -H "apikey: TOKEN" -H "Content-Type: application/json" \
  -d '{
    "instance_name": "mi-whatsapp",
    "message_type": "text",
    "message_content": "Mensaje automatico",
    "recipients": ["595981123456", "595982654321"],
    "scheduled_at": "2026-03-01T10:00:00"
  }'

# Listar programados
curl http://localhost/api/scheduled -H "apikey: TOKEN"

# Cancelar
curl -X DELETE http://localhost/api/scheduled/1 -H "apikey: TOKEN"
```

### Administracion (requiere role=admin)

```bash
# Crear usuario
curl -X POST http://localhost/admin/users \
  -H "apikey: ADMIN_TOKEN" -H "Content-Type: application/json" \
  -d '{"username": "empresa1", "password": "secreto123", "max_instances": 3}'

# Listar usuarios
curl http://localhost/admin/users -H "apikey: ADMIN_TOKEN"
```

> Consulta la documentacion completa en el panel: **API Docs**

---

## Control de Acceso

| Accion | Admin | Usuario |
|--------|:-----:|:-------:|
| Crear instancias | Sin limite | Hasta `max_instances` |
| Ver instancias | Todas | Solo las propias |
| Enviar mensajes | Cualquier instancia | Solo sus instancias |
| Programar envios | Cualquier instancia | Solo sus instancias |
| Manager Evolution API | Si | No |
| Swagger docs | Si | No |
| Gestionar usuarios | Si | No |
| Dashboard | Si | No |
| Auditoria | Si | No |
| Backups | Si | No |
| Status / Incidentes | Si | No |

---

## Tech Stack

| Componente | Tecnologia | Proposito |
|------------|------------|-----------|
| Gateway | **OpenResty** (nginx + LuaJIT) | Proxy reverso, auth, rate limiting, panel, workers |
| WhatsApp | **Evolution API** v2.3.7 | Motor de WhatsApp via Baileys |
| Base de datos | **PostgreSQL** 15 + pgcrypto | Usuarios, instancias, logs, templates, contactos |
| Cache | **Redis** | Cache de sesiones WhatsApp |
| DB Driver | **pgmoon** | Conexion PostgreSQL desde Lua (async) |
| HTTP Client | **lua-resty-http** | Requests internos desde workers |
| Contenedores | **Docker Compose** | Orquestacion de los 4 servicios |

---

## Estructura del Proyecto

```
TAGUATO-SEND/
├── docker-compose.yml            # Orquestacion de servicios
├── .env.example                  # Template de variables de entorno
├── db/
│   ├── init.sql                  # Schema completo (20+ tablas)
│   └── seed-admin.sh             # Seed del usuario admin
├── gateway/
│   ├── Dockerfile                # OpenResty alpine + pgmoon
│   ├── nginx.conf                # Rutas, proxy, workers
│   ├── lua/
│   │   ├── init.lua              # Pool de conexiones PostgreSQL
│   │   ├── json.lua              # Helpers JSON
│   │   ├── auth.lua              # Middleware de autenticacion
│   │   ├── access.lua            # Auth + filtro de instancias
│   │   ├── admin.lua             # CRUD de usuarios
│   │   ├── templates.lua         # CRUD de plantillas
│   │   ├── contacts.lua          # CRUD de listas de contactos
│   │   ├── scheduled.lua         # CRUD de envios programados
│   │   ├── sessions.lua          # Gestion de sesiones
│   │   ├── message_log.lua       # Registro de mensajes
│   │   ├── audit.lua             # Log de auditoria
│   │   ├── recovery.lua          # Recuperacion de contrasena
│   │   ├── smtp.lua              # Envio de emails via SMTP
│   │   ├── alerting.lua          # Alertas webhook externas
│   │   ├── circuit_breaker.lua   # Circuit breaker para upstream
│   │   ├── scheduled_worker.lua  # Worker de envios programados
│   │   ├── reconnect_worker.lua  # Worker de auto-reconexion
│   │   ├── uptime_worker.lua     # Worker de monitoreo
│   │   ├── backup_worker.lua     # Worker de backup automatico
│   │   ├── cleanup_worker.lua    # Worker de limpieza (sesiones, logs)
│   │   └── ...
│   └── panel/
│       ├── index.html            # SPA del panel
│       ├── css/style.css         # Estilos + dark mode
│       ├── js/
│       │   ├── api.js            # Cliente API
│       │   ├── app.js            # Logica de la aplicacion
│       │   └── docs-data.js      # Datos de documentacion
│       ├── img/                  # Logo y assets
│       └── status/               # Pagina publica de estado
├── scripts/
│   ├── start.sh                  # Iniciar servicios
│   ├── stop.sh                   # Detener servicios
│   ├── logs.sh                   # Ver logs
│   └── backup-db.sh              # Backup de DB
└── docs/
    └── changes/                  # Historial de cambios por feature
```

---

## Scripts de Utilidad

```bash
./scripts/start.sh                    # Iniciar todos los servicios
./scripts/stop.sh                     # Detener todos los servicios
./scripts/logs.sh                     # Ver logs de todos los servicios
./scripts/logs.sh taguato-gateway     # Ver logs solo del gateway
./scripts/backup-db.sh               # Crear backup de PostgreSQL
```

---

## Workers en Background

TAGUATO-SEND ejecuta 6 workers automaticos en el gateway:

| Worker | Intervalo | Funcion |
|--------|-----------|---------|
| **Uptime Check** | 5 min | Monitorea salud de los 4 servicios + alertas webhook |
| **Auto-Reconnect** | 3 min | Detecta y reconecta instancias desconectadas |
| **Scheduled Messages** | 1 min | Ejecuta envios programados pendientes |
| **Backup** | 24h (configurable) | Backup automatico de PostgreSQL |
| **Cleanup** | 1h | Expira sesiones, reintenta webhooks, purga logs antiguos |
| **Log Rotate** | 24h | Rotacion de logs de nginx |

---

## Documentacion

| Recurso | Ubicacion |
|---------|-----------|
| Panel de gestion | `http://localhost/panel/` |
| API Docs (interactivo) | Panel > API Docs |
| Pagina de estado | `http://localhost/status/` |
| Swagger (admin) | `http://localhost/docs` |
| Historial de cambios | [`docs/changes/`](docs/changes/) |

---

## Configuracion

Las variables de entorno se configuran en `.env` (ver [`.env.example`](.env.example)):

| Variable | Descripcion |
|----------|-------------|
| `GATEWAY_PORT` | Puerto del gateway (default: 80) |
| `ADMIN_USERNAME` | Usuario admin inicial |
| `ADMIN_PASSWORD` | Contrasena admin inicial |
| `AUTHENTICATION_API_KEY` | Clave interna gateway-API |
| `POSTGRES_PASSWORD` | Contrasena de PostgreSQL |
| `REDIS_PASSWORD` | Contrasena de Redis |
| `GATEWAY_CORS_ORIGIN` | Dominio permitido para CORS (vacio = sin CORS) |
| `SMTP_HOST`, `SMTP_PORT`, etc. | Configuracion SMTP para recuperacion de contrasena por email |
| `ALERT_WEBHOOK_URL` | URL webhook para alertas de caida de servicios (Slack/Discord/Teams) |
| `BACKUP_INTERVAL` | Intervalo de backup automatico en segundos (default: 86400) |

---

<p align="center">
  Hecho en Paraguay
</p>
