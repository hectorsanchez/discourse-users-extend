#!/bin/bash
# Wrapper script para ejecución automática del cache de usuarios
# Ejecuta a las 02:00 UTC (23:00 Buenos Aires)

SCRIPT_DIR="/var/discourse"
SCRIPT_NAME="load-users-cache-optimized.sh"
LOG_FILE="/var/log/discourse-users-cache.log"

# Función de logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S') UTC] $1" | tee -a "$LOG_FILE"
}

# Iniciar ejecución
log "=== INICIANDO CARGA AUTOMÁTICA DE CACHE ==="
log "Hora UTC: $(date)"
log "Hora Buenos Aires: $(TZ='America/Argentina/Buenos_Aires' date)"
log "Directorio: $SCRIPT_DIR"
log "Script: $SCRIPT_NAME"

# Verificar que el script existe
if [ ! -f "$SCRIPT_DIR/$SCRIPT_NAME" ]; then
    log "ERROR: Script no encontrado en $SCRIPT_DIR/$SCRIPT_NAME"
    exit 1
fi

# Verificar que es ejecutable
if [ ! -x "$SCRIPT_DIR/$SCRIPT_NAME" ]; then
    log "ERROR: Script no es ejecutable"
    exit 1
fi

# Cambiar al directorio del script
cd "$SCRIPT_DIR" || {
    log "ERROR: No se puede acceder al directorio $SCRIPT_DIR"
    exit 1
}

# Ejecutar el script
log "Ejecutando script de carga de cache..."
if ./"$SCRIPT_NAME" >> "$LOG_FILE" 2>&1; then
    log "Script ejecutado exitosamente"
    log "=== CARGA AUTOMÁTICA COMPLETADA ==="
else
    log "ERROR: Script falló con código de salida $?"
    log "=== CARGA AUTOMÁTICA FALLÓ ==="
    exit 1
fi
