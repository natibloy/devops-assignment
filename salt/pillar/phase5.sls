phase5:
  script_dir: /opt/slurm-jobs
  job_script: /opt/slurm-jobs/metrics_job.sbatch
  submit_script: /opt/slurm-jobs/submit_metrics_job.sh
  log_file: /var/log/slurm-metrics-submit.log
  # cron runs as an unprivileged user; sbatch needs no elevation.
  user: vagrant
  cron_minute: '*/5'
  # The job pushes a sample per metric every push_interval_seconds for
  # job_duration_seconds, so one job produces 12 samples per metric.
  job_duration_seconds: 60
  push_interval_seconds: 5
