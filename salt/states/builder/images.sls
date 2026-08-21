{%- import 'artifacts.jinja' as artifacts with context %}
{%- set gateway = salt['pillar.get']('gateway') %}
{%- set node_exporter = salt['pillar.get']('monitoring:node_exporter') %}
{%- set gateway_ref = gateway.image.name ~ ':' ~ gateway.image.tag %}
{%- set gateway_tar = artifacts.image_tar('metrics-gateway', gateway.image.tag) %}
{%- set exporter_ref = node_exporter.image ~ ':' ~ node_exporter.tag %}
{%- set exporter_tar = artifacts.image_tar('node-exporter', node_exporter.tag) %}

include:
  - podman

{{ artifacts.images }}:
  file.directory:
    - makedirs: True

# The gateway image is built here and side-loaded on the compute node, so K3s
# never needs a registry to pull from.
#
# cgroupfs is used instead of podman's default systemd cgroup manager: build
# containers are short-lived and need no systemd scope, and asking systemd for one
# over D-Bus fails outright if anything restarted dbus earlier in the highstate -
# which the Slurm build-dependency installation is liable to do.
gateway-image-build:
  cmd.run:
    - name: podman build --cgroup-manager=cgroupfs -t {{ gateway_ref }} {{ gateway.build_context }}
    - unless: test -f {{ gateway_tar }}
    - timeout: 900
    - retry:
        attempts: 3
        interval: 15
    - require:
      - sls: podman

gateway-image-export:
  cmd.run:
    - name: podman save -o {{ gateway_tar }} {{ gateway_ref }}
    - creates: {{ gateway_tar }}
    - require:
      - cmd: gateway-image-build
      - file: {{ artifacts.images }}

# Exported alongside so the controller can start node_exporter from the shared
# folder rather than reaching out to quay.io during its own highstate.
node-exporter-image-pull:
  cmd.run:
    - name: podman pull {{ exporter_ref }}
    - unless: test -f {{ exporter_tar }}
    - timeout: 600
    - retry:
        attempts: 3
        interval: 15
    - require:
      - sls: podman

node-exporter-image-export:
  cmd.run:
    - name: podman save -o {{ exporter_tar }} {{ exporter_ref }}
    - creates: {{ exporter_tar }}
    - require:
      - cmd: node-exporter-image-pull
      - file: {{ artifacts.images }}
