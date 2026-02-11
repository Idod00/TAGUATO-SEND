# 01 - Panel Web + Auth + Instancias + API Docs

**Estado:** Completado
**Commit:** `1653776`

## Objetivo
Panel web para gestion de instancias WhatsApp con autenticacion, CRUD de instancias y documentacion de API integrada.

## Archivos principales
- `gateway/panel/index.html` - SPA principal
- `gateway/panel/css/style.css` - Estilos
- `gateway/panel/js/api.js` - Cliente API
- `gateway/panel/js/app.js` - Logica de la aplicacion
- `gateway/panel/js/docs-data.js` - Datos de la documentacion API
- `gateway/lua/panel_auth.lua` - Endpoints de auth del panel

## Cambios clave
- Login/logout con tokens
- CRUD de instancias (crear, conectar via QR, eliminar)
- Envio de mensajes de texto individuales
- Seccion de documentacion API interactiva
