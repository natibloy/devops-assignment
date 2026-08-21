{%- set version = salt['pillar.get']('slurm:version') %}
{%- set debs = '/srv/artifacts/debs' %}

# The builder published its output as a flat apt repository. Pointing apt at it
# lets the Slurm packages be installed with pkg.installed, with apt resolving the
# dependencies between them and against Debian's own archive.
slurm-artifacts-present:
  file.exists:
    - name: {{ debs }}/.built-{{ version }}

slurm-local-repo:
  pkgrepo.managed:
    - name: deb [trusted=yes] file:{{ debs }} ./
    - file: /etc/apt/sources.list.d/slurm-local.list
    - clean_file: True
    - refresh: True
    - require:
      - file: slurm-artifacts-present
