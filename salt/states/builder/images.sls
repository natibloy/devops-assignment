{%- set gateway = salt['pillar.get']('gateway') %}
{%- set node_exporter = salt['pillar.get']('monitoring:node_exporter') %}
{%- set images = '/srv/artifacts/images' %}
{%- set gateway_ref = gateway.image.name ~ ':' ~ gateway.image.tag %}
{%- set gateway_tar = images ~ '/metrics-gateway-' ~ gateway.image.tag ~ '.tar' %}
{%- set exporter_ref = node_exporter.image ~ ':' ~ node_exporter.tag %}
{%- set exporter_tar = images ~ '/node-exporter-' ~ node_exporter.tag ~ '.tar' %}

include:
  - podman

{{ images }}:
  file.directory:
    - makedirs: True

# The gateway image is built here and side-loaded on the compute node, so K3s
# never needs a registry to pull from.
gateway-image-build:
  cmd.run:
    - name: podman build -t {{ gateway_ref }} {{ gateway.build_context }}
    - creates: {{ gateway_tar }}
    - require:
      - sls: podman

gateway-image-export:
  cmd.run:
    - name: podman save -o {{ gateway_tar }} {{ gateway_ref }}
    - creates: {{ gateway_tar }}
    - require:
      - cmd: gateway-image-build
      - file: {{ images }}

# Exported alongside so the controller can start node_exporter from the shared
# folder rather than reaching out to quay.io during its own highstate.
node-exporter-image-pull:
  cmd.run:
    - name: podman pull {{ exporter_ref }}
    - creates: {{ exporter_tar }}
    - require:
      - sls: podman

node-exporter-image-export:
  cmd.run:
    - name: podman save -o {{ exporter_tar }} {{ exporter_ref }}
    - creates: {{ exporter_tar }}
    - require:
      - cmd: node-exporter-image-pull
      - file: {{ images }}
