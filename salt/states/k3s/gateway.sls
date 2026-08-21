{%- set gateway = salt['pillar.get']('gateway') %}
{%- set k3s = salt['pillar.get']('monitoring:k3s') %}
{%- set ref = gateway.image.name ~ ':' ~ gateway.image.tag %}
{%- set tar = '/srv/artifacts/images/metrics-gateway-' ~ gateway.image.tag ~ '.tar' %}
{%- set stamp = k3s.values_dir ~ '/.gateway-deployed' %}

include:
  - k3s
  - k3s.helm
  - k3s.monitoring

# Imported straight into containerd from the builder's export, so the Deployment's
# IfNotPresent pull policy never has to reach a registry.
gateway-image-import:
  cmd.run:
    - name: k3s ctr images import {{ tar }}
    - unless: k3s ctr images ls -q | grep -qx 'docker.io/{{ ref }}' || k3s ctr images ls -q | grep -qx '{{ ref }}'
    - timeout: 300
    - require:
      - cmd: k3s-api-ready

gateway-namespace:
  cmd.run:
    - name: kubectl create namespace {{ gateway.namespace }} --dry-run=client -o yaml | kubectl apply -f -
    - env:
      - KUBECONFIG: {{ k3s.kubeconfig }}
    - unless: kubectl --kubeconfig {{ k3s.kubeconfig }} get namespace {{ gateway.namespace }}
    - require:
      - cmd: k3s-api-ready
      - file: kubectl-symlink

# Same stamp pattern as the Prometheus stack: the hash covers the whole chart
# directory, so editing a template or the dashboard on the host triggers a
# redeploy on the next highstate and nothing else does.
gateway-release:
  cmd.run:
    - name: >-
        helm upgrade --install {{ gateway.release }} {{ gateway.chart_path }}
        --namespace {{ gateway.namespace }}
        --set image.repository={{ gateway.image.name }}
        --set image.tag={{ gateway.image.tag }}
        --set service.port={{ gateway.port }}
        --set service.nodePort={{ gateway.node_port }}
        --wait --timeout 5m
        && find {{ gateway.chart_path }} -type f -exec sha256sum {} + | sort -k2 | sha256sum | cut -d' ' -f1 > {{ stamp }}
    - env:
      - KUBECONFIG: {{ k3s.kubeconfig }}
    - timeout: 600
    - unless: >-
        test "$(cat {{ stamp }} 2>/dev/null)"
        = "$(find {{ gateway.chart_path }} -type f -exec sha256sum {} + | sort -k2 | sha256sum | cut -d' ' -f1)"
        && helm -n {{ gateway.namespace }} status {{ gateway.release }} >/dev/null 2>&1
    - require:
      - cmd: gateway-image-import
      - cmd: gateway-namespace
      - cmd: helm-install
      - cmd: kps-release
