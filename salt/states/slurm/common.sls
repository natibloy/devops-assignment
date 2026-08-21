{%- set slurm = salt['pillar.get']('slurm') %}

include:
  - munge
  - slurm.repo

slurm-group:
  group.present:
    - name: {{ slurm.user.name }}
    - gid: {{ slurm.user.gid }}
    - system: True

slurm-user:
  user.present:
    - name: {{ slurm.user.name }}
    - uid: {{ slurm.user.uid }}
    - gid: {{ slurm.user.gid }}
    - home: {{ slurm.user.home }}
    - shell: {{ slurm.user.shell }}
    - system: True
    - createhome: True
    - require:
      - group: slurm-group

# Installed on both roles: the libraries plus the client tools (sinfo, squeue,
# sbatch, sacct) that Phase 5 relies on.
slurm-common-packages:
  pkg.installed:
    - pkgs: {{ slurm.packages.common | json }}
    - require:
      - cmd: slurm-local-repo-refresh
      - user: slurm-user

slurm-log-dir:
  file.directory:
    - name: /var/log/slurm
    - user: {{ slurm.user.name }}
    - group: {{ slurm.user.name }}
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
