"""Small Flask service used to demonstrate a Kubernetes + GitOps workflow.

Endpoints:
  /         JSON greeting; can return simulated 500s (ERROR_RATE) for incident drills
  /healthz  liveness probe
  /readyz   readiness probe
  /metrics  Prometheus metrics
"""
import os
import random
import time

from flask import Flask, Response, g, jsonify, request
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest

# Metrics are module-level: prometheus_client keeps one global registry per process.
REQUESTS = Counter(
    "http_requests_total",
    "Total HTTP requests handled by the service",
    ["method", "endpoint", "status"],
)
LATENCY = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency in seconds",
    ["endpoint"],
)

# Probe and scrape traffic would drown out real traffic in the metrics, so skip it.
UNTRACKED = {"/metrics", "/healthz", "/readyz"}


def _error_rate_from_env() -> float:
    try:
        rate = float(os.getenv("ERROR_RATE", "0"))
    except ValueError:
        rate = 0.0
    return min(max(rate, 0.0), 1.0)


def create_app(config=None) -> Flask:
    app = Flask(__name__)
    app.config["APP_VERSION"] = os.getenv("APP_VERSION", "dev")
    app.config["ERROR_RATE"] = _error_rate_from_env()
    if config:
        app.config.update(config)

    @app.before_request
    def _start_timer():
        g.start = time.perf_counter()

    @app.after_request
    def _record_metrics(response):
        # Use the route template, not the raw path, to keep label cardinality bounded.
        endpoint = request.url_rule.rule if request.url_rule else "unmatched"
        if endpoint not in UNTRACKED:
            REQUESTS.labels(request.method, endpoint, str(response.status_code)).inc()
            LATENCY.labels(endpoint).observe(time.perf_counter() - g.start)
        return response

    @app.get("/")
    def index():
        if random.random() < app.config["ERROR_RATE"]:
            app.logger.warning("simulated failure returned (ERROR_RATE=%s)", app.config["ERROR_RATE"])
            return jsonify(error="simulated failure"), 500
        return jsonify(
            service="demo-service",
            version=app.config["APP_VERSION"],
            message="Hello from the GitOps microservice demo",
        )

    @app.get("/healthz")
    def healthz():
        return jsonify(status="ok")

    @app.get("/readyz")
    def readyz():
        return jsonify(status="ready")

    @app.get("/metrics")
    def metrics():
        return Response(generate_latest(), content_type=CONTENT_TYPE_LATEST)

    return app
