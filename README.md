# Discourse Users Extend Plugin

Plugin para Discourse que permite visualizar usuarios de Discourse, agrupándolos por país con funcionalidades de filtrado y búsqueda.

## Características

- **Visualización de usuarios** de Discourse via API
- **Agrupación por país** con contadores en tiempo real
- **Filtros avanzados** por país y búsqueda de texto
- **Interfaz responsive** similar al diseño de Discourse
- **API REST** para integración con otros sistemas
- **Configuración desde admin** sin modificar código
- **Información detallada** de usuarios (username, trust level, avatar)

## Requisitos

- Discourse 3.0+
- API Key de administración de Discourse
- Acceso a la API de usuarios de Discourse

## Instalación

### 1. Instalar el plugin

```bash
cd /var/discourse
git clone https://github.com/hectorsanchez/discourse-users-extend.git plugins/discourse-users-extend
```

### 2. Rebuild de la aplicación

```bash
cd /var/discourse
sudo ./launcher rebuild app
```

### 3. Configurar desde el admin

1. Ir a **Admin → Plugins → Discourse API Settings**
2. Configurar:
   - **dmu_enabled**: `true` (habilitar plugin)
   - **dmu_discourse_api_url**: URL del servidor Discourse (ej: https://discourse.youth-care.eu)
   - **dmu_discourse_api_key**: API Key de administración
   - **dmu_discourse_api_username**: Usuario para la API (recomendado: system)

### 4. Agregar enlace al sidebar (opcional)

1. Ir a **Admin → Customize → Navigation Menu**
2. Agregar nuevo enlace:
   - **Name**: `Users Extend`
   - **URL**: `/discourse-users-page`
   - **Icon**: `users`
   - **Position**: Después de "Categories"

## Configuración de la API

### Obtener API Key

1. Ir a **Admin → API**
2. Crear nueva API Key
3. Asignar permisos necesarios para leer usuarios
4. Copiar la API Key generada

### Configuración de prueba

- **URL de desarrollo**: `https://discourse.youth-care.eu`
- **URL de producción**: `https://assembly.youth-care.eu`

## Uso

Una vez configurado, el plugin proporciona:

- **Vista de usuarios** agrupados por país
- **Filtros por país** con dropdown
- **Búsqueda de texto** en nombre, email y username
- **Información detallada** de cada usuario
- **Actualización en tiempo real** de estadísticas

## Estructura del Plugin

```
discourse-users-extend/
├── plugin.rb                                    # Controlador principal
├── config/
│   └── settings.yml                            # Configuración del plugin
├── assets/
│   └── javascripts/
│       └── discourse/
│           ├── components/
│           │   ├── discourse-api-settings.js   # Componente de configuración
│           │   └── discourse-users-page.js     # Componente principal
│           ├── controllers/
│           │   └── admin/
│           │       └── plugins-index.js        # Controlador de admin
│           ├── helpers/
│           │   └── get-initials.js             # Helper para iniciales
│           ├── initializers/
│           │   └── discourse-users-sidebar.js  # Inicializador del sidebar
│           └── templates/
│               ├── admin/
│               │   └── plugins/
│               │       └── discourse_api_settings.hbs
│               ├── components/
│               │   └── discourse-users-page.hbs
│               └── discourse-users-page.hbs
└── README.md
```

## API Endpoints

- `GET /discourse/users` - Obtener usuarios agrupados por país
- `POST /discourse/save_settings` - Guardar configuración (solo admin)

## Desarrollo

### Estructura de la respuesta de la API

```json
{
  "success": true,
  "users_by_country": {
    "España": [
      {
        "firstname": "Juan",
        "lastname": "Pérez",
        "email": "juan@example.com",
        "username": "juanperez",
        "trust_level": 2,
        "avatar_template": "https://..."
      }
    ]
  },
  "total_users": 150,
  "timestamp": "2025-01-27T10:30:00Z"
}
```

## Licencia

Este proyecto está bajo la Licencia MIT. Ver el archivo LICENSE para más detalles.

## Contribuciones

Las contribuciones son bienvenidas. Por favor:

1. Fork el proyecto
2. Crea una rama para tu feature (`git checkout -b feature/AmazingFeature`)
3. Commit tus cambios (`git commit -m 'Add some AmazingFeature'`)
4. Push a la rama (`git push origin feature/AmazingFeature`)
5. Abre un Pull Request

## Autor

**Héctor Sánchez** - [@hectorsanchez](https://github.com/hectorsanchez)

#