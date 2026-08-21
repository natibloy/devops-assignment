"""Prometheus metrics gateway.

Accepts arbitrary metric samples over HTTP and republishes them in the Prometheus
text format, bridging Slurm jobs (which are short-lived and cannot be scraped)
to a Prometheus server (which only pulls).
"""

import sys
import threading

from flask import Flask, jsonify, request
from prometheus_client import CONTENT_TYPE_LATEST, CollectorRegistry, Gauge, generate_latest

app = Flask(__name__)

REGISTRY = CollectorRegistry()

# A metric's label names are fixed by prometheus_client at Gauge creation time, so
# the first payload for a given name defines its label set and later payloads must
# match it.
_gauges = {}
_lock = threading.Lock()


def _get_gauge(name, label_names):
    with _lock:
        gauge = _gauges.get(name)
        if gauge is None:
            gauge = Gauge(
                name,
                "Value reported through the metrics gateway",
                labelnames=label_names,
                registry=REGISTRY,
            )
            _gauges[name] = gauge
            return gauge

    if tuple(gauge._labelnames) != label_names:
        raise ValueError(
            "metric %r was registered with labels %s, got %s"
            % (name, list(gauge._labelnames), list(label_names))
        )
    return gauge


@app.route("/update-metric", methods=["PUT"])
def update_metric():
    payload = request.get_json(silent=True)
    if not isinstance(payload, dict):
        return jsonify(error="body must be a JSON object"), 400

    name = payload.get("name") or payload.get("metric")
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

    if label_names:
        gauge.labels(**labels).set(value)
    else:
        gauge.set(value)

    return jsonify(status="ok", name=name, value=value, labels=labels), 200


@app.route("/metrics", methods=["GET"])
def metrics():
    return generate_latest(REGISTRY), 200, {"Content-Type": CONTENT_TYPE_LATEST}


@app.route("/healthz", methods=["GET"])
def healthz():
    return jsonify(status="ok"), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
