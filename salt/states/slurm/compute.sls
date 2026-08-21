{%- set slurm = salt['pillar.get']('slurm') %}

include:
  - slurm.common

slurm-compute-packages:
  pkg.installed:
    - pkgs: {{ slurm.packages.compute | json }}
    - require:
      - pkg: slurm-common-packages

slurmd-spool-dir:
  file.directory:
    - name: /var/spool/slurmd
    - user: root
    - group: root
    - mode: '0755'
    - makedirs: True
    - require:
      - pkg: slurm-compute-packages

slurmd-service:
  service.running:
    - name: slurmd
    - enable: True
    - watch:
      - file: slurm-conf
    - require:
      - file: slurmd-spool-dir
      - file: slurm-log-dir
      - service: munge-service
