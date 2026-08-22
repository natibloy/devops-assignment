"""Prometheus metrics gateway.

Accepts arbitrary metric samples over HTTP and republishes them in the Prometheus
text format, bridging Slurm jobs (which are short-lived and cannot be scraped)
to a Prometheus server (which only pulls).
"""

import os
import threading
import time

from flask import Flask, jsonify, request
from prometheus_client import CONTENT_TYPE_LATEST, CollectorRegistry, Gauge, generate_latest

app = Flask(__name__)

REGISTRY = CollectorRegistry()

# Every Slurm job reports under its own SLURM_JOB_ID, so each job leaves three
# label sets behind that will never be written again. Prometheus has already
# stored their samples, so re-publishing them forever only grows each scrape;
# series untouched for this long are dropped. 0 disables the sweep.
SERIES_TTL_SECONDS = int(os.environ.get("SERIES_TTL_SECONDS", "3600"))

# name -> (gauge, label_names). The label names are kept alongside the gauge
# because prometheus_client fixes them at creation time and exposes them only as
# a private attribute.
_gauges = {}
# (name, label_values) -> monotonic timestamp of the last sample.
_last_seen = {}
_lock = threading.Lock()


def _get_gauge(name, label_names):
    with _lock:
        entry = _gauges.get(name)
        if entry is None:
            gauge = Gauge(
                name,
                "Value reported through the metrics gateway",
                labelnames=label_names,
                registry=REGISTRY,
            )
            _gauges[name] = (gauge, label_names)
            return gauge

        gauge, registered = entry
        if registered != label_names:
            raise ValueError(
                "metric %r was registered with labels %s, got %s"
                % (name, list(registered), list(label_names))
            )
        return gauge


def _touch(name, label_values):
    with _lock:
        _last_seen[(name, label_values)] = time.monotonic()


def _drop_stale_series():
    """Remove label sets no longer being reported, so /metrics stays bounded."""
    if not SERIES_TTL_SECONDS:
        return
    cutoff = time.monotonic() - SERIES_TTL_SECONDS
    with _lock:
        stale = [key for key, seen in _last_seen.items() if seen < cutoff]
        for key in stale:
            name, label_values = key
            del _last_seen[key]
            entry = _gauges.get(name)
            if entry and label_values:
                entry[0].remove(*label_values)


@app.route("/update-metric", methods=["PUT"])
def update_metric():
    payload = request.get_json(silent=True)
    if not isinstance(payload, dict):
        return jsonify(error="body must be a JSON object"), 400

    name = payload.get("name")
    if not isinstance(name, str) or not name:
        return jsonify(error="'name' is required and must be a non-empty string"), 400

    try:
        value = float(payload["value"])
    except (KeyError, TypeError, ValueError):
        return jsonify(error="'value' is required and must be a number"), 400

    labels = payload.get("labels") or {}
    if not isinstance(labels, dict):
        return jsonify(error="'labels' must be a JSON object"), 400
    labels = {str(k): str(v) for k, v in labels.items()}

    label_names = tuple(sorted(labels))
    try:
        gauge = _get_gauge(name, label_names)
    except ValueError as exc:
        return jsonify(error=str(exc)), 409

    label_values = tuple(labels[key] for key in label_names)
    if label_names:
        gauge.labels(*label_values).set(value)
    else:
        gauge.set(value)
    _touch(name, label_values)

    return jsonify(status="ok", name=name, value=value, labels=labels), 200


@app.route("/metrics", methods=["GET"])
def metrics():
    _drop_stale_series()
    return generate_latest(REGISTRY), 200, {"Content-Type": CONTENT_TYPE_LATEST}


@app.route("/healthz", methods=["GET"])
def healthz():
    return jsonify(status="ok"), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "8080")))
