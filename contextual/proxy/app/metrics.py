"""Prometheus-style metrics for the Contextual proxy.

Uses prometheus_client in single-process mode (sufficient for one container).
For multi-process deployments (e.g., gunicorn), use the multiprocess collector.
"""

import time
from contextlib import contextmanager

from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest

# ---------------------------------------------------------------------------
# Counters
# ---------------------------------------------------------------------------

REQUESTS_TOTAL = Counter(
    "proxy_requests_total",
    "Total HTTP requests",
    ["method", "endpoint", "status"],
)

CACHE_HITS_TOTAL = Counter(
    "proxy_cache_hits_total",
    "Cache hits by endpoint",
    ["endpoint"],
)

CACHE_MISSES_TOTAL = Counter(
    "proxy_cache_misses_total",
    "Cache misses by endpoint",
    ["endpoint"],
)

RATE_LIMIT_HITS_TOTAL = Counter(
    "proxy_rate_limit_hits_total",
    "Rate-limited requests",
    ["device_id"],
)

REDIS_ERRORS_TOTAL = Counter(
    "proxy_redis_errors_total",
    "Redis errors by operation",
    ["operation"],
)

MAPBOX_ERRORS_TOTAL = Counter(
    "proxy_mapbox_errors_total",
    "Mapbox upstream errors",
    ["endpoint", "status"],
)

# ---------------------------------------------------------------------------
# Histograms
# ---------------------------------------------------------------------------

MAPBOX_LATENCY_SECONDS = Histogram(
    "proxy_mapbox_latency_seconds",
    "Mapbox API call latency",
    ["endpoint"],
    buckets=[0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0],
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def observe_request(method: str, endpoint: str, status: int) -> None:
    REQUESTS_TOTAL.labels(method=method, endpoint=endpoint, status=str(status)).inc()


def observe_cache_hit(endpoint: str) -> None:
    CACHE_HITS_TOTAL.labels(endpoint=endpoint).inc()


def observe_cache_miss(endpoint: str) -> None:
    CACHE_MISSES_TOTAL.labels(endpoint=endpoint).inc()


def observe_rate_limit(device_id: str) -> None:
    RATE_LIMIT_HITS_TOTAL.labels(device_id=device_id).inc()


def observe_redis_error(operation: str) -> None:
    REDIS_ERRORS_TOTAL.labels(operation=operation).inc()


def observe_mapbox_error(endpoint: str, status: int) -> None:
    MAPBOX_ERRORS_TOTAL.labels(endpoint=endpoint, status=str(status)).inc()


@contextmanager
def mapbox_timer(endpoint: str):
    """Context manager to time Mapbox API calls."""
    start = time.perf_counter()
    try:
        yield
    finally:
        MAPBOX_LATENCY_SECONDS.labels(endpoint=endpoint).observe(time.perf_counter() - start)


def render_latest() -> tuple[bytes, str]:
    """Return (body, content_type) for the /metrics endpoint."""
    return generate_latest(), CONTENT_TYPE_LATEST
