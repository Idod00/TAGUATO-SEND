# 10 - Programacion de Envios (Scheduled Messages)

**Estado:** Completado
**Commit:** Pendiente de commit

## Objetivo
Permitir a los usuarios programar envios de mensajes (individuales o masivos) para una fecha/hora futura, ejecutados automaticamente por un worker server-side.

## Archivos creados
| Archivo | Descripcion |
|---------|-------------|
| `gateway/lua/scheduled.lua` | CRUD handler para mensajes programados |
| `gateway/lua/scheduled_worker.lua` | Worker background que ejecuta los envios |

## Archivos modificados
| Archivo | Cambios |
|---------|---------|
| `db/init.sql` | Tabla `taguato.scheduled_messages` + indices |
| `gateway/nginx.conf` | Location `/api/scheduled` + timer worker (60s) |
| `gateway/panel/css/style.css` | Badges `badge-warning` y `badge-info` + dark mode |
| `gateway/panel/index.html` | Nav link "Programados", seccion con form/filtros/lista, modales |
| `gateway/panel/js/api.js` | 5 funciones: list, create, get, update, cancel |
| `gateway/panel/js/app.js` | Logica completa de la seccion programados |

## Detalle de cambios

### Base de datos
```sql
CREATE TABLE taguato.scheduled_messages (
    id SERIAL PRIMARY KEY,
    user_id INT NOT NULL REFERENCES taguato.users(id) ON DELETE CASCADE,
    instance_name VARCHAR(255) NOT NULL,
    message_type VARCHAR(20) DEFAULT 'text',    -- text, image, document, audio, video
    message_content TEXT NOT NULL,               -- texto plano o JSON para media
    recipients TEXT NOT NULL,                    -- JSON array ["595...","595..."]
    scheduled_at TIMESTAMP NOT NULL,
    status VARCHAR(20) DEFAULT 'pending',        -- pending, processing, completed, failed, cancelled
    results JSONB,                               -- {total, sent, failed, errors}
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);
```

### API Endpoints (scheduled.lua)
- `GET /api/scheduled` - Listar (paginado, filtro por status)
- `GET /api/scheduled/{id}` - Detalle con resultados
- `POST /api/scheduled` - Crear (valida ownership de instancia)
- `PUT /api/scheduled/{id}` - Actualizar (solo status=pending)
- `DELETE /api/scheduled/{id}` - Cancelar (solo status=pending)

### Worker (scheduled_worker.lua)
- Corre cada 60 segundos (primer run a los 45s)
- Busca hasta 5 mensajes pendientes cuya `scheduled_at <= NOW()`
- Para cada mensaje:
  1. Marca como `processing`
  2. Parsea recipients JSON
  3. Envia cada numero via `resty.http` a Evolution API (sendText o sendMedia)
  4. Delay de 1 segundo entre envios
  5. Registra cada envio en `message_logs`
  6. Actualiza status a `completed` o `failed` con resultados JSON
- Limpieza automatica de registros >30 dias

### Frontend
- Formulario: instancia, destinatarios (textarea + cargar lista), tipo, plantilla, mensaje, fecha/hora
- Soporte para media (URL + caption cuando tipo != text)
- Lista con filtro por estado y paginacion
- Modal de detalle: info, mensaje, destinatarios, resultados con errores
- Badges de estado: Pendiente (amarillo), Enviando (azul), Completado (verde), Fallido (rojo), Cancelado (gris)

## Notas de deploy
```bash
# Si la DB ya existe, ejecutar manualmente:
docker compose exec postgres psql -U taguato -d evolution -c "
CREATE TABLE IF NOT EXISTS taguato.scheduled_messages (...);
CREATE INDEX IF NOT EXISTS idx_scheduled_user ON taguato.scheduled_messages(user_id);
CREATE INDEX IF NOT EXISTS idx_scheduled_pending ON taguato.scheduled_messages(status, scheduled_at) WHERE status = 'pending';
"

# Luego rebuild:
docker compose up --build -d
```

## Verificacion
1. Crear envio programado 2 min en el futuro
2. Verificar aparece como "Pendiente" en la lista
3. Esperar ejecucion del worker (logs: `docker compose logs -f gateway`)
4. Verificar cambio a "Enviando..." y luego "Completado"
5. Ver detalle con resultados (enviados/fallidos)
6. Cancelar un envio pendiente
7. Verificar que los envios aparecen en Historial (message_logs)
