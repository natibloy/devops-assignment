# The HPC-DevOps Hybrid Orchestrator

A one-button (`vagrant up`) lab that bridges a traditional Slurm HPC cluster with a
cloud-native observability stack. Everything below is built from source and
configured by SaltStack; nothing is set up by hand.

```
                     host-only network 192.168.56.0/24
                                                                  
  builder .10            controller .11                compute .12
  ephemeral              Salt master                   Salt minion
  -------------          ----------------------        --------------------------
  compiles Slurm         slurmctld + slurmdbd          slurmd
  DEBs from source       MariaDB (accounting)          K3s (single node)
  builds the gateway     munge                         kube-prometheus-stack
  container image        Podman + node_exporter        metrics-gateway (Helm)
  then powers off        Phase 5 cron -> sbatch        Grafana @ grafana.local

  artifacts/  <-- shared folder: DEBs + container image tars flow builder -> others
```

## Requirements

| | |
|---|---|
| Vagrant | 2.4.x |
| VirtualBox | 7.0 / 7.1 |
| Host resources | 16 GB RAM and 12 vCPU free at peak (12 GB / 8 vCPU once the builder powers off) |
| Disk | ~20 GB |
| Network | Internet access on first run (box, Debian packages, Helm charts, Grafana dashboard 1860) |

No Vagrant plugins are required.

## Quick start

```bash
git clone <this-repo> && cd devops-assignment
vagrant up
```

