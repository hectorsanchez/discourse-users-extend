# Discourse Moodle User Plugin Makefile

# Variables
DISCOURSE_VERSION = 3.5.0.beta8-dev
COMMIT_HASH = $(shell git rev-parse HEAD)

# Comandos principales
.PHONY: update-compatibility rebuild push help

# Actualizar compatibilidad y hacer commit/push
update-compatibility:
	@echo "Actualizando .discourse-compatibility con commit $(COMMIT_HASH)..."
	@echo "$(DISCOURSE_VERSION): $(COMMIT_HASH)" > .discourse-compatibility
	@git add .
	@git commit -m "update compatibility $(COMMIT_HASH)"
	@git push
	@echo "✅ Compatibilidad actualizada y pusheada"

# Hacer commit y push de cambios con mensaje personalizado
push:
	@if [ -z "$(TEXTO)" ]; then \
		echo "❌ Error: Debes proporcionar un mensaje de commit"; \
		echo "Uso: make push TEXTO=\"tu mensaje de commit\""; \
		exit 1; \
	fi
	@echo "📋 Estado actual del repositorio:"
	@git status --short
	@echo ""
	@echo "📦 Agregando cambios..."
	@git add .
	@echo "💾 Haciendo commit: $(TEXTO)"
	@git commit -m "$(TEXTO)"
	@echo "🚀 Subiendo cambios..."
	@git push
	@echo "✅ Cambios pusheados exitosamente"

# Comando completo: actualizar compatibilidad + rebuild
rebuild: update-compatibility
	@echo "🔄 Iniciando rebuild de Discourse..."
	@echo "Ahora puedes ejecutar el rebuild de Docker"

# Mostrar ayuda
help:
	@echo "Comandos disponibles:"
	@echo "  make update-compatibility  - Actualiza .discourse-compatibility y hace push"
	@echo "  make push TEXTO=\"mensaje\"  - Hace commit y push con mensaje personalizado"
	@echo "  make rebuild              - Ejecuta update-compatibility + mensaje para rebuild"
	@echo "  make help                 - Muestra esta ayuda"
	@echo ""
	@echo "Ejemplos:"
	@echo "  make push TEXTO=\"fix parsing error\""
	@echo "  make push TEXTO=\"add new feature\""
	@echo ""
	@echo "Variables:"
	@echo "  DISCOURSE_VERSION: $(DISCOURSE_VERSION)"
	@echo "  COMMIT_HASH: $(COMMIT_HASH)"

# Target por defecto
.DEFAULT_GOAL := help
