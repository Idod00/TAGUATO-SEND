# TAGUATO-SEND

Sistema de envío de mensajes automáticos por WhatsApp con panel web y API REST.

Basado en [Evolution API](https://github.com/EvolutionAPI/evolution-api) + [Evolution Manager](https://github.com/EvolutionAPI/evolution-manager).

## Requisitos

- Docker y Docker Compose
- Puerto 8080 (API + Panel), 5432 (PostgreSQL), 6379 (Redis) disponibles

## Instalación

```bash
# 1. Clonar el repositorio
git clone <url-del-repo> && cd TAGUATO-SEND

# 2. Configurar variables de entorno
cp .env.example .env
# Editar .env: cambiar AUTHENTICATION_API_KEY y POSTGRES_PASSWORD

# 3. Levantar servicios
./scripts/start.sh
```

## Servicios

| Servicio | URL | Descripción |
|----------|-----|-------------|
| API | http://localhost:8080 | Evolution API (backend) |
| Panel | http://localhost:8080/manager | Evolution Manager (integrado) |
| Swagger | http://localhost:8080/docs | Documentación interactiva |

## Uso del Panel Web

1. Abrir http://localhost:8080/manager
2. Conectar al servidor: `http://localhost:8080` con tu `AUTHENTICATION_API_KEY`
3. Crear una instancia WhatsApp
4. Escanear el código QR con tu teléfono
5. Enviar mensajes desde el panel

## API REST

Todas las peticiones requieren el header de autenticación:

```
apikey: TU_AUTHENTICATION_API_KEY
```

### Crear instancia WhatsApp

```bash
curl -X POST http://localhost:8080/instance/create \
  -H "apikey: TU_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "instanceName": "mi-whatsapp",
    "integration": "WHATSAPP-BAILEYS",
    "qrcode": true
  }'
```

### Obtener QR para vincular

```bash
curl http://localhost:8080/instance/connect/mi-whatsapp \
  -H "apikey: TU_API_KEY"
```

### Ver estado de conexión

```bash
curl http://localhost:8080/instance/connectionState/mi-whatsapp \
  -H "apikey: TU_API_KEY"
```

### Listar instancias

```bash
curl http://localhost:8080/instance/fetchInstances \
  -H "apikey: TU_API_KEY"
```

### Enviar mensaje de texto

```bash
curl -X POST http://localhost:8080/message/sendText/mi-whatsapp \
  -H "apikey: TU_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "number": "595981123456",
    "text": "Hola desde TAGUATO-SEND!"
  }'
```

> **Nota:** El número debe incluir código de país sin `+`. Paraguay: `595`, Argentina: `54`, Brasil: `55`.

### Enviar imagen

```bash
curl -X POST http://localhost:8080/message/sendMedia/mi-whatsapp \
  -H "apikey: TU_API_KEY" \
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
curl -X POST http://localhost:8080/message/sendMedia/mi-whatsapp \
  -H "apikey: TU_API_KEY" \
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
curl -X POST http://localhost:8080/webhook/set/mi-whatsapp \
  -H "apikey: TU_API_KEY" \
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
curl -X DELETE http://localhost:8080/instance/delete/mi-whatsapp \
  -H "apikey: TU_API_KEY"
```

## Scripts de Utilidad

```bash
./scripts/start.sh          # Iniciar todos los servicios
./scripts/stop.sh           # Detener todos los servicios
./scripts/logs.sh           # Ver logs de todos los servicios
./scripts/logs.sh taguato-api  # Ver logs solo de la API
./scripts/backup-db.sh      # Crear backup de la base de datos
```

## Estructura del Proyecto

```
TAGUATO-SEND/
├── docker-compose.yml      # Orquestación de servicios
├── .env                    # Variables de entorno (no se commitea)
├── .env.example            # Template de variables
├── .gitignore              # Exclusiones de Git
├── README.md               # Esta documentación
└── scripts/
    ├── start.sh            # Iniciar servicios
    ├── stop.sh             # Detener servicios
    ├── logs.sh             # Ver logs
    └── backup-db.sh        # Backup de DB
```
