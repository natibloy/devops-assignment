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
#
# clean removes the box's own 127.0.1.x mapping for the node's own hostname, so a
# name resolves to exactly one address - the private network one every other node
# can actually reach.
{%- for name, node in network.nodes.items() %}
hosts-entry-{{ name }}:
  host.present:
    - ip: {{ node.ip }}
    - clean: True
    - names:
      - {{ name }}
      - {{ name }}.{{ network.domain }}
{%- endfor %}
