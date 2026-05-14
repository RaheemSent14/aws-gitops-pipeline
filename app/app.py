import os
import time
import uuid
from flask import Flask, jsonify, request, Response
from prometheus_client import Counter, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST

app = Flask(__name__)

# ==========================================
# PROMETHEUS TELEMETRY DEFINITIONS
# ==========================================

# Counter metric: Tracks cumulative request volume dimensions.
# Intent: Measures incoming traffic trends and error rates over time.
# Label Choice: 'http_status' separates 200s from 400/500 errors to calculate error rates.
REQUEST_COUNT = Counter(
    'http_requests_total',
    'Total HTTP requests processed by the application',
    ['method', 'endpoint', 'http_status']
)

# Histogram metric: Tracks performance response duration distributions.
# Intent: Measures system latency. Prometheus automatically creates bucket ranges 
# allowing us to calculate P95 or P99 response trends in Grafana.
REQUEST_LATENCY = Histogram(
    'http_request_duration_seconds',
    'HTTP request latency processing duration in seconds',
    ['endpoint']
)

# Gauge metric: Tracks a point-in-time value that can rise or fall.
# Intent: Used here to pass static metadata (the application version) into our time-series data.
# How it works: It outputs a constant value of 1, but the 'version' label tells Grafana exactly what code is running.
APP_INFO = Gauge(
    'app_info',
    'Application metadata properties tracking the current version',
    ['version']
)

# Pull version from environment variables (fallback to 2.0.0) and initialize the gauge on boot
APP_VERSION = os.environ.get('APP_VERSION', '2.0.0')
APP_INFO.labels(version=APP_VERSION).set(1)

# ==========================================
# MIDDLEWARE AND LIFECYCLE HOOKS
# ==========================================

@app.before_request
def before_request():
    """
    Executes right before a request hits the routing logic.
    We attach a start timestamp and a unique tracing ID directly to the request object.
    This lets us accurately measure performance latency later in the lifecycle.
    """
    request.start_time = time.time()
    request.id = str(uuid.uuid4())

@app.after_request
def after_request(response):
    """
    Executes right before the response is sent back to the client.
    Handles metrics tracking and injects telemetry headers globally.
    """
    # EDGE CASE PASSTHROUGH: If the request is Prometheus scraping our /metrics page, 
    # we exit early. Otherwise, Prometheus would count its own scrapes as regular traffic, 
    # polluting our real user analytics.
    if request.path == '/metrics':
        return response

    # Calculate exact duration execution speed
    request_latency = time.time() - request.start_time
    
    # Record metrics into memory registers with precise dimensions
    REQUEST_COUNT.labels(
        method=request.method,
        endpoint=request.path,
        http_status=response.status_code
    ).inc()
    
    REQUEST_LATENCY.labels(endpoint=request.path).observe(request_latency)
    
    # DISTRIBUTED TRACING BOUNDARY: Inject the request ID into the outbound headers.
    # This lets us map front-end browser logs to specific backend transactions when debugging.
    response.headers['X-Request-Id'] = request.id
    return response

# ==========================================
# APPLICATION API ENDPOINTS
# ==========================================

@app.route('/')
def root():
    """
    Primary API application entrypoint returning basic environmental metadata.
    """
    return jsonify({
        "status": "ok",
        "version": APP_VERSION,
        "environment": os.environ.get('ENVIRONMENT', 'development')
    })

@app.route('/health')
def health():
    """
    Health check endpoint monitored by Kubernetes liveness and readiness probes.
    Returns an explicit HTTP 200 status code to confirm the engine is responsive.
    """
    return jsonify({"healthy": True, "checks": {"app": "ok"}}), 200

@app.route('/metrics')
def metrics():
    """
    The metric extraction page scraped by the Prometheus controller.
    Exposes all internal time-series registries as a raw formatted plaintext stream.
    """
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)

if __name__ == '__main__':
    # PORT BINDING NOTE: Binding to 0.0.0.0 is mandatory for containerized workloads.
    # It instructs the application to accept traffic from all available network interfaces 
    # inside the container, allowing Kubernetes service routers to forward inbound traffic.
    app.run(host='0.0.0.0', port=5000)