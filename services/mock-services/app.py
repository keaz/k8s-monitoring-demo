import os
import time
import random
import logging
import requests
from flask import Flask, jsonify, request
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.instrumentation.requests import RequestsInstrumentor

# Configuration from environment
SERVICE_NAME = os.getenv('SERVICE_NAME', 'unknown-service')
SERVICE_PORT = int(os.getenv('SERVICE_PORT', 8080))
OTEL_ENDPOINT = os.getenv('OTEL_EXPORTER_OTLP_ENDPOINT',
                          'otel-collector.monitoring.svc.cluster.local:4317')

# Downstream services this service calls
DOWNSTREAM_SERVICES = os.getenv('DOWNSTREAM_SERVICES', '').split(',') if os.getenv('DOWNSTREAM_SERVICES') else []

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize OpenTelemetry
resource = Resource.create({"service.name": SERVICE_NAME})
trace.set_tracer_provider(TracerProvider(resource=resource))
tracer = trace.get_tracer(__name__)

otlp_exporter = OTLPSpanExporter(endpoint=OTEL_ENDPOINT, insecure=True)
span_processor = BatchSpanProcessor(otlp_exporter)
trace.get_tracer_provider().add_span_processor(span_processor)

# Initialize Flask
app = Flask(__name__)

# Instrument Flask and Requests
FlaskInstrumentor().instrument_app(app)
RequestsInstrumentor().instrument()

# Prometheus metrics
REQUEST_COUNT = Counter(
    'http_requests_total',
    'Total HTTP requests',
    ['method', 'endpoint', 'status']
)

REQUEST_DURATION = Histogram(
    'http_request_duration_seconds',
    'HTTP request duration in seconds',
    ['method', 'endpoint']
)

DOWNSTREAM_REQUEST_COUNT = Counter(
    'downstream_requests_total',
    'Total requests to downstream services',
    ['service', 'status']
)

BUSINESS_EVENTS = Counter(
    'business_events_total',
    'Business events processed',
    ['event_type', 'status']
)

# Sample data for different services
SERVICE_DATA = {
    'user-service': {
        'users': [
            {'id': 1, 'name': 'Alice Johnson', 'email': 'alice@example.com'},
            {'id': 2, 'name': 'Bob Smith', 'email': 'bob@example.com'},
            {'id': 3, 'name': 'Carol White', 'email': 'carol@example.com'},
        ]
    },
    'product-service': {
        'products': [
            {'id': 101, 'name': 'Laptop', 'price': 999.99, 'stock': 50},
            {'id': 102, 'name': 'Mouse', 'price': 29.99, 'stock': 200},
            {'id': 103, 'name': 'Keyboard', 'price': 79.99, 'stock': 150},
        ]
    },
    'order-service': {
        'orders': [
            {'id': 1001, 'userId': 1, 'productId': 101, 'status': 'completed'},
            {'id': 1002, 'userId': 2, 'productId': 102, 'status': 'pending'},
        ]
    },
    'inventory-service': {
        'inventory': [
            {'productId': 101, 'warehouse': 'US-EAST', 'quantity': 30},
            {'productId': 102, 'warehouse': 'US-WEST', 'quantity': 100},
        ]
    },
    'payment-service': {
        'payments': [
            {'id': 5001, 'orderId': 1001, 'amount': 999.99, 'status': 'completed'},
        ]
    }
}

def get_service_data():
    """Get data specific to this service"""
    return SERVICE_DATA.get(SERVICE_NAME, {'data': []})

def call_downstream_service(service_name, endpoint='/api/health'):
    """Call a downstream service"""
    url = f'http://{service_name}.services.svc.cluster.local{endpoint}'

    try:
        start_time = time.time()
        response = requests.get(url, timeout=2)
        duration = time.time() - start_time

        DOWNSTREAM_REQUEST_COUNT.labels(service=service_name, status=response.status_code).inc()

        logger.info(f'Called {service_name}: {response.status_code} in {duration:.3f}s')
        return response.json() if response.status_code == 200 else None
    except Exception as e:
        DOWNSTREAM_REQUEST_COUNT.labels(service=service_name, status='error').inc()
        logger.error(f'Error calling {service_name}: {str(e)}')
        return None

