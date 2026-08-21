slurm:
  # Latest stable release at time of writing. Bumping this value is the only
  # change needed to rebuild against a newer Slurm.
  version: '26.05.3'
  deb_revision: '1'
  source_url: https://download.schedmd.com/slurm
  cluster_name: lab
  slurmctld_port: 6817
  slurmd_port: 6818
  slurmdbd_port: 6819
  build_dir: /root/build
  # Packages installed per role from the locally built apt repository.
  packages:
    common:
      - slurm-smd
      - slurm-smd-client
    controller:
      - slurm-smd-slurmctld
      - slurm-smd-slurmdbd
    compute:
      - slurm-smd-slurmd
  db:
    name: slurm_acct_db
    user: slurm
    host: localhost
  partition:
    name: main
    default: 'YES'
    max_time: INFINITE
    state: UP
  # Resources advertised to slurmctld for the compute node. Kept below the VM's
  # real memory so the kernel and K3s are not starved.
  compute_node:
    cpus: 6
    real_memory: 6144