> If VirtualBox was only just installed or upgraded, reboot before the first
> `vagrant up` — its host-only network driver is not usable until the host restarts.
> See [Troubleshooting](#troubleshooting).

Then add one line to your hosts file so the browser can find Grafana.

- **Windows** (`C:\Windows\System32\drivers\etc\hosts`, as Administrator)
- **Linux / macOS** (`/etc/hosts`, with sudo)

```
192.168.56.12  grafana.local
```

Open **<https://grafana.local>** and log in with Grafana's default credentials,
**`admin` / `admin`**. The certificate is self-signed, so accept the browser warning
once.

Two dashboards are provisioned automatically:

- **Node Exporter Full** (grafana.com ID 1860) — both hosts, selectable by `instance`
- **Live Slurm Job Load** — the Phase 5 metrics, filterable by `SLURM_JOB_ID` and `SLURMD_NODENAME`

The Phase 5 cron submits a job every 5 minutes, so the Slurm panels fill in within
about 10 minutes of the cluster coming up.

### What `vagrant up` does, in order

1. **builder** boots, applies its masterless highstate: installs Podman, downloads
   and compiles Slurm into separate `slurm-smd-*` DEBs, indexes them as an apt
   repository, builds the gateway container image, and exports all of it to
   `artifacts/`. A verification step asserts the artifacts exist, then the box
   powers itself off. Expect **10–25 minutes** for the compile.
2. **controller** boots, the Salt provisioner installs the master (with
   `auto_accept`) and a local minion, and the highstate brings up munge, MariaDB,
   the Slurm control plane, the Podman node_exporter and the Phase 5 cron.
3. **compute** boots, its minion registers with the master, and its highstate
   installs slurmd, K3s, the Prometheus stack and the metrics-gateway chart.

`vagrant status` afterwards shows the builder as `poweroff` — that is the expected
end state, not a failure.

## Verifying the deployment

The quickest check is the bundled suite, which covers all five phases — including
submitting a real Slurm job and confirming its metrics arrive:

```bash
./scripts/verify.sh
```

It prints a PASS/FAIL line per check and exits non-zero if any fail, so it also
works as a CI gate. A healthy deployment reports **49 passed, 0 failed**; the run
takes a couple of minutes, most of it waiting for the Slurm job to finish
reporting. It needs only the controller and compute nodes running (the builder is
expected to be powered off).

The individual commands, if you would rather check by hand:

```bash
# Artifacts produced by the builder (run on the host)
ls artifacts/debs/*.deb artifacts/images/*.tar

# Salt (on the controller)
vagrant ssh controller -c "sudo salt '*' test.ping"
vagrant ssh controller -c "sudo salt-key -l acc"

# Slurm
vagrant ssh controller -c "sinfo && sacctmgr -n show cluster"
vagrant ssh controller -c "sbatch --wrap 'hostname' && sleep 20 && sacct"

# Controller's Podman node_exporter
vagrant ssh controller -c "sudo podman ps && curl -s localhost:9100/metrics | head -3"

# Metrics gateway, reached from the controller exactly as the Slurm job does
vagrant ssh controller -c "curl -sS -X PUT http://192.168.56.12:30080/update-metric \
  -H 'Content-Type: application/json' \
  -d '{\"name\":\"demo_metric\",\"value\":1,\"labels\":{\"SLURM_JOB_ID\":\"0\"}}'"
vagrant ssh controller -c "curl -s http://192.168.56.12:30080/metrics | grep demo_metric"

# K3s and the monitoring stack
vagrant ssh compute -c "sudo k3s kubectl get nodes,pods -A"
vagrant ssh compute -c "sudo helm -n monitoring list && sudo helm -n gateway list"
```

Prometheus targets are easiest to check in Grafana
(*Connections → Data sources → Prometheus → ...*) or by port-forwarding:

```bash
vagrant ssh compute -c "sudo k3s kubectl -n monitoring port-forward svc/kps-kube-prometheus-stack-prometheus 9090:9090 --address 0.0.0.0"
```

The `node-exporter-hosts` job should show **2/2 up** (controller and compute) and the
`gateway/metrics-gateway` ServiceMonitor target should be up.

### Idempotency

Re-running the highstate must not break services or duplicate containers:

```bash
vagrant provision controller compute
vagrant ssh controller -c "sudo podman ps"                    # exactly one node_exporter
vagrant ssh controller -c "sudo crontab -u vagrant -l"        # exactly one cron line
vagrant ssh compute -c "sudo helm -n monitoring history kps"  # no new revision
```

## How it is built

### Phase 1 — Vagrant and artifacts

`Vagrantfile` defines the three nodes. Addressing and VM sizing are **read from
`salt/pillar/network.sls`** with `YAML.load_file`, so the pillar is the single source
of truth for both Vagrant and Salt and no IP is written twice. The compute node's
minion config is rendered at `vagrant up` time from that same pillar value.

All three nodes are provisioned by the **Vagrant Salt provisioner**, pointed at a
vendored `provision/bootstrap-salt.sh` so a first run never depends on a live
redirect from the Salt project's download host.

The builder is masterless (`file_client: local`) against the *same* state tree the
master later serves, which is what lets the Podman setup be one state file shared
by the builder and the controller instead of two copies.

Slurm is built with its own `debian/` packaging (`mk-build-deps` + `dpkg-buildpackage`), which
is what produces the separated `slurm-smd`, `slurm-smd-client`, `slurm-smd-slurmctld`,
`slurm-smd-slurmd` and `slurm-smd-slurmdbd` packages. Only those five of Slurm's
seventeen binary packages are ever installed, so the build skips the work nothing
here consumes — debug packages, manuals, the test suite and the packaging audit —
which more than halves both the build time and the bytes crossing the shared folder. The build runs in
`/root/build` on the guest, never in the shared folder — VirtualBox's vboxsf cannot
represent the symlinks and hardlinks `dpkg-buildpackage` creates. Only the finished
`.deb` files are copied out, then indexed with `dpkg-scanpackages` so the other nodes
consume them as a real apt repository and let apt resolve the dependencies between
them.

### Phase 2 — SaltStack

The master auto-accepts minion keys (`salt/etc/master.conf`). The controller runs its
own minion against `localhost`, so the controller and the compute node converge
through the identical `state.highstate` path rather than one being special-cased.

`salt/states/top.sls` targets on the `role` grain, so no state ever needs to know a
node's hostname. Every tunable, credential, version and address lives in
`salt/pillar/`; the state files and templates contain no literal values. The one
cross-node contract — the layout of the shared artifact folder — is derived in
`salt/states/artifacts.jinja` from a single pillar key, so the builder that writes
an export and the node that reads it can never disagree about its name.

Idempotency, state by state:

| State | How re-running stays safe |
|---|---|
| `builder.slurm_build` | A `.built-<version>` sentinel skips the whole compile |
| `builder.images` | `creates:` on the exported image tars |
| `node_exporter` | systemd owns a single named container started with `podman run --replace`; the service only restarts when the unit file changes |
| `munge` | The `unless` compares the installed key against the pillar's, so it writes on first run, again if the pillar changes, and never otherwise |
| `mariadb` | The guard is a real login as the Slurm account against its own database, so the SQL is applied on the first run, again if the password or grants drift, and never otherwise |
| `slurm` user | `group.present` / `user.present` with a pinned uid, since Slurm's DEBs ship no `postinst` to create it |
| `k3s-api-ready` | A readiness barrier, guarded so a converged cluster does not report it as a change every run |
| `slurm.*` | `pkg.installed` from the local apt repo; configs via `file.managed` with services on `watch` |
| `k3s`, `helm` | `creates:` / version guards |
| `kps-release`, `gateway-release` | A stamp file holds the hash of the last successfully deployed values (or chart tree). A no-op highstate skips Helm entirely, a real change forces an upgrade, and a *failed* deploy is retried — both because the stamp is only written when Helm exits 0, and because the guard also requires the release to report `deployed`. Both releases share the guard via `salt/states/k3s/macros.jinja` |
| `k3s`, `helm-repo` | Guarded on the pinned version and the repo URL rather than on a binary existing, so bumping a pillar version actually upgrades instead of silently reporting success |
| `phase5` | `cron.present` is keyed by identifier, so the crontab converges on one line |
| `time-sync` | An NTP client runs on every node. Munge stamps each credential with a timestamp and rejects any outside a tolerance window, so drifting clocks break Slurm RPCs with what looks like a bad key. VirtualBox's guest time sync does not step a large offset — this was observed as a 14-minute drift on the compute node |

### Phase 3 — K3s and Prometheus

K3s is installed with `--node-ip`/`--advertise-address`/`--flannel-iface` pinned to
the private network. This is not optional: every VirtualBox guest shares the same
NAT address `10.0.2.15` on `eth0`, and without pinning, K3s advertises that address
and its own kubelet becomes unreachable.

`kube-prometheus-stack` is installed with the Helm binary rather than K3s's
`HelmChart` CRD, so the same mechanism deploys both this chart and the in-repo
gateway chart, and `--wait` gives Salt a real success signal.

The gateway chart itself is served **by the Salt master**: `charts/` is a second
`file_roots` entry, and the compute node pulls it with `file.recurse` into a
guest-local directory before Helm installs from there. It previously read the chart
straight off Vagrant's `/vagrant` synced folder, which tied that state to a Vagrant
guest of this checkout and quietly undercut the point that compute gets everything
from the master.

`additionalScrapeConfigs` exists for targets the Prometheus Operator cannot discover
by itself, and that is exactly the controller: its node_exporter is a Podman container
on a machine that is not a Kubernetes node, so no ServiceMonitor can select it. The
compute node's exporter is the chart's own DaemonSet — in-cluster, and already scraped
by the ServiceMonitor that ships with it, left at its defaults.

So each exporter is scraped once, by the mechanism suited to it, and both are covered.
Because the DaemonSet runs with `hostNetwork`, its pod address is the node's own
address, so both targets are scraped at `<node ip>:9100` and carry consistent labels
without any relabelling.

The requirement — *"configure additionalScrapeConfigs to scrape the Node Exporters on
both the Controller and Compute nodes"* — also reads as putting both hosts in the
static config and disabling the chart's ServiceMonitor to avoid double-scraping. That
works too, and satisfies the sentence more literally. This version was chosen because
it changes no chart default the assignment did not mention, and because using
`additionalScrapeConfigs` for the out-of-cluster target and a ServiceMonitor for the
in-cluster one is the idiomatic split.

Grafana gets its admin credentials from the pillar, dashboard 1860 through `gnetId`
provisioning, and an ingress on `grafana.local` with a self-signed certificate served
by K3s's built-in Traefik.

The accounting database is provisioned through the `mysql` client rather than
Salt's `mysql_*` states. Those states only load when a MySQL driver is importable
from Salt's bundled interpreter, and the state compiler resolves state functions
*before* any state could install one — so a first highstate on a fresh minion fails
outright with `State 'mysql_database.present' was not found`. The SQL is written to
a root-only file and applied when a real login as the Slurm account fails, which
keeps the password off every command line.

### Phase 4 — metrics gateway

`gateway/app.py` is a Flask service with `PUT /update-metric` and `GET /metrics`
(plus `/healthz` for probes). The first payload for a metric name fixes its label
set, and later payloads with a different label set are rejected with `409` — a
consequence of how `prometheus_client` binds label names at `Gauge` creation.

It runs under a **single** gunicorn worker on purpose. The registry lives in process
memory, so a second worker would answer `/metrics` from its own partial view of the
samples.

Because every job reports under its own `SLURM_JOB_ID`, each one leaves three label
sets behind that are never written again — roughly 900 dead series a day at a job
every five minutes. Prometheus has already stored their samples, so the gateway
drops any series it has not seen for `SERIES_TTL_SECONDS` (default one hour) and
`/metrics` stays bounded. Dashboard history is unaffected, since the panels query
Prometheus rather than the gateway.

The image is built on the builder, exported as a tar, and side-loaded into containerd
with `k3s ctr images import`; the Deployment uses `imagePullPolicy: IfNotPresent` so a
pull is never attempted. `charts/metrics-gateway/` exposes it on a fixed NodePort so
the Slurm job can reach it at a predictable address, and ships both a ServiceMonitor
and the Phase 5 Grafana dashboard as a sidecar-labelled ConfigMap.

### Phase 5 — the hybrid loop

A cron entry on the controller runs every 5 minutes and `sbatch`es the job. Slurm
dispatches it to the compute node, which is where `SLURM_JOB_ID` and
`SLURMD_NODENAME` actually exist — so submission is on the controller, as the
assignment specifies, and the reporter body runs under `slurmd`.

For one minute the job pushes simulated CPU, GPU and memory values every 5 seconds,
labelled with both Slurm variables. Because the gateway holds the last value per
series, Prometheus can still scrape samples from a job that has already exited.

## Troubleshooting

**`vagrant up` looks stuck on the builder.** It is compiling Slurm. `verbose` is on
for the Salt provisioner, so output appears in bursts; the compile is 10–25 minutes.

**Grafana does not resolve.** The hosts-file entry above is required — nothing in the
guest can add it for you. Verify with `curl -k https://192.168.56.12 -H 'Host: grafana.local'`.

**`vagrant up` fails with `VERR_INTNET_FLT_IF_NOT_FOUND`.** VirtualBox cannot attach
the host-only adapter. This means its network filter driver was installed or replaced
by an installer and the host has not been restarted since, so the driver in memory no
longer matches the one on disk — no VM using a host-only network will start.

**Reboot the host.** That is the whole fix; there is nothing to change in this
repository. It is worth checking before a first run on a machine where VirtualBox or
Vagrant was just installed.

**Everything is very slow.** On Windows, Hyper-V/VBS forces VirtualBox into its slower
NEM execution mode (VirtualBox shows a green turtle icon). Disabling Hyper-V,
Windows Sandbox, WSL2 and Memory Integrity restores hardware virtualisation.

**Synced folders fail to mount.** The box ships VirtualBox Guest Additions matched to
7.x, but if your VirtualBox is much newer, install `vagrant plugin install vagrant-vbguest`
and `vagrant reload --provision`.

**Rebuilding Slurm.** Bump `slurm:version` in `salt/pillar/slurm.sls`, then
`vagrant up builder --provision`. The sentinel name includes the version, so a new
version rebuilds and an unchanged one does not.

**Starting over.** `vagrant destroy -f && rm -rf artifacts/debs artifacts/images`.
Leaving `artifacts/` in place makes the next `vagrant up` skip the Slurm compile.

## Repository layout

```
Vagrantfile                     three nodes; reads addressing/sizing from the pillar
provision/bootstrap-salt.sh     vendored, pinned Salt bootstrap
artifacts/                      build output shared between nodes (git-ignored)
salt/etc/                       master and minion configs
salt/states/                    the state tree (also served masterless to the builder)
salt/states/artifacts.jinja     shared-folder layout, imported by producer and consumers
salt/states/k3s/macros.jinja    the namespace and Helm-release idioms both charts use
scripts/verify.sh               49-check end-to-end verification of all five phases
salt/pillar/                    every version, address, credential and tunable
gateway/                        the Phase 4 microservice and its Containerfile
charts/metrics-gateway/         Helm chart, ServiceMonitor, Phase 5 dashboard
```
