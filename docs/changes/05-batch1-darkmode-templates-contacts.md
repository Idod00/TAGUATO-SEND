# 05 - Batch 1: Dark Mode + Templates + Contactos

**Estado:** Completado
**Commit:** `5bbaa68`

## Objetivo
Tema oscuro, plantillas de mensajes reutilizables y listas de contactos.

## Archivos creados/modificados
- `gateway/lua/templates.lua` - **Nuevo** - CRUD de plantillas
- `gateway/lua/contacts.lua` - **Nuevo** - CRUD de listas de contactos + items
- `gateway/nginx.conf` - Locations para `/api/templates` y `/api/contacts`
- `gateway/panel/css/style.css` - Variables CSS + tema oscuro con `[data-theme="dark"]`
- `gateway/panel/index.html` - Secciones de templates y contactos, toggle tema
- `gateway/panel/js/api.js` - Funciones de templates y contactos
- `gateway/panel/js/app.js` - Logica de templates, contactos, dark mode
- `db/init.sql` - Tablas: `message_templates`, `contact_lists`, `contact_list_items`

## Cambios clave
- Dark mode persistente via localStorage
- CRUD completo de plantillas con selector en formulario de mensajes
- Listas de contactos con items (telefono + etiqueta)
- Cargar lista de contactos directamente en textarea de bulk