@app.route('/health')
def health():
    """Health check endpoint"""
    return jsonify({'status': 'healthy', 'service': SERVICE_NAME}), 200

@app.route('/api/data')
def get_data():
    """Get service-specific data"""
    start_time = time.time()

    # Simulate some processing time
    time.sleep(random.uniform(0.01, 0.1))

    data = get_service_data()

    # Randomly call downstream services to create trace chains
    downstream_data = {}
    if DOWNSTREAM_SERVICES and random.random() > 0.3:  # 70% chance to call downstream
        service_to_call = random.choice(DOWNSTREAM_SERVICES)
        result = call_downstream_service(service_to_call, '/api/data')
        if result:
            downstream_data[service_to_call] = result

    response = {
        'service': SERVICE_NAME,
        'data': data,
        'downstream': downstream_data,
        'timestamp': time.time()
    }

    duration = time.time() - start_time
    REQUEST_DURATION.labels(method='GET', endpoint='/api/data').observe(duration)
    REQUEST_COUNT.labels(method='GET', endpoint='/api/data', status=200).inc()
    BUSINESS_EVENTS.labels(event_type='data_fetch', status='success').inc()

    return jsonify(response), 200

@app.route('/api/action', methods=['POST'])
def perform_action():
    """Perform an action that calls multiple downstream services"""
    start_time = time.time()

    with tracer.start_as_current_span("perform_action") as span:
        span.set_attribute("service.name", SERVICE_NAME)

        # Simulate processing
        processing_time = random.uniform(0.05, 0.2)
        time.sleep(processing_time)
        span.set_attribute("processing.duration", processing_time)

        results = {}

        # Call all downstream services
        for service in DOWNSTREAM_SERVICES:
            with tracer.start_as_current_span(f"call_{service}") as child_span:
                child_span.set_attribute("downstream.service", service)
                result = call_downstream_service(service, '/api/data')
                results[service] = 'success' if result else 'failed'
                child_span.set_attribute("call.result", results[service])

        # Simulate occasional errors
        if random.random() < 0.1:  # 10% error rate
            REQUEST_COUNT.labels(method='POST', endpoint='/api/action', status=500).inc()
            BUSINESS_EVENTS.labels(event_type='action', status='error').inc()
            span.set_attribute("error", True)
            return jsonify({'error': 'Random failure for demo'}), 500

        duration = time.time() - start_time
        REQUEST_DURATION.labels(method='POST', endpoint='/api/action').observe(duration)
        REQUEST_COUNT.labels(method='POST', endpoint='/api/action', status=200).inc()
        BUSINESS_EVENTS.labels(event_type='action', status='success').inc()

        response = {
            'service': SERVICE_NAME,
            'action': 'completed',
            'downstream_results': results,
            'duration': duration
        }

        return jsonify(response), 200

@app.route('/api/slow')
def slow_endpoint():
    """Endpoint with variable latency for demo"""
    start_time = time.time()

    # Simulate slow operation
    delay = random.uniform(0.5, 2.0)
    time.sleep(delay)

    duration = time.time() - start_time
    REQUEST_DURATION.labels(method='GET', endpoint='/api/slow').observe(duration)
    REQUEST_COUNT.labels(method='GET', endpoint='/api/slow', status=200).inc()

    return jsonify({
        'service': SERVICE_NAME,
        'message': 'Slow operation completed',
        'delay': delay
    }), 200

@app.route('/api/error')
def error_endpoint():
    """Endpoint that returns errors for demo"""
    REQUEST_COUNT.labels(method='GET', endpoint='/api/error', status=500).inc()
    BUSINESS_EVENTS.labels(event_type='error_test', status='error').inc()

    return jsonify({
        'error': 'Intentional error for demo',
        'service': SERVICE_NAME
    }), 500

@app.route('/metrics')
def metrics():
    """Prometheus metrics endpoint"""
    return generate_latest(), 200, {'Content-Type': CONTENT_TYPE_LATEST}

