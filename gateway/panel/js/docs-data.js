// API Documentation Data for TAGUATO-SEND
const DOCS_DATA = [
  {
    tag: 'Estado del Sistema',
    description: 'Endpoints publicos para verificar el estado de los servicios. No requieren autenticacion.',
    endpoints: [
      {
        method: 'GET',
        path: '/health',
        summary: 'Health check basico',
        description: 'Verifica la conectividad con la base de datos. Retorna 200 si todo esta operacional o 503 si hay problemas.',
        auth: false,
        response: {
          status: 'ok',
          database: 'connected'
        }
      },
      {
        method: 'GET',
        path: '/api/status',
        summary: 'Estado detallado de servicios',
        description: 'Retorna el estado de todos los servicios (Gateway, Evolution API, PostgreSQL, Redis), incidentes activos, mantenimientos programados, porcentajes de uptime (30 dias) y tiempos de respuesta. Los resultados se cachean en Redis por 15 segundos.',
        auth: false,
        response: {
          overall_status: 'operational',
          services: [
            { name: 'Gateway', status: 'operational', response_time: 0 },
            { name: 'Evolution API', status: 'operational', response_time: 45 },
            { name: 'PostgreSQL', status: 'operational', response_time: 3 },
            { name: 'Redis', status: 'operational', response_time: 1 }
          ],
          active_incidents: [],
          recent_incidents: [],
          scheduled_maintenances: [],
          uptime: { 'Evolution API': 99.95, 'PostgreSQL': 100, 'Redis': 100 },
          uptime_daily: {},
          response_time_history: {},
          cached: false,
          checked_at: 'Thu, 01 Jan 2025 00:00:00 GMT'
        }
      }
    ]
  },
  {
    tag: 'Autenticacion',
    description: 'Endpoints para login, perfil y cambio de contrasena del panel. Las sesiones expiran en 24 horas con extension automatica por actividad (sliding window).',
    endpoints: [
      {
        method: 'POST',
        path: '/api/auth/login',
        summary: 'Iniciar sesion',
        description: 'Autentica un usuario con username y password. Retorna un token API para usar en solicitudes posteriores. La sesion tiene un TTL de 24 horas que se renueva con cada actividad. Incluye proteccion contra fuerza bruta.',
        auth: false,
        body: {
          username: 'mi_usuario',
          password: 'mi_contrasena'
        },
        response: {
          token: 'a1b2c3d4e5f6...',
          user: {
            id: 1,
            username: 'mi_usuario',
            role: 'user',
            max_instances: 3,
            is_active: true,
            must_change_password: false
          }
        }
      },
      {
        method: 'GET',
        path: '/api/auth/me',
        summary: 'Obtener perfil del usuario actual',
        description: 'Retorna la informacion del usuario autenticado junto con sus instancias asignadas. Verifica que la sesion no haya expirado y extiende automaticamente el TTL por 24 horas adicionales.',
        auth: true,
        response: {
          user: {
            id: 1,
            username: 'mi_usuario',
            role: 'user',
            max_instances: 3,
            is_active: true,
            must_change_password: false
          },
          instances: ['mi-instancia-1', 'mi-instancia-2']
        },
        errors: [
          { status: 401, description: 'Session expired, please login again - La sesion ha expirado' }
        ]
      },
      {
        method: 'POST',
        path: '/api/auth/change-password',
        summary: 'Cambiar contrasena',
        description: 'Cambia la contrasena del usuario autenticado. Requiere la contrasena actual para verificacion.',
        auth: true,
        body: {
          current_password: 'contrasena_actual',
          new_password: 'nueva_contrasena'
        },
        response: {
          message: 'Password updated successfully'
        }
      }
    ]
  },
  {
    tag: 'Instancias',
    description: 'Gestion de instancias WhatsApp. Los usuarios solo pueden acceder a sus propias instancias. Admin puede acceder a todas.',
    endpoints: [
      {
        method: 'GET',
        path: '/instance/fetchInstances',
        summary: 'Listar instancias',
        description: 'Retorna las instancias del usuario autenticado. Admin recibe todas las instancias del sistema.',
        auth: true,
        response: [
          {
            instance: {
              instanceName: 'mi-instancia',
              instanceId: 'abc123',
              owner: 'mi_usuario',
              state: 'open'
            }
          }
        ]
      },
      {
        method: 'POST',
        path: '/instance/create',
        summary: 'Crear instancia',
        description: 'Crea una nueva instancia WhatsApp. El usuario debe tener cupo disponible segun su limite de max_instances.',
        auth: true,
        body: {
          instanceName: 'nueva-instancia',
          integration: 'WHATSAPP-BAILEYS'
        },
        response: {
          instance: {
            instanceName: 'nueva-instancia',
            instanceId: 'def456',
            status: 'created'
          },
          hash: { apikey: 'instance-api-key' }
        }
      },
      {
        method: 'GET',
        path: '/instance/connect/{instanceName}',
        summary: 'Conectar instancia (obtener QR)',
        description: 'Genera un codigo QR para vincular la instancia con WhatsApp. El QR expira en ~40 segundos.',
        auth: true,
        params: [
          { name: 'instanceName', in: 'path', required: true, description: 'Nombre de la instancia' }
        ],
        response: {
          base64: 'data:image/png;base64,...',
          pairingCode: null
        }
      },
      {
        method: 'GET',
        path: '/instance/connectionState/{instanceName}',
        summary: 'Estado de conexion',
        description: 'Consulta el estado actual de conexion de una instancia (open, close, connecting).',
        auth: true,
        params: [
          { name: 'instanceName', in: 'path', required: true, description: 'Nombre de la instancia' }
        ],
        response: {
          instance: {
            instanceName: 'mi-instancia',
            state: 'open'
          }
        }
      },
      {
        method: 'DELETE',
        path: '/instance/delete/{instanceName}',
        summary: 'Eliminar instancia',
        description: 'Elimina permanentemente una instancia WhatsApp y desvincula la asociacion con el usuario.',
        auth: true,
        params: [
          { name: 'instanceName', in: 'path', required: true, description: 'Nombre de la instancia a eliminar' }
        ],
        response: {
          status: 'SUCCESS',
          message: 'Instance deleted'
        }
      }
    ]
  },
  {
    tag: 'Mensajes',
    description: 'Envio de mensajes a traves de instancias WhatsApp conectadas. Rate limit global: 5 req/s por IP, burst 10. Rate limit por usuario configurable por admin.',
    endpoints: [
      {
        method: 'POST',
        path: '/message/sendText/{instanceName}',
        summary: 'Enviar mensaje de texto',
        description: 'Envia un mensaje de texto a un numero de WhatsApp a traves de la instancia especificada. El numero debe incluir el codigo de pais sin el "+".',
        auth: true,
        params: [
          { name: 'instanceName', in: 'path', required: true, description: 'Nombre de la instancia conectada' }
        ],
        body: {
          number: '595981123456',
          text: 'Hola, este es un mensaje de prueba'
        },
        response: {
          key: {
            remoteJid: '595981123456@s.whatsapp.net',
            fromMe: true,
            id: 'BAE5F2...'
          },
          message: { conversation: 'Hola, este es un mensaje de prueba' },
          messageTimestamp: '1700000000',
          status: 'PENDING'
        },
        errors: [
          { status: 429, description: 'Rate limit exceeded - Se incluye header Retry-After: 60' }
        ]
      },
      {
        method: 'POST',
        path: '/message/sendMedia/{instanceName}',
        summary: 'Enviar archivo multimedia',
        description: 'Envia una imagen, documento u otro archivo multimedia. Se puede incluir un caption opcional.',
        auth: true,
        params: [
          { name: 'instanceName', in: 'path', required: true, description: 'Nombre de la instancia conectada' }
        ],
        body: {
          number: '595981123456',
          mediatype: 'image',
          media: 'https://example.com/imagen.jpg',
          caption: 'Mira esta imagen',
          fileName: 'imagen.jpg'
        },
        response: {
          key: {
            remoteJid: '595981123456@s.whatsapp.net',
            fromMe: true,
            id: 'BAE5F2...'
          },
          status: 'PENDING'
        }
      }
    ]
  },
  {
    tag: 'Historial de Mensajes',
    description: 'Registro y consulta de mensajes enviados. Permite paginacion, filtros y exportacion a CSV.',
    endpoints: [
      {
        method: 'POST',
        path: '/api/messages/log',
        summary: 'Registrar envio de mensaje',
        description: 'Registra un intento de envio de mensaje en el historial del usuario.',
        auth: true,
        body: {
          instance_name: 'mi-instancia',
          phone_number: '595981123456',
          message_type: 'text',
          status: 'sent',
          error_message: null
        },
        response: {
          log: {
            id: 1,
            instance_name: 'mi-instancia',
            phone_number: '595981123456',
            message_type: 'text',
            status: 'sent',
            error_message: null,
            created_at: '2025-01-15T10:00:00Z'
          }
        }
      },
      {
        method: 'GET',
        path: '/api/messages/log',
        summary: 'Listar historial de mensajes',
        description: 'Retorna el historial de mensajes enviados con paginacion y filtros opcionales. Limite maximo: 100 por pagina.',
        auth: true,
        params: [
          { name: 'page', in: 'query', required: false, description: 'Numero de pagina (default: 1)' },
          { name: 'limit', in: 'query', required: false, description: 'Resultados por pagina (default: 50, max: 100)' },
          { name: 'status', in: 'query', required: false, description: 'Filtrar por estado: sent, failed, pending' },
          { name: 'message_type', in: 'query', required: false, description: 'Filtrar por tipo: text, image, document, etc.' },
          { name: 'instance_name', in: 'query', required: false, description: 'Filtrar por nombre de instancia' },
          { name: 'date_from', in: 'query', required: false, description: 'Fecha inicio (ISO 8601)' },
          { name: 'date_to', in: 'query', required: false, description: 'Fecha fin (ISO 8601)' }
        ],
        response: {
          logs: [
            {
              id: 1,
              instance_name: 'mi-instancia',
              phone_number: '595981123456',
              message_type: 'text',
              status: 'sent',
              error_message: null,
              created_at: '2025-01-15T10:00:00Z'
            }
          ],
          total: 150,
          page: 1,
          limit: 50,
          pages: 3
        }
      },
      {
        method: 'GET',
        path: '/api/messages/export',
        summary: 'Exportar historial como CSV',
        description: 'Descarga el historial de mensajes en formato CSV. Acepta los mismos filtros que GET /api/messages/log. Maximo 10,000 registros por exportacion.',
        auth: true,
        params: [
          { name: 'status', in: 'query', required: false, description: 'Filtrar por estado' },
          { name: 'message_type', in: 'query', required: false, description: 'Filtrar por tipo' },
          { name: 'instance_name', in: 'query', required: false, description: 'Filtrar por instancia' },
          { name: 'date_from', in: 'query', required: false, description: 'Fecha inicio' },
          { name: 'date_to', in: 'query', required: false, description: 'Fecha fin' }
        ],
        response: 'Archivo CSV con headers: ID,Instance,Phone,Type,Status,Error,Date'
      }
    ]
  },
  {
    tag: 'Plantillas de Mensajes',
    description: 'CRUD de plantillas de mensajes reutilizables. Cada usuario gestiona sus propias plantillas.',
    endpoints: [
      {
        method: 'GET',
        path: '/api/templates',
        summary: 'Listar plantillas',
        description: 'Retorna todas las plantillas del usuario autenticado, ordenadas por ultima modificacion.',
        auth: true,
        response: {
          templates: [
            {
              id: 1,
              name: 'Saludo inicial',
              content: 'Hola {nombre}, bienvenido a nuestro servicio.',
              created_at: '2025-01-15T10:00:00Z',
              updated_at: '2025-01-15T10:00:00Z'
            }
          ]
        }
      },
      {
        method: 'POST',
        path: '/api/templates',
        summary: 'Crear plantilla',
        description: 'Crea una nueva plantilla de mensaje. Nombre maximo: 100 caracteres. Contenido maximo: 5,000 caracteres.',
        auth: true,
        body: {
          name: 'Saludo inicial',
          content: 'Hola {nombre}, bienvenido a nuestro servicio.'
        },
        response: {
          template: {
            id: 1,
            name: 'Saludo inicial',
            content: 'Hola {nombre}, bienvenido a nuestro servicio.',
            created_at: '2025-01-15T10:00:00Z',
            updated_at: '2025-01-15T10:00:00Z'
          }
        }
      },
      {
        method: 'PUT',
        path: '/api/templates/{id}',
        summary: 'Actualizar plantilla',
        description: 'Actualiza el nombre y/o contenido de una plantilla existente.',
        auth: true,
        params: [
          { name: 'id', in: 'path', required: true, description: 'ID de la plantilla' }
        ],
        body: {
          name: 'Saludo actualizado',
          content: 'Hola {nombre}, gracias por elegirnos.'
        },
        response: {
          template: {
            id: 1,
            name: 'Saludo actualizado',
            content: 'Hola {nombre}, gracias por elegirnos.',
            created_at: '2025-01-15T10:00:00Z',
            updated_at: '2025-01-16T12:00:00Z'
          }
        }
      },
      {
        method: 'DELETE',
        path: '/api/templates/{id}',
        summary: 'Eliminar plantilla',
        description: 'Elimina permanentemente una plantilla del usuario.',
        auth: true,
        params: [
          { name: 'id', in: 'path', required: true, description: 'ID de la plantilla' }
        ],
        response: {
          deleted: { id: 1, name: 'Saludo actualizado' }
        }
      }
    ]
  },
  {
    tag: 'Listas de Contactos',
    description: 'Gestion de listas de contactos para envios masivos. Cada lista contiene items con numero de telefono y etiqueta.',
    endpoints: [
      {
        method: 'GET',
        path: '/api/contacts',
        summary: 'Listar listas de contactos',
        description: 'Retorna todas las listas de contactos del usuario con el conteo de items en cada una.',
        auth: true,
        response: {
          lists: [
            {
              id: 1,
              name: 'Clientes VIP',
              item_count: 25,
              created_at: '2025-01-15T10:00:00Z',
              updated_at: '2025-01-15T10:00:00Z'
            }
          ]
        }
      },
      {
        method: 'POST',
        path: '/api/contacts',
        summary: 'Crear lista de contactos',
        description: 'Crea una nueva lista de contactos vacia.',
        auth: true,
        body: {
          name: 'Clientes VIP'
        },
        response: {
          list: {
            id: 1,
            name: 'Clientes VIP',
            created_at: '2025-01-15T10:00:00Z',
            updated_at: '2025-01-15T10:00:00Z'
          }
        }
      },
      {
        method: 'GET',
        path: '/api/contacts/{id}',
        summary: 'Obtener lista con items',
        description: 'Retorna los detalles de una lista junto con todos sus contactos.',
        auth: true,
        params: [
          { name: 'id', in: 'path', required: true, description: 'ID de la lista' }
        ],
        response: {
          list: {
            id: 1,
            name: 'Clientes VIP',
            created_at: '2025-01-15T10:00:00Z',
            updated_at: '2025-01-15T10:00:00Z',
            items: [
              { id: 1, phone_number: '595981123456', label: 'Juan Perez', created_at: '2025-01-15T10:00:00Z' }
            ]
          }
        }
      },
      {
        method: 'PUT',
        path: '/api/contacts/{id}',
        summary: 'Renombrar lista',
        description: 'Cambia el nombre de una lista de contactos existente.',
        auth: true,
        params: [
          { name: 'id', in: 'path', required: true, description: 'ID de la lista' }
        ],
        body: {
          name: 'Clientes Premium'
        },
        response: {
          list: {
            id: 1,
            name: 'Clientes Premium',
            updated_at: '2025-01-16T12:00:00Z'
          }
        }
      },
      {
        method: 'DELETE',
        path: '/api/contacts/{id}',
        summary: 'Eliminar lista',
        description: 'Elimina una lista de contactos y todos sus items de forma permanente.',
        auth: true,
        params: [
          { name: 'id', in: 'path', required: true, description: 'ID de la lista' }
        ],
        response: {
          deleted: { id: 1, name: 'Clientes Premium' }
        }
      },
      {
        method: 'POST',
        path: '/api/contacts/{id}/items',
        summary: 'Agregar contacto(s) a lista',
        description: 'Agrega uno o multiples contactos a una lista. Se puede enviar un solo contacto o un array de items. Los numeros de telefono son validados.',
        auth: true,
        params: [
          { name: 'id', in: 'path', required: true, description: 'ID de la lista' }
        ],
        body: {
          items: [
            { phone_number: '595981123456', label: 'Juan Perez' },
            { phone_number: '595982654321', label: 'Maria Lopez' }
          ]
        },
        response: {
          items: [
            { id: 1, phone_number: '595981123456', label: 'Juan Perez', created_at: '2025-01-15T10:00:00Z' },
            { id: 2, phone_number: '595982654321', label: 'Maria Lopez', created_at: '2025-01-15T10:00:00Z' }
          ]
        }
      },
      {
        method: 'DELETE',
        path: '/api/contacts/{id}/items/{item_id}',
        summary: 'Eliminar contacto de lista',
        description: 'Elimina un contacto especifico de una lista.',
        auth: true,
        params: [
          { name: 'id', in: 'path', required: true, description: 'ID de la lista' },
          { name: 'item_id', in: 'path', required: true, description: 'ID del contacto' }
        ],
        response: {
          deleted: { id: 1 }
        }
      }
    ]
  },
  {
    tag: 'Mensajes Programados',
    description: 'Programacion de envios masivos para una fecha y hora futura. Los mensajes se ejecutan automaticamente en la hora programada.',
    endpoints: [
      {
        method: 'GET',
        path: '/api/scheduled',
        summary: 'Listar mensajes programados',
        description: 'Retorna los mensajes programados del usuario con paginacion. Se puede filtrar por estado.',
        auth: true,
        params: [
          { name: 'page', in: 'query', required: false, description: 'Numero de pagina (default: 1)' },
          { name: 'limit', in: 'query', required: false, description: 'Resultados por pagina (default: 20, max: 100)' },
          { name: 'status', in: 'query', required: false, description: 'Filtrar por estado: pending, processing, completed, cancelled, failed' }
        ],
        response: {
          messages: [
            {
              id: 1,
              instance_name: 'mi-instancia',
              message_type: 'text',
              message_content: 'Recordatorio de cita manana',
              recipients: ['595981123456', '595982654321'],
              scheduled_at: '2025-01-20T14:00:00Z',
              status: 'pending',
              results: null,
              created_at: '2025-01-15T10:00:00Z',
              updated_at: '2025-01-15T10:00:00Z'
            }
          ],
          total: 5,
          page: 1,
          limit: 20,
          pages: 1
        }
      },
      {
        method: 'GET',
        path: '/api/scheduled/{id}',
        summary: 'Detalle de mensaje programado',
        description: 'Retorna el detalle completo de un mensaje programado, incluyendo resultados de envio si ya fue ejecutado.',
        auth: true,
        params: [
          { name: 'id', in: 'path', required: true, description: 'ID del mensaje programado' }
        ],
        response: {
          message: {
            id: 1,
            instance_name: 'mi-instancia',
            message_type: 'text',
            message_content: 'Recordatorio de cita manana',
            recipients: ['595981123456', '595982654321'],
            scheduled_at: '2025-01-20T14:00:00Z',
            status: 'completed',
            results: { sent: 2, failed: 0 },
            created_at: '2025-01-15T10:00:00Z',
            updated_at: '2025-01-20T14:00:05Z'
          }
        }
      },
      {
        method: 'POST',
        path: '/api/scheduled',
        summary: 'Crear mensaje programado',
        description: 'Programa un envio masivo para una fecha futura. Maximo 500 destinatarios por mensaje. El contenido puede tener hasta 5,000 caracteres. Se verifica la propiedad de la instancia.',
        auth: true,
        body: {
          instance_name: 'mi-instancia',
          message_type: 'text',
          message_content: 'Recordatorio de cita manana a las 10:00',
          recipients: ['595981123456', '595982654321'],
          scheduled_at: '2025-01-20T14:00:00'
        },
        response: {
          message: {
            id: 1,
            instance_name: 'mi-instancia',
            message_type: 'text',
            message_content: 'Recordatorio de cita manana a las 10:00',
            recipients: ['595981123456', '595982654321'],
            scheduled_at: '2025-01-20T14:00:00Z',
            status: 'pending',
            created_at: '2025-01-15T10:00:00Z'
          }
        }
      },
      {
        method: 'PUT',
        path: '/api/scheduled/{id}',
        summary: 'Actualizar mensaje programado',
        description: 'Modifica un mensaje programado. Solo se pueden editar mensajes con estado "pending". Se pueden actualizar campos individuales.',
        auth: true,
        params: [
          { name: 'id', in: 'path', required: true, description: 'ID del mensaje programado' }
        ],
        body: {
          message_content: 'Contenido actualizado',
          scheduled_at: '2025-01-21T16:00:00',
          recipients: ['595981123456']
        },
        response: {
          message: {
            id: 1,
            instance_name: 'mi-instancia',
            message_type: 'text',
            message_content: 'Contenido actualizado',
            recipients: ['595981123456'],
            scheduled_at: '2025-01-21T16:00:00Z',
            status: 'pending',
            created_at: '2025-01-15T10:00:00Z',
            updated_at: '2025-01-16T12:00:00Z'
          }
        },
        errors: [
          { status: 400, description: 'Only pending messages can be updated' }
        ]
      },
      {
        method: 'DELETE',
        path: '/api/scheduled/{id}',
        summary: 'Cancelar mensaje programado',
        description: 'Cancela un mensaje programado. Solo se pueden cancelar mensajes con estado "pending". El mensaje no se elimina, se marca como "cancelled".',
        auth: true,
        params: [
          { name: 'id', in: 'path', required: true, description: 'ID del mensaje programado' }
        ],
        response: {
          message: { id: 1, status: 'cancelled' }
        },
        errors: [
          { status: 400, description: 'Only pending messages can be cancelled' }
        ]
      }
    ]
  },
  {
    tag: 'Webhooks',
    description: 'Configuracion de webhooks para recibir notificaciones de eventos en tiempo real. Un webhook por instancia. Si la configuracion falla, se marca para reintento automatico.',
    endpoints: [
      {
        method: 'GET',
        path: '/api/webhooks',
        summary: 'Listar webhooks',
        description: 'Retorna todos los webhooks configurados por el usuario.',
        auth: true,
        response: {
          webhooks: [
            {
              id: 1,
              instance_name: 'mi-instancia',
              webhook_url: 'https://mi-servidor.com/webhook',
              events: ['MESSAGES_UPSERT', 'CONNECTION_UPDATE'],
              is_active: true,
              created_at: '2025-01-15T10:00:00Z',
              updated_at: '2025-01-15T10:00:00Z'
            }
          ]
        }
      },
      {
        method: 'POST',
        path: '/api/webhooks',
        summary: 'Crear webhook',
        description: 'Configura un webhook para recibir eventos de una instancia. La URL debe comenzar con http:// o https://. Solo un webhook por instancia. Se configura automaticamente en la Evolution API.',
        auth: true,
        body: {
          instance_name: 'mi-instancia',
          webhook_url: 'https://mi-servidor.com/webhook',
          events: [
            'MESSAGES_UPSERT',
            'CONNECTION_UPDATE',
            'QRCODE_UPDATED'
          ]
        },
        response: {
          webhook: {
            id: 1,
            instance_name: 'mi-instancia',
            webhook_url: 'https://mi-servidor.com/webhook',
            events: ['MESSAGES_UPSERT', 'CONNECTION_UPDATE', 'QRCODE_UPDATED'],
            is_active: true,
            created_at: '2025-01-15T10:00:00Z'
          }
        },
        errors: [
          { status: 409, description: 'Webhook already exists for this instance' }
        ]
      },
      {
        method: 'DELETE',
        path: '/api/webhooks/{id}',
        summary: 'Eliminar webhook',
        description: 'Elimina un webhook y remueve la configuracion de la Evolution API.',
        auth: true,
        params: [
          { name: 'id', in: 'path', required: true, description: 'ID del webhook' }
        ],
        response: {
          deleted: { id: 1 }
        }
      }
    ]
  },
  {
    tag: 'Sesiones',
    description: 'Gestion de sesiones activas del usuario. Las sesiones expiran en 24 horas y se extienden con actividad.',
    endpoints: [
      {
        method: 'GET',
        path: '/api/sessions',
        summary: 'Listar mis sesiones',
        description: 'Retorna todas las sesiones activas del usuario autenticado.',
        auth: true,
        response: {
          sessions: [
            {
              id: 1,
              ip_address: '192.168.1.100',
              user_agent: 'Mozilla/5.0...',
              last_active: '2025-01-15T10:00:00Z',
              is_active: true,
              created_at: '2025-01-15T08:00:00Z'
            }
          ]
        }
      },
      {
        method: 'DELETE',
        path: '/api/sessions/{id}',
        summary: 'Revocar sesion propia',
        description: 'Revoca (cierra) una sesion activa del usuario autenticado.',
        auth: true,
        params: [
          { name: 'id', in: 'path', required: true, description: 'ID de la sesion' }
        ],
        response: {
          revoked: { id: 1 }
        }
      }
    ]
  },
  {
    tag: 'Dashboard de Usuario',
    description: 'Metricas y estadisticas del usuario autenticado.',
    endpoints: [
      {
        method: 'GET',
        path: '/api/user/dashboard',
        summary: 'Obtener estadisticas del usuario',
        description: 'Retorna metricas de mensajes (hoy, semana, mes, total), tasa de entrega, cantidad de instancias y grafico diario de los ultimos 7 dias.',
        auth: true,
        response: {
          messages_today: 45,
          messages_week: 312,
          messages_month: 1250,
          messages_total: 8500,
          delivery_rate: 97,
          instances: 2,
          max_instances: 3,
          daily: [
            { day: '2025-01-09', count: 40 },
            { day: '2025-01-10', count: 55 },
            { day: '2025-01-11', count: 38 },
            { day: '2025-01-12', count: 62 },
            { day: '2025-01-13', count: 48 },
            { day: '2025-01-14', count: 69 },
            { day: '2025-01-15', count: 45 }
          ]
        }
      }
    ]
  },
  {
    tag: 'Admin - Usuarios',
    description: 'Gestion de usuarios del sistema. Solo accesible para usuarios con rol admin.',
    adminOnly: true,
    endpoints: [
      {
        method: 'POST',
        path: '/admin/users',
        summary: 'Crear usuario',
        description: 'Crea un nuevo usuario en el sistema. Se genera automaticamente un token API unico. El campo rate_limit es opcional y configura el limite de peticiones por minuto del usuario (0 o null = sin limite).',
        auth: true,
        adminOnly: true,
        body: {
          username: 'nuevo_usuario',
          password: 'contrasena123',
          role: 'user',
          max_instances: 3,
          rate_limit: 100
        },
        response: {
          user: {
            id: 5,
            username: 'nuevo_usuario',
            role: 'user',
            api_token: 'a1b2c3d4...',
            max_instances: 3,
            is_active: true,
            must_change_password: true
          }
        }
      },
      {
        method: 'GET',
        path: '/admin/users',
        summary: 'Listar usuarios',
        description: 'Retorna la lista de todos los usuarios registrados en el sistema.',
        auth: true,
        adminOnly: true,
        response: {
          users: [
            {
              id: 1,
              username: 'admin',
              role: 'admin',
              max_instances: 0,
              is_active: true
            },
            {
              id: 2,
              username: 'usuario1',
              role: 'user',
              max_instances: 3,
              is_active: true
            }
          ]
        }
      },
      {
        method: 'GET',
        path: '/admin/users/{id}',
        summary: 'Obtener usuario con instancias',
        description: 'Retorna los detalles de un usuario especifico junto con la lista de sus instancias asignadas.',
        auth: true,
        adminOnly: true,
        params: [
          { name: 'id', in: 'path', required: true, description: 'ID del usuario' }
        ],
        response: {
          user: {
            id: 2,
            username: 'usuario1',
            role: 'user',
            api_token: 'a1b2c3d4...',
            max_instances: 3,
            is_active: true
          },
          instances: [
            { instance_name: 'instancia-1', created_at: '2024-01-15T10:00:00Z' }
          ]
        }
      },
      {
        method: 'PUT',
        path: '/admin/users/{id}',
        summary: 'Actualizar usuario',
        description: 'Actualiza los campos de un usuario. Solo se envian los campos que se desean cambiar. Usar regenerate_token para generar un nuevo API token. El campo rate_limit configura peticiones por minuto (0 o null = sin limite).',
        auth: true,
        adminOnly: true,
        params: [
          { name: 'id', in: 'path', required: true, description: 'ID del usuario' }
        ],
        body: {
          max_instances: 5,
          is_active: true,
          role: 'user',
          password: 'nueva_contrasena',
          rate_limit: 200,
          regenerate_token: false
        },
        response: {
          user: {
            id: 2,
            username: 'usuario1',
            role: 'user',
            api_token: 'a1b2c3d4...',
            max_instances: 5,
            is_active: true
          }
        }
      },
      {
        method: 'DELETE',
        path: '/admin/users/{id}',
        summary: 'Eliminar usuario',
        description: 'Elimina permanentemente un usuario y todas sus asociaciones de instancias del sistema. No se puede eliminar al propio usuario admin.',
        auth: true,
        adminOnly: true,
        params: [
          { name: 'id', in: 'path', required: true, description: 'ID del usuario a eliminar' }
        ],
        response: {
          user: {
            id: 2,
            username: 'usuario1',
            deleted: true
          }
        }
      }
    ]
  },
  {
    tag: 'Admin - Sesiones',
    description: 'Gestion de sesiones de todos los usuarios. Solo accesible para admin.',
    adminOnly: true,
    endpoints: [
      {
        method: 'GET',
        path: '/admin/sessions',
        summary: 'Listar todas las sesiones activas',
        description: 'Retorna todas las sesiones activas del sistema con informacion del usuario asociado.',
        auth: true,
        adminOnly: true,
        response: {
          sessions: [
            {
              id: 1,
              user_id: 2,
              username: 'usuario1',
              ip_address: '192.168.1.100',
              user_agent: 'Mozilla/5.0...',
              last_active: '2025-01-15T10:00:00Z',
              is_active: true,
              created_at: '2025-01-15T08:00:00Z'
            }
          ]
        }
      },
      {
        method: 'DELETE',
        path: '/admin/sessions/{id}',
        summary: 'Revocar cualquier sesion',
        description: 'Revoca la sesion de cualquier usuario del sistema.',
        auth: true,
        adminOnly: true,
        params: [
          { name: 'id', in: 'path', required: true, description: 'ID de la sesion' }
        ],
        response: {
          revoked: { id: 1, user_id: 2 }
        }
      }
    ]
  },
  {
    tag: 'Admin - Dashboard',
    description: 'Estadisticas globales del sistema. Solo accesible para admin.',
    adminOnly: true,
    endpoints: [
      {
        method: 'GET',
        path: '/admin/dashboard',
        summary: 'Dashboard del sistema',
        description: 'Retorna estadisticas globales: usuarios activos/totales, instancias registradas/conectadas, uptime de 30 dias, actividad reciente y reconexiones recientes.',
        auth: true,
        adminOnly: true,
        response: {
          users: { total: 15, active: 12 },
          instances: {
            total_registered: 25,
            total_evolution: 23,
            connected: 18
          },
          uptime_30d: 99.95,
          recent_activity: [
            { type: 'user_created', name: 'nuevo_usuario', created_at: '2025-01-15T10:00:00Z' },
            { type: 'instance_created', name: 'nueva-instancia', created_at: '2025-01-15T09:00:00Z' }
          ],
          recent_reconnections: [
            {
              instance_name: 'mi-instancia',
              previous_state: 'close',
              result: 'success',
              error_message: null,
              created_at: '2025-01-15T08:00:00Z'
            }
          ]
        }
      }
    ]
  },
  {
    tag: 'Admin - Incidentes',
    description: 'Gestion de incidentes para la pagina de estado publica. Solo accesible para admin.',
    adminOnly: true,
    endpoints: [
      {
        method: 'GET',
        path: '/admin/incidents/services',
        summary: 'Listar servicios disponibles',
        description: 'Retorna los servicios del sistema que pueden ser afectados por un incidente.',
        auth: true,
        adminOnly: true,
        response: {
          services: [
            { id: 1, name: 'Gateway', description: 'API Gateway', display_order: 1 },
            { id: 2, name: 'Evolution API', description: 'WhatsApp API', display_order: 2 }
          ]
        }
      },
      {
        method: 'GET',
        path: '/admin/incidents',
        summary: 'Listar incidentes',
        description: 'Retorna todos los incidentes con sus actualizaciones de timeline y servicios afectados. Los no resueltos aparecen primero.',
        auth: true,
        adminOnly: true,
        response: {
          incidents: [
            {
              id: 1,
              title: 'API con latencia elevada',
              severity: 'minor',
              status: 'investigating',
              created_at: '2025-01-15T10:00:00Z',
              updated_at: '2025-01-15T10:30:00Z',
              resolved_at: null,
              created_by_name: 'admin',
              affected_services: [{ id: 2, name: 'Evolution API' }],
              updates: [
                {
                  id: 1,
                  status: 'investigating',
                  message: 'Investigando la causa de la latencia elevada.',
                  created_at: '2025-01-15T10:00:00Z',
                  created_by_name: 'admin'
                }
              ]
            }
          ]
        }
      },
      {
        method: 'POST',
        path: '/admin/incidents',
        summary: 'Crear incidente',
        description: 'Crea un nuevo incidente con su primera actualizacion de timeline. Severidades: minor, major, critical. Estados: investigating, identified, monitoring, resolved.',
        auth: true,
        adminOnly: true,
        body: {
          title: 'API con latencia elevada',
          severity: 'minor',
          status: 'investigating',
          message: 'Investigando la causa de la latencia elevada.',
          service_ids: [2]
        },
        response: {
          incident: {
            id: 1,
            title: 'API con latencia elevada',
            severity: 'minor',
            status: 'investigating',
            created_at: '2025-01-15T10:00:00Z'
          }
        }
      },
      {
        method: 'POST',
        path: '/admin/incidents/{id}/updates',
        summary: 'Agregar actualizacion al timeline',
        description: 'Agrega una actualizacion al timeline de un incidente. Actualiza automaticamente el estado del incidente. Si el estado es "resolved", se registra la fecha de resolucion.',
        auth: true,
        adminOnly: true,
        params: [
          { name: 'id', in: 'path', required: true, description: 'ID del incidente' }
        ],
        body: {
          status: 'resolved',
          message: 'Se identifico y corrigio el problema. La latencia volvio a niveles normales.'
        },
        response: {
          update: {
            id: 2,
            status: 'resolved',
            message: 'Se identifico y corrigio el problema.',
            created_at: '2025-01-15T11:00:00Z'
          }
        }
      },
      {
        method: 'PUT',
        path: '/admin/incidents/{id}',
        summary: 'Actualizar metadatos del incidente',
        description: 'Modifica el titulo, severidad o servicios afectados de un incidente. Solo enviar los campos a actualizar.',
        auth: true,
        adminOnly: true,
        params: [
          { name: 'id', in: 'path', required: true, description: 'ID del incidente' }
        ],
        body: {
          title: 'Titulo actualizado',
          severity: 'major',
          service_ids: [1, 2]
        },
        response: {
          incident: {
            id: 1,
            title: 'Titulo actualizado',
            severity: 'major',
            status: 'investigating',
            updated_at: '2025-01-15T10:30:00Z'
          }
        }
      },
      {
        method: 'DELETE',
        path: '/admin/incidents/{id}',
        summary: 'Eliminar incidente',
        description: 'Elimina un incidente permanentemente junto con sus actualizaciones y servicios asociados.',
        auth: true,
        adminOnly: true,
        params: [
          { name: 'id', in: 'path', required: true, description: 'ID del incidente' }
        ],
        response: {
          deleted: { id: 1, title: 'API con latencia elevada' }
        }
      }
    ]
  },
  {
    tag: 'Admin - Mantenimiento',
    description: 'Programacion de ventanas de mantenimiento que se muestran en la pagina de estado publica. Solo accesible para admin.',
    adminOnly: true,
    endpoints: [
      {
        method: 'GET',
        path: '/admin/maintenance',
        summary: 'Listar mantenimientos',
        description: 'Retorna todos los mantenimientos programados con sus servicios afectados. Ordenados: en_progreso > programados > completados.',
        auth: true,
        adminOnly: true,
        response: {
          maintenances: [
            {
              id: 1,
              title: 'Actualizacion de base de datos',
              description: 'Migracion de esquema y optimizacion de indices.',
              scheduled_start: '2025-01-20T02:00:00Z',
              scheduled_end: '2025-01-20T04:00:00Z',
              status: 'scheduled',
              created_at: '2025-01-15T10:00:00Z',
              updated_at: '2025-01-15T10:00:00Z',
              created_by_name: 'admin',
              affected_services: [{ id: 3, name: 'PostgreSQL' }]
            }
          ]
        }
      },
      {
        method: 'POST',
        path: '/admin/maintenance',
        summary: 'Crear mantenimiento programado',
        description: 'Programa una ventana de mantenimiento. Se muestra automaticamente en la pagina de estado publica.',
        auth: true,
        adminOnly: true,
        body: {
          title: 'Actualizacion de base de datos',
          description: 'Migracion de esquema y optimizacion de indices.',
          scheduled_start: '2025-01-20T02:00:00',
          scheduled_end: '2025-01-20T04:00:00',
          service_ids: [3]
        },
        response: {
          maintenance: {
            id: 1,
            title: 'Actualizacion de base de datos',
            description: 'Migracion de esquema y optimizacion de indices.',
            scheduled_start: '2025-01-20T02:00:00Z',
            scheduled_end: '2025-01-20T04:00:00Z',
            status: 'scheduled',
            created_at: '2025-01-15T10:00:00Z'
          }
        }
      },
      {
        method: 'PUT',
        path: '/admin/maintenance/{id}',
        summary: 'Actualizar mantenimiento',
        description: 'Modifica un mantenimiento programado. Se puede cambiar titulo, descripcion, fechas, estado y servicios afectados. Estados: scheduled, in_progress, completed.',
        auth: true,
        adminOnly: true,
        params: [
          { name: 'id', in: 'path', required: true, description: 'ID del mantenimiento' }
        ],
        body: {
          status: 'in_progress',
          scheduled_end: '2025-01-20T05:00:00',
          service_ids: [3, 4]
        },
        response: {
          maintenance: {
            id: 1,
            title: 'Actualizacion de base de datos',
            description: 'Migracion de esquema y optimizacion de indices.',
            scheduled_start: '2025-01-20T02:00:00Z',
            scheduled_end: '2025-01-20T05:00:00Z',
            status: 'in_progress',
            updated_at: '2025-01-20T02:00:00Z'
          }
        }
      },
      {
        method: 'DELETE',
        path: '/admin/maintenance/{id}',
        summary: 'Eliminar mantenimiento',
        description: 'Elimina un mantenimiento programado permanentemente.',
        auth: true,
        adminOnly: true,
        params: [
          { name: 'id', in: 'path', required: true, description: 'ID del mantenimiento' }
        ],
        response: {
          deleted: { id: 1, title: 'Actualizacion de base de datos' }
        }
      }
    ]
  },
  {
    tag: 'Admin - Auditoria',
    description: 'Registro de auditoria del sistema. Todas las acciones administrativas se registran automaticamente. Solo accesible para admin.',
    adminOnly: true,
    endpoints: [
      {
        method: 'GET',
        path: '/admin/audit',
        summary: 'Listar registros de auditoria',
        description: 'Retorna los registros del log de auditoria con paginacion y filtros opcionales. Maximo 100 por pagina.',
        auth: true,
        adminOnly: true,
        params: [
          { name: 'page', in: 'query', required: false, description: 'Numero de pagina (default: 1)' },
          { name: 'limit', in: 'query', required: false, description: 'Resultados por pagina (default: 50, max: 100)' },
          { name: 'action', in: 'query', required: false, description: 'Filtrar por accion: user_login, user_created, instance_created, backup_created, incident_created, etc.' },
          { name: 'username', in: 'query', required: false, description: 'Filtrar por nombre de usuario' },
          { name: 'resource_type', in: 'query', required: false, description: 'Filtrar por tipo de recurso: user, instance, session, backup, incident, maintenance' }
        ],
        response: {
          logs: [
            {
              id: 1,
              user_id: 1,
              username: 'admin',
              action: 'user_created',
              resource_type: 'user',
              resource_id: '5',
              details: { username: 'nuevo_usuario' },
              ip_address: '192.168.1.100',
              created_at: '2025-01-15T10:00:00Z'
            }
          ],
          total: 250,
          page: 1,
          limit: 50,
          pages: 5
        }
      }
    ]
  },
  {
    tag: 'Admin - Backups',
    description: 'Gestion de backups de la base de datos. Se ejecutan automaticamente cada 6 horas. Solo accesible para admin.',
    adminOnly: true,
    endpoints: [
      {
        method: 'GET',
        path: '/admin/backup',
        summary: 'Listar backups existentes',
        description: 'Retorna la lista de los ultimos 20 archivos de backup con su tamano y fecha.',
        auth: true,
        adminOnly: true,
        response: {
          backups: [
            {
              filename: 'taguato_backup_20250115_100000.sql.gz',
              size: '2.5M',
              date: 'Jan 15 10:00'
            }
          ]
        }
      },
      {
        method: 'POST',
        path: '/admin/backup',
        summary: 'Crear backup manual',
        description: 'Ejecuta un backup inmediato de la base de datos. El archivo se comprime con gzip y se almacena en /backups/.',
        auth: true,
        adminOnly: true,
        response: {
          message: 'Backup created',
          filename: 'taguato_backup_20250115_120000.sql.gz',
          size: '2.5M'
        }
      }
    ]
  }
];
