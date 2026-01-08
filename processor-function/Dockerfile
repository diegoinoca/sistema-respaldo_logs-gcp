FROM python:3.11-slim

# Variables de entorno
ENV PYTHONUNBUFFERED=1
ENV BUCKET_NAME=""
ENV PROJECT_ID=""
ENV PORT=8080

# Directorio de trabajo
WORKDIR /app

# Copiar archivos
COPY requirements.txt .
COPY main.py .

# Instalar dependencias
RUN pip install --no-cache-dir -r requirements.txt

# Exponer puerto
EXPOSE 8080

# Comando de inicio
CMD exec functions-framework \
    --target=process_log \
    --signature-type=cloudevent \
    --port=${PORT}