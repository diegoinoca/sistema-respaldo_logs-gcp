import base64
import json
import os
from datetime import datetime
from google.cloud import storage
from cloudevents.http import CloudEvent
import functions_framework

# Configuración
BUCKET_NAME = os.environ.get('BUCKET_NAME')
PROJECT_ID = os.environ.get('PROJECT_ID')

# Cliente de Storage
storage_client = storage.Client()

def save_to_storage(log_data):
    """
    Guarda el log en Cloud Storage organizado por fecha
    """
    try:
        bucket = storage_client.bucket(BUCKET_NAME)
        
        # Obtener timestamp
        timestamp_str = log_data.get('timestamp', datetime.utcnow().isoformat())
        try:
            dt = datetime.fromisoformat(timestamp_str.replace('Z', '+00:00'))
        except:
            dt = datetime.utcnow()
        
        # Path: logs/YYYY/MM/DD/HH/log_timestamp.json
        blob_path = (
            f"logs/"
            f"{dt.year}/"
            f"{dt.month:02d}/"
            f"{dt.day:02d}/"
            f"{dt.hour:02d}/"
            f"log_{dt.strftime('%Y%m%d_%H%M%S_%f')}.json"
        )
        
        # Metadata
        blob = bucket.blob(blob_path)
        blob.metadata = {
            'level': log_data.get('level', 'INFO'),
            'source': log_data.get('source', 'unknown'),
            'processed_at': datetime.utcnow().isoformat()
        }
        
        # Upload
        blob.upload_from_string(
            json.dumps(log_data, indent=2),
            content_type='application/json'
        )
        
        print(f"✅ Log guardado: gs://{BUCKET_NAME}/{blob_path}")
        return True
        
    except Exception as e:
        print(f"❌ Error guardando en Storage: {e}")
        raise

@functions_framework.cloud_event
def process_log(cloud_event: CloudEvent):
    """
    Función activada por Pub/Sub que procesa y guarda logs
    """
    try:
        # Decodificar mensaje
        pubsub_message = base64.b64decode(
            cloud_event.data["message"]["data"]
        ).decode('utf-8')
        
        # Parsear JSON
        log_data = json.loads(pubsub_message)
        
        # Validar datos mínimos
        if not log_data:
            print("⚠️ Mensaje vacío")
            return
        
        # Agregar metadata de procesamiento
        log_data['processing'] = {
            'processed_at': datetime.utcnow().isoformat(),
            'processor': 'cloud-function',
            'project_id': PROJECT_ID
        }
        
        # Guardar en Storage
        save_to_storage(log_data)
        
        print(f"✅ Log procesado exitosamente - Source: {log_data.get('source', 'unknown')}")
        
    except Exception as e:
        print(f"❌ Error procesando log: {e}")
        raise  # Re-lanzar para que Pub/Sub reintente