gateway:
  release: metrics-gateway
  namespace: gateway
  chart_path: /vagrant/charts/metrics-gateway
  image:
    name: localhost/metrics-gateway
    tag: 0.2.0
  build_context: /vagrant/gateway
  port: 8080
  node_port: 30080
  # Metric suffixes the Phase 5 reporter pushes, as slurm_job_<suffix>_usage_percent.
  # The Grafana dashboard in charts/metrics-gateway/dashboards/ is a static Grafana
  # export and spells the full names out, so adding one here also needs a panel there.
  metrics:
    - cpu
    - gpu
    - memory
