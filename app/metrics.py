"""Prometheus metrics shared by the request middleware and /metrics endpoint."""

from prometheus_client import Counter, Histogram

REQUEST_COUNT = Counter(
    "app_requests_total",
    "Total HTTP requests processed.",
    ["method", "path", "status"],
)

ERROR_COUNT = Counter(
    "app_errors_total",
    "Total HTTP responses with a 5xx status.",
    ["method", "path"],
)

REQUEST_LATENCY = Histogram(
    "app_request_duration_seconds",
    "HTTP request latency in seconds.",
    ["method", "path"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0),
)
