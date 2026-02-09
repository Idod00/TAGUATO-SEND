// API Documentation Data for TAGUATO-SEND
const DOCS_DATA = [
  {
    tag: 'Autenticacion',
    description: 'Endpoints para login, perfil y cambio de contrasena del panel.',
    endpoints: [
      {
        method: 'POST',
        path: '/api/auth/login',
        summary: 'Iniciar sesion',
        description: 'Autentica un usuario con username y password. Retorna un token API para usar en solicitudes posteriores.',
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
        description: 'Retorna la informacion del usuario autenticado junto con sus instancias asignadas.',
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
        }
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
    description: 'Envio de mensajes a traves de instancias WhatsApp conectadas.',
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
        }
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
    tag: 'Webhooks',
    description: 'Configuracion de webhooks para recibir notificaciones de eventos en tiempo real.',
    endpoints: [
      {
        method: 'POST',
        path: '/webhook/set/{instanceName}',
        summary: 'Configurar webhook',
        description: 'Configura una URL de webhook para recibir notificaciones de eventos (mensajes recibidos, cambios de estado, etc.) de la instancia.',
        auth: true,
        params: [
          { name: 'instanceName', in: 'path', required: true, description: 'Nombre de la instancia' }
        ],
        body: {
          url: 'https://mi-servidor.com/webhook',
          webhook_by_events: false,
          webhook_base64: true,
          events: [
            'MESSAGES_UPSERT',
            'CONNECTION_UPDATE',
            'QRCODE_UPDATED'
          ]
        },
        response: {
          webhook: {
            url: 'https://mi-servidor.com/webhook',
            events: ['MESSAGES_UPSERT', 'CONNECTION_UPDATE', 'QRCODE_UPDATED']
          }
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
        description: 'Crea un nuevo usuario en el sistema. Se genera automaticamente un token API unico.',
        auth: true,
        adminOnly: true,
        body: {
          username: 'nuevo_usuario',
          password: 'contrasena123',
          role: 'user',
          max_instances: 3
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
        description: 'Actualiza los campos de un usuario. Solo se envian los campos que se desean cambiar. Usar regenerate_token para generar un nuevo API token.',
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
        description: 'Elimina permanentemente un usuario y todas sus asociaciones de instancias del sistema.',
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
  }
];
