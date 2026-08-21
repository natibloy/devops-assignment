{%- set slurm = salt['pillar.get']('slurm') %}

include:
  - mariadb
  - slurm.common

slurm-controller-packages:
  pkg.installed:
    - pkgs: {{ slurm.packages.controller | json }}
    - require:
      - pkg: slurm-common-packages

slurm-state-dir:
  file.directory:
    - name: /var/spool/slurmctld
    - user: slurm
    - group: slurm
    - mode: '0755'
    - makedirs: True
    - require:
      - pkg: slurm-controller-packages

slurmdbd-conf:
  file.managed:
    - name: /etc/slurm/slurmdbd.conf
    - source: salt://slurm/files/slurmdbd.conf.j2
    - template: jinja
    - user: slurm
    - group: slurm
    - mode: '0600'
    - require:
      - pkg: slurm-controller-packages

# slurmdbd has to be accepting connections before slurmctld starts, or slurmctld
# logs accounting errors and drops its connection to the database.
slurmdbd-service:
  service.running:
    - name: slurmdbd
    - enable: True
    - watch:
      - file: slurmdbd-conf
    - require:
      - mysql_grants: slurm-acct-grants
      - file: slurm-log-dir

slurmctld-service:
  service.running:
    - name: slurmctld
    - enable: True
    - watch:
      - file: slurm-conf
    - require:
      - service: slurmdbd-service
      - file: slurm-state-dir
      - service: munge-service

# Registers the cluster in the accounting database. Without this sacct reports
# nothing for the Phase 5 jobs.
slurm-register-cluster:
  cmd.run:
    - name: sacctmgr -i add cluster {{ slurm.cluster_name }}
    - unless: sacctmgr -n -P list cluster format=Cluster | grep -qx {{ slurm.cluster_name }}
    - retry:
        attempts: 10
        interval: 6
    - require:
      - service: slurmdbd-service
