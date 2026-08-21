{%- set k3s = salt['pillar.get']('monitoring:k3s') %}
{%- set network = salt['pillar.get']('network') %}
{%- set grafana = salt['pillar.get']('monitoring:grafana') %}
{%- set node_ip = network.nodes.compute.ip %}

# --node-ip and --flannel-iface are mandatory here: every VirtualBox guest shares
# the same NAT address on eth0, so without pinning them to the private network
# K3s would advertise 10.0.2.15 and its own kubelet would be unreachable.
k3s-install:
  cmd.run:
    - name: >-
        curl -sfL https://get.k3s.io |
        INSTALL_K3S_VERSION='{{ k3s.version }}'
        INSTALL_K3S_EXEC='server
        --node-ip {{ node_ip }}
        --advertise-address {{ node_ip }}
        --flannel-iface {{ network.interface }}
        --tls-san {{ grafana.host }}
        --tls-san {{ node_ip }}
        --write-kubeconfig-mode 0644'
        sh -s -
    - creates: /usr/local/bin/k3s
    - timeout: 900

k3s-service:
  service.running:
    - name: k3s
    - enable: True
    - require:
      - cmd: k3s-install

# Everything downstream shells out to kubectl/helm, so block until the API server
# answers rather than letting each state discover the wait for itself.
k3s-api-ready:
  cmd.run:
    - name: >-
        until k3s kubectl get --raw='/readyz' >/dev/null 2>&1; do sleep 5; done;
        k3s kubectl wait --for=condition=Ready node/compute --timeout=300s
    - timeout: 600
    - require:
      - service: k3s-service

# k3s ships kubectl as a subcommand only; the Helm chart hooks and our own states
# expect a real binary on PATH.
kubectl-symlink:
  file.symlink:
    - name: /usr/local/bin/kubectl
    - target: /usr/local/bin/k3s
    - require:
      - cmd: k3s-install

# Lets kubectl and helm work over SSH without exporting KUBECONFIG by hand.
kubeconfig-profile:
  file.managed:
    - name: /etc/profile.d/k3s.sh
    - mode: '0644'
    - contents: |
        export KUBECONFIG={{ k3s.kubeconfig }}
