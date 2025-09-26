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

## Script de Carga Optimizada de Cache

### `load-users-cache-optimized.sh`

Script para cargar el cache de usuarios con una estrategia optimizada que evita rate limiting y mejora la eficiencia.

#### Características

- **Procesamiento por lotes**: 60 usuarios por lote con pausa de 30 segundos entre lotes
- **Manejo de rate limiting**: Reintentos automáticos con backoff exponencial
- **Configuración flexible**: Permite procesar todos los lotes o un número específico
- **Mapeo de países**: Normalización automática de ubicaciones a países
- **Persistencia**: Guarda el cache en disco para recuperación rápida

#### Uso

```bash
# Procesar todos los lotes disponibles
./load-users-cache-optimized.sh

# Procesar solo 3 lotes (útil para pruebas)
./load-users-cache-optimized.sh 3
```

#### Parámetros

- **Sin parámetros**: Procesa todos los lotes disponibles
- **Número entero**: Procesa solo el número especificado de lotes

#### Estrategia de Optimización

1. **Lotes de 60 usuarios** con pausa de 30 segundos entre lotes
2. **Delay de 500ms** entre peticiones individuales
3. **Reintentos automáticos** para errores 429 (rate limit)
4. **Mapeo inteligente** de ubicaciones a países
5. **Eliminación de duplicados** por username

#### Tiempo Estimado

- **Todos los lotes**: ~11 minutos (para ~660 usuarios)
- **3 lotes**: ~3 minutos (para ~180 usuarios)

#### Configuración Requerida

El script utiliza la configuración del plugin:
- `dmu_discourse_api_key`: API Key de administración
- `dmu_discourse_api_username`: Usuario para la API
- `dmu_discourse_api_url`: URL del servidor Discourse

#### Salida

El script genera:
- Cache en memoria (`$users_by_country_cache`)
- Archivo de cache en disco (`tmp/discourse_users_cache.json`)
- Estadísticas detalladas del procesamiento
- Lista de países encontrados y conteo de usuarios

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