{%- import 'k3s/macros.jinja' as k8s with context %}
{%- set monitoring = salt['pillar.get']('monitoring') %}
{%- set k3s = monitoring.k3s %}
{%- set kps = monitoring.kube_prometheus_stack %}
{%- set grafana = monitoring.grafana %}
{%- set values_file = k3s.values_dir ~ '/kps-values.yaml' %}
{%- set stamp = k3s.values_dir ~ '/.kps-deployed' %}
{#- Written by the deploy and re-evaluated by its guard, so it is defined once. -#}
{%- set hash_cmd = "sha256sum " ~ values_file ~ " | cut -d' ' -f1" %}
{%- set crt = k3s.tls_dir ~ '/grafana.crt' %}
{%- set key = k3s.tls_dir ~ '/grafana.key' %}

include:
  - k3s
  - k3s.helm

{{ k3s.tls_dir }}:
  file.directory:
    - makedirs: True
    - mode: '0700'

{{ k3s.values_dir }}:
  file.directory:
    - makedirs: True
    - mode: '0700'

# Self-signed because there is no CA in this lab; browsers will warn once and the
# README says so.
grafana-tls-cert:
  cmd.run:
    - name: >-
        openssl req -x509 -newkey rsa:2048 -nodes -days 825
        -subj '/CN={{ grafana.host }}'
        -addext 'subjectAltName=DNS:{{ grafana.host }}'
        -keyout {{ key }} -out {{ crt }}
    - creates:
      - {{ crt }}
      - {{ key }}
    - require:
      - file: {{ k3s.tls_dir }}

{{ k8s.namespace('monitoring-namespace', kps.namespace) }}

# create --dry-run | apply is the idempotent way to converge a TLS secret; plain
# `kubectl create secret` fails once it already exists.
grafana-tls-secret:
  cmd.run:
    - name: >-
        kubectl create secret tls {{ grafana.tls_secret }}
        -n {{ kps.namespace }} --cert {{ crt }} --key {{ key }}
        --dry-run=client -o yaml | kubectl apply -f -
    - env:
      - KUBECONFIG: {{ k3s.kubeconfig }}
    - unless: kubectl --kubeconfig {{ k3s.kubeconfig }} -n {{ kps.namespace }} get secret {{ grafana.tls_secret }}
    - require:
      - cmd: grafana-tls-cert
      - cmd: monitoring-namespace

kps-values:
  file.managed:
    - name: {{ values_file }}
    - source: salt://k3s/files/kps-values.yaml.j2
    - template: jinja
    - mode: '0600'
    - require:
      - file: {{ k3s.values_dir }}

# `upgrade --install` converges rather than failing on an existing release, and
# the stamp guard makes a no-op highstate skip Helm entirely while a changed
# values file or a previously failed release still forces a deploy.
kps-release:
  cmd.run:
    - name: >-
        helm upgrade --install {{ kps.release }} {{ kps.chart }}
        --version {{ kps.chart_version }}
        --namespace {{ kps.namespace }}
        --values {{ values_file }}
        --wait --timeout 20m
        && {{ hash_cmd }} > {{ stamp }}
    - env:
      - KUBECONFIG: {{ k3s.kubeconfig }}
    - timeout: 1500
{{ k8s.release_converged(kps.namespace, kps.release, stamp, hash_cmd) }}
    - require:
      - cmd: helm-repo
      - cmd: grafana-tls-secret
      - file: kps-values
