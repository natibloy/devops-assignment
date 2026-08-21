{%- import 'artifacts.jinja' as artifacts with context %}
{%- set exporter = salt['pillar.get']('monitoring:node_exporter') %}
{%- set ref = exporter.image ~ ':' ~ exporter.tag %}
{%- set tar = artifacts.image_tar('node-exporter', exporter.tag) %}

include:
  - podman

# Loaded from the builder's export so this node never needs registry access.
node-exporter-image:
  cmd.run:
    - name: podman load -i {{ tar }}
    - unless: podman image exists {{ ref }}
    - require:
      - sls: podman

# systemd owns the container's lifecycle. Because the unit always runs the same
# named container with --replace, re-running the highstate can never leave a
# second copy behind.
node-exporter-unit:
  file.managed:
    - name: /etc/systemd/system/node_exporter.service
    - source: salt://node_exporter/files/node_exporter.service.j2
    - template: jinja
    - mode: '0644'

node-exporter-service:
  service.running:
    - name: node_exporter
    - enable: True
    - watch:
      - file: node-exporter-unit
    - require:
      - cmd: node-exporter-image
