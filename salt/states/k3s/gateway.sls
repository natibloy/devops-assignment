{%- import 'artifacts.jinja' as artifacts with context %}
{%- import 'k3s/macros.jinja' as k8s with context %}
{%- set gateway = salt['pillar.get']('gateway') %}
{%- set k3s = salt['pillar.get']('monitoring:k3s') %}
{%- set kps = salt['pillar.get']('monitoring:kube_prometheus_stack') %}
{%- set ref = gateway.image.name ~ ':' ~ gateway.image.tag %}
{%- set tar = artifacts.image_tar('metrics-gateway', gateway.image.tag) %}
{%- set stamp = k3s.values_dir ~ '/.gateway-deployed' %}
{#- Covers the whole chart directory, so editing a template or the dashboard on
    the host redeploys on the next highstate. Defined once because the deploy
    writes it and its guard re-evaluates it. -#}
{%- set hash_cmd = "find " ~ gateway.chart_path ~ " -type f -exec sha256sum {} + | sort -k2 | sha256sum | cut -d' ' -f1" %}

include:
  - k3s
  - k3s.helm
  - k3s.monitoring

# Imported straight into containerd from the builder's export, so the Deployment's
# IfNotPresent pull policy never has to reach a registry.
gateway-image-import:
  cmd.run:
    - name: k3s ctr images import {{ tar }}
    - unless: k3s ctr images ls -q | grep -qx '{{ ref }}'
    - timeout: 300
    - require:
      - cmd: k3s-api-ready

{{ k8s.namespace('gateway-namespace', gateway.namespace) }}

# The ServiceMonitor's release label has to match the kube-prometheus-stack
# release for Prometheus to select it, so Salt passes it in rather than letting
# the chart carry a second copy of a name this pillar already owns.
gateway-release:
  cmd.run:
    - name: >-
        helm upgrade --install {{ gateway.release }} {{ gateway.chart_path }}
        --namespace {{ gateway.namespace }}
        --set image.repository={{ gateway.image.name }}
        --set image.tag={{ gateway.image.tag }}
        --set service.port={{ gateway.port }}
        --set service.nodePort={{ gateway.node_port }}
        --set seriesTtlSeconds={{ gateway.series_ttl_seconds }}
        --set serviceMonitor.labels.release={{ kps.release }}
        --wait --timeout 5m
        && {{ hash_cmd }} > {{ stamp }}
    - env:
      - KUBECONFIG: {{ k3s.kubeconfig }}
    - timeout: 600
{{ k8s.release_converged(gateway.namespace, gateway.release, stamp, hash_cmd) }}
    - require:
      - cmd: gateway-image-import
      - cmd: gateway-namespace
      - cmd: helm-install
      - cmd: kps-release
