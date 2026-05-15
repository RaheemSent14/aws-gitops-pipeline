import os
import time
import uuid
from flask import Flask, jsonify, request, Response
from prometheus_client import Counter, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST

app = Flask(__name__)

# ==========================================
# PROMETHEUS TELEMETRY DEFINITIONS
# ==========================================

# Counter: Tracks "The Past". 
# Production Context: We label by 'http_status' so we can calculate our 
# Error Rate percentage (e.g., (5xx errors / total requests) * 100).
REQUEST_COUNT = Counter(
    'http_requests_total',
    'Total HTTP requests processed by the application',
    ['method', 'endpoint', 'http_status']
)

# Histogram: Tracks "The User Experience".
# Production Context: Unlike a simple average, a histogram allows us to calculate 
# P95 latency in Grafana. This reveals if 5% of our users are experiencing 
# massive delays, even if the "average" response time looks healthy.
REQUEST_LATENCY = Histogram(
    'http_request_duration_seconds',
    'HTTP request latency processing duration in seconds',
    ['endpoint']
)

# Gauge: Tracks "The Metadata".
# Production Context: This provides a visual "timeline marker" in Grafana. 
# When we deploy a new version via ArgoCD, this value changes, allowing us 
# to immediately see if a performance dip correlates with a specific code release.
APP_INFO = Gauge(
    'app_info',
    'Application metadata properties tracking the current version',
    ['version']
)

# APP_VERSION is injected dynamically via AWS Secrets Manager & External Secrets Operator.
APP_VERSION = os.environ.get('APP_VERSION', '2.0.0')
APP_INFO.labels(version=APP_VERSION).set(1)

# ==========================================
# MIDDLEWARE AND LIFECYCLE HOOKS
# ==========================================

@app.before_request
def before_request():
    """
    Executes before routing logic. We initialize tracing and timing here.
    Production Context: Attaching a unique ID to every request allows us 
    to track a single user transaction across different microservices (Distributed Tracing).
    """
    request.start_time = time.time()
    request.id = str(uuid.uuid4())

@app.after_request
def after_request(response):
    """
    Executes before the response is sent. This is our telemetry 'collection point'.
    """
    # DATA PURITY: We explicitly ignore the /metrics endpoint. 
    # In a production setting, Prometheus scrapes this app every 15 seconds. 
    # If we don't filter this, 90% of our 'traffic' data would be the scraper 
    # itself, making our real user analytics useless.
    if request.path == '/metrics':
        return response

    request_latency = time.time() - request.start_time
    
    # Record metrics into in-memory registers
    REQUEST_COUNT.labels(
        method=request.method,
        endpoint=request.path,
        http_status=response.status_code
    ).inc()
    
    REQUEST_LATENCY.labels(endpoint=request.path).observe(request_latency)
    
    # TRACING: Return the Request ID in the headers. 
    # If a user reports an error, they can provide this ID, and we can 
    # find the exact logs for their specific failed request.
    response.headers['X-Request-Id'] = request.id
    return response

# ==========================================
# APPLICATION API ENDPOINTS
# ==========================================

@app.route('/')
def root():
    return jsonify({
        "status": "ok",
        "version": APP_VERSION,
        "environment": os.environ.get('ENVIRONMENT', 'production')
    })

@app.route('/health')
def health():
    """
    Health check for Kubernetes Liveness/Readiness probes.
    Production Context: If this returns anything other than 200, K8s will 
    automatically stop sending traffic to this pod or restart it (Self-Healing).
    """
    return jsonify({"healthy": True, "checks": {"app": "ok"}}), 200

@app.route('/metrics')
def metrics():
    """
    The scrape point for Prometheus.
    """
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)

if __name__ == '__main__':
    # Binding to 0.0.0.0 is mandatory for Docker/Kubernetes to allow 
    # external traffic to reach the application inside the container.
    app.run(host='0.0.0.0', port=5000)