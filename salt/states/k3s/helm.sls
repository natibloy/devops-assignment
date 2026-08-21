{%- set helm = salt['pillar.get']('monitoring:helm') %}
{%- set k3s = salt['pillar.get']('monitoring:k3s') %}

include:
  - k3s

helm-install:
  cmd.run:
    - name: >-
        curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 |
        DESIRED_VERSION='{{ helm.version }}' bash
    - unless: helm version --short 2>/dev/null | grep -q '{{ helm.version }}'
    - timeout: 300

# `helm repo add` fetches the index itself, so no separate update is needed. The
# guard matches the URL, not just the name, so changing repo_url re-adds it.
helm-repo:
  cmd.run:
    - name: helm repo add {{ helm.repo_name }} {{ helm.repo_url }} --force-update
    - unless: helm repo list -o json 2>/dev/null | grep -qF '"{{ helm.repo_url }}"'
    - env:
      - KUBECONFIG: {{ k3s.kubeconfig }}
    - timeout: 300
    - require:
      - cmd: helm-install
