#!/bin/bash

set -e

# Obtener URL del receiver
RECEIVER_URL=$(terraform output -raw receiver_url 2>/dev/null)
BUCKET_NAME=$(terraform output -raw bucket_name 2>/dev/null)

if [ -z "$RECEIVER_URL" ]; then
    echo "ERROR: No se pudo obtener la URL del receiver"
    exit 1
fi

echo "Probando sistema de logs..."
echo "URL: $RECEIVER_URL"
echo ""
# Test 1: Log INFO
echo "Test 1: Enviando log INFO..."
curl -X POST "$RECEIVER_URL" \
  -H "Content-Type: application/json" \
  -d '{
    "level": "INFO",
    "message": "Test log INFO desde script de prueba",
    "source": "test-script",
    "metadata": {
      "environment": "test",
      "version": "1.0"
    }
  }'
echo ""
echo ""

# Test 2: Log ERROR
echo "Test 2: Enviando log ERROR..."
curl -X POST "$RECEIVER_URL" \
  -H "Content-Type: application/json" \
  -d '{
    "level": "ERROR",
    "message": "Test error message",
    "source": "test-script",
    "error": {
      "code": "TEST_ERROR",
      "details": "This is a test error"
    }
  }'
echo ""
echo ""

# Test 3: Log WARNING
echo "Test 3: Enviando log WARNING..."
curl -X POST "$RECEIVER_URL" \
  -H "Content-Type: application/json" \
  -d '{
    "level": "WARNING",
    "message": "Test warning message",
    "source": "test-script"
  }'
echo ""
echo ""

# Esperar procesamiento
echo "Esperando procesamiento (20 segundos)..."
sleep 20

# Verificar logs en Storage
echo "Verificando logs en Storage..."
TODAY=$(date +%Y/%m/%d)
gsutil ls -r "gs://$BUCKET_NAME/logs/$TODAY/" 2>/dev/null || echo "ADVERTENCIA: No se encontraron logs aún"

echo ""
echo "Tests completados"
echo ""
echo "Ver todos los logs: gsutil ls -r gs://$BUCKET_NAME/logs/"
echo "Ver logs recientes: gsutil ls -lr gs://$BUCKET_NAME/logs/ | tail -10"