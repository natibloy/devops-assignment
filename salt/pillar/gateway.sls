gateway:
  release: metrics-gateway
  namespace: gateway
  chart_path: /vagrant/charts/metrics-gateway
  image:
    name: localhost/metrics-gateway
    tag: 0.3.0
  build_context: /vagrant/gateway
  port: 8080
  node_port: 30080
  # How long the gateway keeps publishing a series it has stopped receiving.
  # Every Slurm job reports under a new SLURM_JOB_ID, so without a sweep the
  # /metrics response grows for the pod's whole lifetime. 0 disables it.
  series_ttl_seconds: 3600
  # Metric suffixes the Phase 5 reporter pushes, as slurm_job_<suffix>_usage_percent.
  # The Grafana dashboard in charts/metrics-gateway/dashboards/ is a static Grafana
  # export and spells the full names out, so adding one here also needs a panel there.
  metrics:
    - cpu
    - gpu
    - memory
