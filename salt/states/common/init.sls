{%- set network = salt['pillar.get']('network') %}

common-packages:
  pkg.installed:
    - pkgs:
      - curl
      - ca-certificates
      - gnupg
      - jq
      - rsync

# Every node resolves every other node by short name and FQDN so Slurm, Munge and
# the Prometheus scrape targets can be expressed by name where it reads better.
{%- for name, node in network.nodes.items() %}
hosts-entry-{{ name }}:
  host.present:
    - ip: {{ node.ip }}
    - names:
      - {{ name }}
      - {{ name }}.{{ network.domain }}
{%- endfor %}
