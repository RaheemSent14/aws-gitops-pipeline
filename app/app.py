import os
import time
import uuid
from flask import Flask, jsonify, request, Response
from prometheus_client import Counter, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST

app = Flask(__name__)

# Prometheus Metrics Definitions
REQUEST_COUNT = Counter(
    'http_requests_total',
    'Total HTTP requests',
    ['method', 'endpoint', 'http_status']
)

REQUEST_LATENCY = Histogram(
    'http_request_duration_seconds',
    'HTTP request latency',
    ['endpoint']
)

APP_INFO = Gauge(
    'app_info',
    'Application version info',
    ['version']
)

APP_VERSION = os.environ.get('APP_VERSION', '1.0.0')
APP_INFO.labels(version=APP_VERSION).set(1)

@app.before_request
def before_request():
    request.start_time = time.time()
    request.id = str(uuid.uuid4())

@app.after_request
def after_request(response):
    # Prevent internal Prometheus scrapes from polluting traffic metrics
    if request.path == '/metrics':
        return response

    request_latency = time.time() - request.start_time
    
    REQUEST_COUNT.labels(
        method=request.method,
        endpoint=request.path,
        http_status=response.status_code
    ).inc()
    
    REQUEST_LATENCY.labels(endpoint=request.path).observe(request_latency)
    
    response.headers['X-Request-Id'] = request.id
    return response

@app.route('/')
def root():
    return jsonify({
        "status": "ok",
        "version": APP_VERSION,
        "environment": os.environ.get('ENVIRONMENT', 'development')
    })

@app.route('/health')
def health():
    return jsonify({"healthy": True, "checks": {"app": "ok"}}), 200

@app.route('/metrics')
def metrics():
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)

if __name__ == '__main__':
    # nosec B104: Binding to all interfaces is required for containerization
    app.run(host='0.0.0.0', port=5000)# test
# test