# Java service proxy endpoints
@app.route('/api/hello')
def java_hello():
    """Proxy to Java Service A - hello endpoint"""
    start_time = time.time()
    url = 'http://service-a.services.svc.cluster.local/api/hello'

    try:
        response = requests.get(url, timeout=5)
        duration = time.time() - start_time
        REQUEST_DURATION.labels(method='GET', endpoint='/api/hello').observe(duration)
        REQUEST_COUNT.labels(method='GET', endpoint='/api/hello', status=response.status_code).inc()

        return response.json(), response.status_code
    except Exception as e:
        logger.error(f'Error calling service-a /api/hello: {str(e)}')
        REQUEST_COUNT.labels(method='GET', endpoint='/api/hello', status=500).inc()
        return jsonify({'error': str(e)}), 500

@app.route('/api/users/<user_id>')
def java_get_user(user_id):
    """Proxy to Java Service A - get user endpoint"""
    start_time = time.time()
    url = f'http://service-a.services.svc.cluster.local/api/users/{user_id}'

    try:
        response = requests.get(url, timeout=5)
        duration = time.time() - start_time
        REQUEST_DURATION.labels(method='GET', endpoint='/api/users').observe(duration)
        REQUEST_COUNT.labels(method='GET', endpoint='/api/users', status=response.status_code).inc()

        return response.json(), response.status_code
    except Exception as e:
        logger.error(f'Error calling service-a /api/users/{user_id}: {str(e)}')
        REQUEST_COUNT.labels(method='GET', endpoint='/api/users', status=500).inc()
        return jsonify({'error': str(e)}), 500

@app.route('/api/orders/<order_id>')
def java_get_order(order_id):
    """Proxy to Java Service A - get order endpoint"""
    start_time = time.time()
    url = f'http://service-a.services.svc.cluster.local/api/orders/{order_id}'

    try:
        response = requests.get(url, timeout=5)
        duration = time.time() - start_time
        REQUEST_DURATION.labels(method='GET', endpoint='/api/orders').observe(duration)
        REQUEST_COUNT.labels(method='GET', endpoint='/api/orders', status=response.status_code).inc()

        return response.json(), response.status_code
    except Exception as e:
        logger.error(f'Error calling service-a /api/orders/{order_id}: {str(e)}')
        REQUEST_COUNT.labels(method='GET', endpoint='/api/orders', status=500).inc()
        return jsonify({'error': str(e)}), 500

@app.route('/actuator/health')
def java_actuator_health():
    """Proxy to Java Service A - actuator health endpoint"""
    start_time = time.time()
    url = 'http://service-a.services.svc.cluster.local/actuator/health'

    try:
        response = requests.get(url, timeout=5)
        duration = time.time() - start_time
        REQUEST_DURATION.labels(method='GET', endpoint='/actuator/health').observe(duration)
        REQUEST_COUNT.labels(method='GET', endpoint='/actuator/health', status=response.status_code).inc()

        return response.json(), response.status_code
    except Exception as e:
        logger.error(f'Error calling service-a /actuator/health: {str(e)}')
        REQUEST_COUNT.labels(method='GET', endpoint='/actuator/health', status=500).inc()
        return jsonify({'error': str(e)}), 500

# CPU-intensive endpoints
@app.route('/api/compute/primes/<int:limit>')
def java_compute_primes(limit):
    """Proxy to Java Service A - compute primes endpoint"""
    start_time = time.time()
    url = f'http://service-a.services.svc.cluster.local/api/compute/primes/{limit}'

    try:
        response = requests.get(url, timeout=30)
        duration = time.time() - start_time
        REQUEST_DURATION.labels(method='GET', endpoint='/api/compute/primes').observe(duration)
        REQUEST_COUNT.labels(method='GET', endpoint='/api/compute/primes', status=response.status_code).inc()

        return response.json(), response.status_code
    except Exception as e:
        logger.error(f'Error calling service-a /api/compute/primes/{limit}: {str(e)}')
        REQUEST_COUNT.labels(method='GET', endpoint='/api/compute/primes', status=500).inc()
        return jsonify({'error': str(e)}), 500

@app.route('/api/compute/hash/<int:iterations>')
def java_compute_hash(iterations):
    """Proxy to Java Service A - compute hash endpoint"""
    start_time = time.time()
    url = f'http://service-a.services.svc.cluster.local/api/compute/hash/{iterations}'

    try:
        response = requests.get(url, timeout=30)
        duration = time.time() - start_time
        REQUEST_DURATION.labels(method='GET', endpoint='/api/compute/hash').observe(duration)
        REQUEST_COUNT.labels(method='GET', endpoint='/api/compute/hash', status=response.status_code).inc()

        return response.json(), response.status_code
    except Exception as e:
        logger.error(f'Error calling service-a /api/compute/hash/{iterations}: {str(e)}')
        REQUEST_COUNT.labels(method='GET', endpoint='/api/compute/hash', status=500).inc()
        return jsonify({'error': str(e)}), 500

