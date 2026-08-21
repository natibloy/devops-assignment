{%- set phase5 = salt['pillar.get']('phase5') %}

include:
  - slurm.controller

{{ phase5.script_dir }}:
  file.directory:
    - user: root
    - group: root
    - mode: '0755'
    - makedirs: True

metrics-job-script:
  file.managed:
    - name: {{ phase5.job_script }}
    - source: salt://phase5/files/metrics_job.sbatch.j2
    - template: jinja
    - user: root
    - group: root
    - mode: '0755'
    - require:
      - file: {{ phase5.script_dir }}

metrics-submit-script:
  file.managed:
    - name: {{ phase5.submit_script }}
    - source: salt://phase5/files/submit_metrics_job.sh.j2
    - template: jinja
    - user: root
    - group: root
    - mode: '0755'
    - require:
      - file: {{ phase5.script_dir }}

# cron runs as an unprivileged user, so the log has to be created for it here.
metrics-submit-log:
  file.managed:
    - name: {{ phase5.log_file }}
    - user: {{ phase5.user }}
    - group: {{ phase5.user }}
    - mode: '0644'
    - replace: False

# cron.present is keyed by the command, so repeated highstates converge on one
# crontab line instead of appending a new one each time.
metrics-job-cron:
  cron.present:
    - name: {{ phase5.submit_script }}
    - user: {{ phase5.user }}
    - minute: '{{ phase5.cron_minute }}'
    - identifier: submit-slurm-metrics-job
    - require:
      - file: metrics-submit-script
      - file: metrics-job-script
      - file: metrics-submit-log
      - service: slurmctld-service
