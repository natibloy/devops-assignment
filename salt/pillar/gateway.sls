gateway:
  release: metrics-gateway
  namespace: gateway
  chart_path: /vagrant/charts/metrics-gateway
  image:
    name: localhost/metrics-gateway
    tag: 0.1.0
  build_context: /vagrant/gateway
  port: 8080
  node_port: 30080
  # Metric names the Phase 5 reporter pushes; also drives the Grafana panels.
  metrics:
    - cpu
    - gpu
    - memory
