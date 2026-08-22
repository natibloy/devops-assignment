# The HPC-DevOps Hybrid Orchestrator

A three-node Vagrant environment that bridges a Slurm HPC cluster with a
Kubernetes-native monitoring stack:

- **builder** — ephemeral; compiles Slurm from source into separate DEBs, builds the
  metrics-gateway container image, exports both, then powers itself off
- **controller** — Salt master, `slurmctld`, `slurmdbd`, MariaDB, and a node_exporter
  running under Podman
- **compute** — Salt minion, `slurmd`, and a single-node K3s cluster hosting
  kube-prometheus-stack, Grafana and the metrics gateway

## Requirements

- Vagrant 2.4.x and VirtualBox 7.x
- 16 GB RAM and 12 vCPU free at peak (12 GB / 8 vCPU once the builder powers off)
- ~20 GB free disk
- Internet access on the first run

No Vagrant plugins are required.

> **If VirtualBox was only just installed or upgraded, reboot the host first.** Its
> host-only network driver is unusable until the machine restarts, and until then
> every VM fails to start with `VERR_INTNET_FLT_IF_NOT_FOUND`.

## Running it

```bash
git clone <this-repo> && cd devops-assignment
vagrant up
```

That is the entire deployment — no further commands. Expect **about 25–40 minutes**
on a first run, most of it compiling Slurm on the builder.

The nodes come up in order, each provisioned by Salt:

1. **builder** compiles Slurm into `slurm-smd-*` packages, publishes them to
   `artifacts/` as an apt repository, builds and exports the container images, then
   **shuts itself down**.
2. **controller** installs the Salt master and brings up munge, MariaDB, the Slurm
   control plane and the Podman node_exporter.
3. **compute** registers as a Salt minion and brings up `slurmd`, K3s,
   kube-prometheus-stack, Grafana and the metrics gateway.

Afterwards `vagrant status` shows the builder as `poweroff`. **That is the expected
end state, not a failure** — it exists only to produce the artifacts in `artifacts/`.

To confirm the whole stack is healthy:

```bash
./scripts/verify.sh
```

It checks all five phases, including submitting a real Slurm job and confirming its
metrics arrive, and reports `49 passed, 0 failed` on a working deployment.

## Accessing the Grafana dashboard

Add one line to your hosts file so the browser can resolve the ingress hostname:

- **Windows** — `C:\Windows\System32\drivers\etc\hosts` (edit as Administrator)
- **Linux / macOS** — `/etc/hosts` (with `sudo`)

```
192.168.56.12  grafana.local
```

Then open **<https://grafana.local>** and log in with Grafana's default credentials:

| | |
|---|---|
| Username | `admin` |
| Password | `admin` |

The certificate is self-signed, so the browser will warn once — accept it and
continue.

Two dashboards are provisioned automatically:

- **Node Exporter Full** (grafana.com ID 1860) — host metrics for both the controller
  and the compute node, selectable with the `instance` dropdown
- **Live Slurm Job Load** — the simulated CPU, GPU and memory values reported by the
  Slurm job, filterable by `SLURM_JOB_ID` and `SLURMD_NODENAME`

A cron entry on the controller submits a Slurm job every 5 minutes, so the Slurm
panels fill in within roughly 10 minutes of the cluster coming up.
