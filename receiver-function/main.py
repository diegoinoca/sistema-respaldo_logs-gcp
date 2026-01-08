import os
import json
from datetime import datetime
from google.cloud import pubsub_v1
import functions_framework
from flask import jsonify

# Configuración
PUBSUB_TOPIC = os.environ.get('PUBSUB_TOPIC')
PROJECT_ID = os.environ.get('PROJECT_ID')

# Cliente de Pub/Sub
publisher = pubsub_v1.PublisherClient()

@functions_framework.http
def receive_log(request):
    """
    Función HTTP que recibe logs vía API y los publica en Pub/Sub
    
    Expected JSON format:
    {
        "level": "INFO",
        "message": "Log message",
        "timestamp": "2026-01-07T12:00:00Z",
        "source": "app-name",
        "metadata": {...}
    }
    """
    try:
        # Obtener datos del request
        request_json = request.get_json(silent=True)
        
        if not request_json:
            return jsonify({
                'error': 'No JSON data provided'
            }), 400
        
        # Agregar timestamp si no viene
        if 'timestamp' not in request_json:
            request_json['timestamp'] = datetime.utcnow().isoformat() + 'Z'
        
        # Agregar metadata del request
        request_json['request_metadata'] = {
            'method': request.method,
            'user_agent': request.headers.get('User-Agent', 'unknown'),
            'remote_addr': request.remote_addr,
            'received_at': datetime.utcnow().isoformat() + 'Z'
        }
        
        # Convertir a JSON y publicar en Pub/Sub
        message_data = json.dumps(request_json).encode('utf-8')
        
        future = publisher.publish(PUBSUB_TOPIC, message_data)
        message_id = future.result()
        
        print(f"✅ Log publicado en Pub/Sub - Message ID: {message_id}")
        
        return jsonify({
            'status': 'success',
            'message': 'Log received and queued for processing',
            'message_id': message_id,
            'timestamp': request_json['timestamp']
        }), 200
        
    except Exception as e:
        print(f"❌ Error: {e}")
        return jsonify({
            'status': 'error',
            'error': str(e)
        }), 500