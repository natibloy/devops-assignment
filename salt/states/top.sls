# Role targeting comes from the `role` grain set in each minion config, so a node
# never needs to know its own name to get the right states.
base:
  'role:builder':
    - match: grain
    - common
    - podman
    - builder

  'role:controller':
    - match: grain
    - common
    - podman
    - munge
    - mariadb
    - node_exporter
    - slurm.repo
    - slurm.common
    - slurm.controller
    - phase5

  'role:compute':
    - match: grain
    - common
    - munge
    - slurm.repo
    - slurm.common
    - slurm.compute
    - k3s
    - k3s.helm
    - k3s.monitoring
    - k3s.gateway
