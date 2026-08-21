{%- set slurm = salt['pillar.get']('slurm') %}

include:
  - munge
  - slurm.repo

# Installed on both roles: the libraries plus the client tools (sinfo, squeue,
# sbatch, sacct) that Phase 5 relies on.
slurm-common-packages:
  pkg.installed:
    - pkgs: {{ slurm.packages.common | json }}
    - require:
      - pkgrepo: slurm-local-repo

slurm-log-dir:
  file.directory:
    - name: /var/log/slurm
    - user: slurm
    - group: slurm
    - mode: '0755'
    - makedirs: True
    - require:
      - pkg: slurm-common-packages

slurm-conf:
  file.managed:
    - name: /etc/slurm/slurm.conf
    - source: salt://slurm/files/slurm.conf.j2
    - template: jinja
    - user: root
    - group: root
    - mode: '0644'
    - makedirs: True
    - require:
      - pkg: slurm-common-packages

slurm-cgroup-conf:
  file.managed:
    - name: /etc/slurm/cgroup.conf
    - source: salt://slurm/files/cgroup.conf
    - user: root
    - group: root
    - mode: '0644'
    - require:
      - pkg: slurm-common-packages
