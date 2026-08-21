monitoring:
  node_exporter:
    image: quay.io/prometheus/node-exporter
    tag: v1.12.1
    port: 9100
    container_name: node_exporter
  k3s:
    version: v1.36.3+k3s1
    kubeconfig: /etc/rancher/k3s/k3s.yaml
    tls_dir: /etc/rancher/tls
    values_dir: /etc/rancher/values
  helm:
    version: v3.21.4
    repo_name: prometheus-community
    repo_url: https://prometheus-community.github.io/helm-charts
  kube_prometheus_stack:
    release: kps
    namespace: monitoring
    chart: prometheus-community/kube-prometheus-stack
    chart_version: 88.5.2
    retention: 24h
  grafana:
    host: grafana.local
    tls_secret: grafana-tls
    # "Node Exporter Full" dashboard from grafana.com.
    node_exporter_dashboard:
      gnet_id: 1860
      revision: 45