# Memory-intensive endpoints
@app.route('/api/memory/allocate/<int:size_mb>')
def java_memory_allocate(size_mb):
    """Proxy to Java Service A - memory allocation endpoint"""
    start_time = time.time()
    url = f'http://service-a.services.svc.cluster.local/api/memory/allocate/{size_mb}'

    try:
        response = requests.get(url, timeout=30)
        duration = time.time() - start_time
        REQUEST_DURATION.labels(method='GET', endpoint='/api/memory/allocate').observe(duration)
        REQUEST_COUNT.labels(method='GET', endpoint='/api/memory/allocate', status=response.status_code).inc()

        return response.json(), response.status_code
    except Exception as e:
        logger.error(f'Error calling service-a /api/memory/allocate/{size_mb}: {str(e)}')
        REQUEST_COUNT.labels(method='GET', endpoint='/api/memory/allocate', status=500).inc()
        return jsonify({'error': str(e)}), 500

@app.route('/api/memory/process/<int:item_count>')
def java_memory_process(item_count):
    """Proxy to Java Service A - memory processing endpoint"""
    start_time = time.time()
    url = f'http://service-a.services.svc.cluster.local/api/memory/process/{item_count}'

    try:
        response = requests.get(url, timeout=30)
        duration = time.time() - start_time
        REQUEST_DURATION.labels(method='GET', endpoint='/api/memory/process').observe(duration)
        REQUEST_COUNT.labels(method='GET', endpoint='/api/memory/process', status=response.status_code).inc()

        return response.json(), response.status_code
    except Exception as e:
        logger.error(f'Error calling service-a /api/memory/process/{item_count}: {str(e)}')
        REQUEST_COUNT.labels(method='GET', endpoint='/api/memory/process', status=500).inc()
        return jsonify({'error': str(e)}), 500

# Slow/database simulation endpoints
@app.route('/api/slow/database/<int:delay_ms>')
def java_slow_database(delay_ms):
    """Proxy to Java Service A - slow database endpoint"""
    start_time = time.time()
    url = f'http://service-a.services.svc.cluster.local/api/slow/database/{delay_ms}'

    try:
        response = requests.get(url, timeout=60)
        duration = time.time() - start_time
        REQUEST_DURATION.labels(method='GET', endpoint='/api/slow/database').observe(duration)
        REQUEST_COUNT.labels(method='GET', endpoint='/api/slow/database', status=response.status_code).inc()

        return response.json(), response.status_code
    except Exception as e:
        logger.error(f'Error calling service-a /api/slow/database/{delay_ms}: {str(e)}')
        REQUEST_COUNT.labels(method='GET', endpoint='/api/slow/database', status=500).inc()
        return jsonify({'error': str(e)}), 500

# Error simulation endpoint
@app.route('/api/simulate/error')
def java_simulate_error():
    """Proxy to Java Service A - error simulation endpoint"""
    start_time = time.time()
    url = 'http://service-a.services.svc.cluster.local/api/simulate/error'

    try:
        response = requests.get(url, timeout=10)
        duration = time.time() - start_time
        REQUEST_DURATION.labels(method='GET', endpoint='/api/simulate/error').observe(duration)
        REQUEST_COUNT.labels(method='GET', endpoint='/api/simulate/error', status=response.status_code).inc()

        return response.json(), response.status_code
    except Exception as e:
        logger.error(f'Error calling service-a /api/simulate/error: {str(e)}')
        REQUEST_COUNT.labels(method='GET', endpoint='/api/simulate/error', status=500).inc()
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    logger.info(f'Starting {SERVICE_NAME} on port {SERVICE_PORT}')
    logger.info(f'OTEL endpoint: {OTEL_ENDPOINT}')
    logger.info(f'Downstream services: {DOWNSTREAM_SERVICES}')

    app.run(host='0.0.0.0', port=SERVICE_PORT, debug=False)
