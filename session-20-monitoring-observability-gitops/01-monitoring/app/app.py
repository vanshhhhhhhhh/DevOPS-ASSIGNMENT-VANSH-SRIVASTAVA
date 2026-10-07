"""s20-app: a tiny Flask service instrumented with prometheus_client.

Signals it produces:
  metrics -> /metrics (request counter, latency histogram, error counter, in-flight gauge, build info)
  logs    -> one JSON line per request on stdout (picked up by `docker compose logs`)
  trace   -> every request gets a W3C trace id (taken from an incoming `traceparent`
             header or generated). It is written into the log line, returned in the
             response headers and attached to the latency histogram as an exemplar,
             so a metric data point can be linked to the exact log line.
"""
import json
import logging
import os
import random
import sys
import time
import uuid

from flask import Flask, g, jsonify, request
from prometheus_client import Counter, Gauge, Histogram, make_wsgi_app
from werkzeug.middleware.dispatcher import DispatcherMiddleware

SERVICE = "s20-app"
VERSION = os.getenv("APP_VERSION", "1.0.0")
# probability that /api/orders fails with a simulated 500
ORDER_ERROR_RATE = float(os.getenv("ORDER_ERROR_RATE", "0.02"))
STARTED_AT = time.time()

# ---------------------------------------------------------------- metrics
REQUESTS = Counter(
    "app_requests_total", "Total HTTP requests handled", ["method", "endpoint", "status"]
)
ERRORS = Counter("app_errors_total", "Total HTTP 5xx responses", ["endpoint"])
LATENCY = Histogram(
    "app_request_duration_seconds",
    "HTTP request latency in seconds",
    ["endpoint"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0),
)
IN_PROGRESS = Gauge("app_requests_in_progress", "Requests currently being handled")
BUILD_INFO = Gauge("app_build_info", "Build information", ["version", "service"])
BUILD_INFO.labels(version=VERSION, service=SERVICE).set(1)


# ---------------------------------------------------------------- logging
class JsonFormatter(logging.Formatter):
    def format(self, record):
        entry = {
            "ts": time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(record.created))
            + f".{int(record.msecs):03d}Z",
            "level": record.levelname,
            "service": SERVICE,
            "version": VERSION,
            "msg": record.getMessage(),
        }
        entry.update(getattr(record, "fields", {}))
        return json.dumps(entry)


log = logging.getLogger(SERVICE)
_handler = logging.StreamHandler(sys.stdout)
_handler.setFormatter(JsonFormatter())
log.addHandler(_handler)
log.setLevel(logging.INFO)
log.propagate = False

app = Flask(__name__)


def _trace_context():
    """Return (trace_id, parent_span_id) from a W3C traceparent header, or a new trace id."""
    header = request.headers.get("traceparent", "")
    parts = header.split("-")
    if len(parts) == 4 and len(parts[1]) == 32 and len(parts[2]) == 16:
        return parts[1], parts[2]
    return uuid.uuid4().hex, None


@app.before_request
def _start():
    g.start = time.perf_counter()
    g.trace_id, g.parent_span_id = _trace_context()
    g.span_id = uuid.uuid4().hex[:16]
    IN_PROGRESS.inc()


@app.after_request
def _finish(response):
    duration = time.perf_counter() - g.start
    endpoint = request.url_rule.rule if request.url_rule else "unmatched"
    status = response.status_code
    REQUESTS.labels(request.method, endpoint, str(status)).inc()
    LATENCY.labels(endpoint).observe(duration, exemplar={"trace_id": g.trace_id})
    if status >= 500:
        ERRORS.labels(endpoint).inc()

    fields = {
        "trace_id": g.trace_id,
        "span_id": g.span_id,
        "method": request.method,
        "path": request.path,
        "status": status,
        "duration_ms": round(duration * 1000, 2),
        "client": request.headers.get("User-Agent", "-")[:40],
    }
    if g.parent_span_id:
        fields["parent_span_id"] = g.parent_span_id
    if getattr(g, "error", None):
        fields["error"] = g.error
    level = logging.ERROR if status >= 500 else logging.INFO
    log.log(level, "request completed", extra={"fields": fields})

    response.headers["X-Trace-Id"] = g.trace_id
    response.headers["traceparent"] = f"00-{g.trace_id}-{g.span_id}-01"
    return response


@app.teardown_request
def _teardown(_exc):
    IN_PROGRESS.dec()


# ---------------------------------------------------------------- routes
@app.route("/")
def index():
    return jsonify(service=SERVICE, version=VERSION,
                   endpoints=["/health", "/metrics", "/api/orders", "/api/slow",
                              "/api/error", "/api/cpu?ms=100"])


@app.route("/health")
def health():
    return jsonify(status="ok", service=SERVICE, version=VERSION,
                   uptime_seconds=round(time.time() - STARTED_AT, 1))


@app.route("/api/orders")
def orders():
    """Normal endpoint: 10-80 ms of simulated work, fails ORDER_ERROR_RATE of the time."""
    time.sleep(random.uniform(0.01, 0.08))
    if random.random() < ORDER_ERROR_RATE:
        g.error = "simulated database timeout"
        return jsonify(error=g.error), 500
    return jsonify(orders=random.randint(1, 50))


@app.route("/api/slow")
def slow():
    """Latency spike endpoint: 0.5-1.5 s."""
    time.sleep(random.uniform(0.5, 1.5))
    return jsonify(result="slow but ok")


@app.route("/api/error")
def error():
    """Always fails, used to push the error rate up."""
    g.error = "simulated upstream failure"
    return jsonify(error=g.error), 500


@app.route("/api/cpu")
def cpu():
    """Burns CPU for ?ms= milliseconds (default 100, max 1000)."""
    ms = min(int(request.args.get("ms", 100)), 1000)
    end = time.perf_counter() + ms / 1000
    n = 0
    while time.perf_counter() < end:
        n += sum(i * i for i in range(500))
    return jsonify(burned_ms=ms)


# /metrics is served by prometheus_client's WSGI app (it negotiates the
# OpenMetrics format, which is what carries the exemplars).
app.wsgi_app = DispatcherMiddleware(app.wsgi_app, {"/metrics": make_wsgi_app()})

log.info("s20-app starting", extra={"fields": {"order_error_rate": ORDER_ERROR_RATE}})
