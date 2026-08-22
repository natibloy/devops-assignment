#!/usr/bin/env bash
# End-to-end verification of the HPC-DevOps Hybrid Orchestrator.
#
#   ./scripts/verify.sh
#
# Run from the repository root after `vagrant up` has finished. Exits non-zero if
# any check fails, so it is usable as a gate in CI as well as by hand.
#
# Facts are collected in two SSH sessions (one per running node) and asserted
# locally, rather than one SSH call per check, which keeps the whole run to a
# couple of minutes.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

PASS=0
FAIL=0
FAILED_NAMES=()

c_pass=""; c_fail=""; c_dim=""; c_off=""
if [ -t 1 ]; then
  c_pass=$'\033[32m'; c_fail=$'\033[31m'; c_dim=$'\033[2m'; c_off=$'\033[0m'
fi

check() { # <label> <extended-regex> <actual>
  if printf '%s' "$3" | grep -qE "$2"; then
    printf '  %sPASS%s  %s\n' "$c_pass" "$c_off" "$1"
    PASS=$((PASS + 1))
  else
    printf '  %sFAIL%s  %s\n        %sexpected /%s/ in:%s\n' \
      "$c_fail" "$c_off" "$1" "$c_dim" "$2" "$c_off"
    printf '%s' "$3" | sed 's/^/        | /' | head -8
    FAIL=$((FAIL + 1))
    FAILED_NAMES+=("$1")
  fi
}

field() { # <report> <key>   -> the value recorded for that key
  printf '%s' "$1" | sed -n "s/^$2=//p"
}

section() { printf '\n%s\n' "== $1 =="; }

# ---------------------------------------------------------------- collect ----
echo "Collecting state from the running nodes (two SSH sessions)..."

CTL=$(vagrant ssh controller -c '
  echo "id=$(id -u slurm 2>/dev/null)"
  for s in munge mariadb slurmdbd slurmctld node_exporter; do
    echo "svc_$s=$(systemctl is-active $s 2>/dev/null)"
  done
  echo "minions=$(sudo salt --out=txt "*" test.ping 2>/dev/null | tr "\n" " ")"
  echo "keys=$(sudo salt-key -l acc 2>/dev/null | tr "\n" " ")"
  echo "cluster=$(sudo sacctmgr -n -P list cluster format=Cluster 2>/dev/null | tr "\n" " ")"
  echo "sinfo=$(sinfo -h -o "%n:%T" 2>/dev/null | tr "\n" " ")"
  echo "mungemd5=$(sudo md5sum /etc/munge/munge.key 2>/dev/null | cut -d" " -f1)"
  echo "containers=$(sudo podman ps --format "{{.Names}}" 2>/dev/null | tr "\n" " ")"
  echo "container_count=$(sudo podman ps -q 2>/dev/null | wc -l)"
  echo "exporter=$(curl -s --max-time 5 localhost:9100/metrics 2>/dev/null | grep -c "^node_cpu_seconds_total")"
  echo "crons=$(sudo crontab -u vagrant -l 2>/dev/null | grep -c submit_metrics_job)"
  echo "jobscript=$(grep -c SLURM_JOB_ID /opt/slurm-jobs/metrics_job.sbatch 2>/dev/null)"
  echo "dbtables=$(sudo mysql -N -B -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=\"slurm_acct_db\"" 2>/dev/null)"
' 2>/dev/null)

CMP=$(vagrant ssh compute -c '
  export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
  echo "svc_slurmd=$(systemctl is-active slurmd 2>/dev/null)"
  echo "mungemd5=$(sudo md5sum /etc/munge/munge.key 2>/dev/null | cut -d" " -f1)"
  echo "node=$(sudo k3s kubectl get node -o jsonpath="{.items[0].status.conditions[?(@.type==\"Ready\")].status}" 2>/dev/null)"
  echo "helm=$(sudo KUBECONFIG=$KUBECONFIG helm list -A -o json 2>/dev/null | tr -d " \n")"
  echo "pods_bad=$(sudo k3s kubectl get pods -A --no-headers 2>/dev/null | grep -vcE "Running|Completed")"
  echo "ingress=$(sudo k3s kubectl -n monitoring get ingress -o jsonpath="{.items[*].spec.rules[*].host}" 2>/dev/null)"
  echo "tlssecret=$(sudo k3s kubectl -n monitoring get secret grafana-tls -o name 2>/dev/null)"
  echo "dashcm=$(sudo k3s kubectl get cm -A -l grafana_dashboard=1 -o name 2>/dev/null | tr "\n" " ")"
  echo "grafana_http=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 10 --resolve grafana.local:443:127.0.0.1 https://grafana.local/login 2>/dev/null)"
  PIP=$(sudo k3s kubectl -n monitoring get svc kps-kube-prometheus-stack-prometheus -o jsonpath="{.spec.clusterIP}" 2>/dev/null)
  echo "targets=$(curl -s --max-time 10 "http://$PIP:9090/api/v1/targets?state=active" 2>/dev/null | jq -r ".data.activeTargets[] | \"\(.labels.job)|\(.scrapeUrl)|\(.health)\"" 2>/dev/null | sort | tr "\n" " ")"
  echo "images=$(sudo k3s ctr images ls -q 2>/dev/null | grep -c metrics-gateway)"
  DASH=$(sudo k3s kubectl -n monitoring get secret kps-grafana -o jsonpath="{.data.admin-password}" 2>/dev/null | base64 -d)
  USER=$(sudo k3s kubectl -n monitoring get secret kps-grafana -o jsonpath="{.data.admin-user}" 2>/dev/null | base64 -d)
  echo "dashboards=$(curl -sk --max-time 10 -u "$USER:$DASH" --resolve grafana.local:443:127.0.0.1 "https://grafana.local/api/search?type=dash-db" 2>/dev/null | jq -r ".[].title" 2>/dev/null | tr "\n" "|")"
' 2>/dev/null)

if [ -z "$CTL" ] || [ -z "$CMP" ]; then
  echo "ERROR: could not collect state. Are the controller and compute nodes running?" >&2
  echo "       Try: vagrant status" >&2
  exit 2
fi

# ------------------------------------------------------------- phase 1 ------
section "Phase 1 - Vagrant, builder artifacts"
check "slurm DEBs exported"            "slurm-smd-slurmctld"  "$(ls artifacts/debs/ 2>&1)"
check "apt repository indexed"          "Packages.gz"          "$(ls artifacts/debs/ 2>&1)"
check "build sentinel written"          "\.built-"             "$(ls -a artifacts/debs/ 2>&1)"
check "gateway image exported"          "metrics-gateway-.*tar" "$(ls artifacts/images/ 2>&1)"
check "node-exporter image exported"    "node-exporter-.*tar"  "$(ls artifacts/images/ 2>&1)"
check "builder powered off (ephemeral)" "poweroff"             "$(vagrant status builder 2>&1)"

# ------------------------------------------------------------- phase 2 ------
section "Phase 2 - SaltStack"
check "controller minion responds"      "controller"  "$(field "$CTL" minions)"
check "compute minion responds"         "compute"     "$(field "$CTL" minions)"
check "compute key auto-accepted"       "compute"     "$(field "$CTL" keys)"

section "Phase 2 - Slurm cluster"
check "slurm service account exists"    "^[0-9]+$"    "$(field "$CTL" id)"
check "munge active (controller)"       "^active$"    "$(field "$CTL" svc_munge)"
check "munge key identical on both"     "^same$"      "$([ -n "$(field "$CTL" mungemd5)" ] && [ "$(field "$CTL" mungemd5)" = "$(field "$CMP" mungemd5)" ] && echo same || echo DIFFERENT)"
check "mariadb active"                  "^active$"    "$(field "$CTL" svc_mariadb)"
check "accounting schema created"       "^[1-9][0-9]*$" "$(field "$CTL" dbtables)"
check "slurmdbd active"                 "^active$"    "$(field "$CTL" svc_slurmdbd)"
check "slurmctld active"                "^active$"    "$(field "$CTL" svc_slurmctld)"
check "slurmd active (compute)"         "^active$"    "$(field "$CMP" svc_slurmd)"
check "cluster registered in accounting" "lab"        "$(field "$CTL" cluster)"
check "compute node available to Slurm" "compute:(idle|mixed|alloc|comp)" "$(field "$CTL" sinfo)"

section "Phase 2 - Podman telemetry (controller only)"
check "node_exporter container running" "node_exporter" "$(field "$CTL" containers)"
check "exactly one container (no dupes)" "^1$"          "$(field "$CTL" container_count)"
check "exporter serves host metrics"    "^[1-9][0-9]*$" "$(field "$CTL" exporter)"

# ------------------------------------------------------------- phase 3 ------
section "Phase 3 - K3s and Prometheus"
check "k3s node Ready"                  "^True$"      "$(field "$CMP" node)"
check "no pods outside Running/Completed" "^0$"       "$(field "$CMP" pods_bad)"
check "kube-prometheus-stack deployed"  "kube-prometheus-stack.*deployed|deployed.*kube-prometheus-stack" "$(field "$CMP" helm)"
check "grafana ingress on grafana.local" "grafana\.local" "$(field "$CMP" ingress)"
check "grafana TLS secret present"      "grafana-tls" "$(field "$CMP" tlssecret)"
check "grafana answers over HTTPS"      "^200$"       "$(field "$CMP" grafana_http)"

TARGETS=$(field "$CMP" targets)
printf '  %sscrape targets:%s\n' "$c_dim" "$c_off"
printf '%s' "$TARGETS" | tr ' ' '\n' | sed '/^$/d;s/^/        /'
check "controller node exporter UP"     "192\.168\.56\.11:9100/metrics\|up" "$TARGETS"
check "compute node exporter UP"        "192\.168\.56\.12:9100/metrics\|up" "$TARGETS"
check "single node-exporter-hosts job"  "node-exporter-hosts"               "$TARGETS"
check "no scrape target down"           "^0$" "$(printf '%s' "$TARGETS" | tr ' ' '\n' | grep -c '|down$')"
check "Node Exporter Full dashboard (1860)" "Node Exporter Full" "$(field "$CMP" dashboards)"

# ------------------------------------------------------------- phase 4 ------
section "Phase 4 - metrics gateway"
check "gateway image imported to containerd" "^[1-9]" "$(field "$CMP" images)"
check "gateway Helm release deployed"   "metrics-gateway.*deployed|deployed.*metrics-gateway" "$(field "$CMP" helm)"
check "gateway scraped by Prometheus"   "metrics-gateway.*\|up"  "$TARGETS"

GW_PUT=$(vagrant ssh controller -c 'curl -sS --max-time 8 -X PUT http://192.168.56.12:30080/update-metric -H "Content-Type: application/json" -d "{\"name\":\"verify_probe\",\"value\":42,\"labels\":{\"SLURM_JOB_ID\":\"0\",\"SLURMD_NODENAME\":\"compute\"}}"' 2>/dev/null)
check "PUT /update-metric accepted"     '"status": *"ok"' "$GW_PUT"
GW_GET=$(vagrant ssh controller -c 'curl -s --max-time 8 http://192.168.56.12:30080/metrics | grep verify_probe' 2>/dev/null)
check "/metrics exposes it (Prom format)" "verify_probe\{" "$GW_GET"

# ------------------------------------------------------------- phase 5 ------
section "Phase 5 - the hybrid loop"
check "cron entry installed"            "^1$"          "$(field "$CTL" crons)"
check "job script uses SLURM_JOB_ID"    "^[1-9]"       "$(field "$CTL" jobscript)"
check "Live Slurm Job Load dashboard"   "Live Slurm Job Load" "$(field "$CMP" dashboards)"
check "dashboard shipped as ConfigMap"  "metrics-gateway" "$(field "$CMP" dashcm)"

echo
echo "Submitting a real Slurm job and waiting ~80s for it to report..."
JOB=$(vagrant ssh controller -c 'sudo -u vagrant /opt/slurm-jobs/submit_metrics_job.sh; sleep 80; sudo tail -3 /var/log/slurm-metrics-submit.log' 2>/dev/null)
check "cron script submitted a job"     "Submitted batch job" "$JOB"
SERIES=$(vagrant ssh controller -c 'curl -s --max-time 8 http://192.168.56.12:30080/metrics | grep "^slurm_job_"' 2>/dev/null)
for m in cpu gpu memory; do
  check "slurm_job_${m}_usage_percent reported" "slurm_job_${m}_usage_percent\{" "$SERIES"
done
check "series carry SLURM_JOB_ID"       'SLURM_JOB_ID="[0-9]+"'   "$SERIES"
check "series carry SLURMD_NODENAME"    'SLURMD_NODENAME="compute"' "$SERIES"

# ---------------------------------------------------------------- result ----
echo
echo "================================================"
printf 'PASS: %s%d%s   FAIL: %s%d%s\n' "$c_pass" "$PASS" "$c_off" \
  "$( [ "$FAIL" -gt 0 ] && printf '%s' "$c_fail" )" "$FAIL" "$c_off"
if [ "$FAIL" -gt 0 ]; then
  echo
  echo "Failed checks:"
  printf '  - %s\n' "${FAILED_NAMES[@]}"
  exit 1
fi
echo "All checks passed."
