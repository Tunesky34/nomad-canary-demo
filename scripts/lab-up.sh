#!/usr/bin/env bash
# One-command lab setup for Ubuntu 22.04/24.04.
# Installs Docker, Nomad, Consul; starts a local registry; optionally registers
# a GitHub Actions self-hosted runner.
#
# Usage:
#   sudo ./scripts/lab-up.sh
#   sudo RUNNER_URL=https://github.com/<intern-org>/<repo> RUNNER_TOKEN=<token> ./scripts/lab-up.sh
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

RUNNER_VERSION="${RUNNER_VERSION:-2.321.0}"
RUNNER_USER="${RUNNER_USER:-${SUDO_USER:-ubuntu}}"
RUNNER_DIR="${RUNNER_DIR:-/opt/actions-runner}"

log() { printf '\n==> %s\n' "$*"; }

log "Installing base packages"
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release unzip jq

log "Installing Docker"
if ! command -v docker >/dev/null; then
  curl --proto '=https' --proto-redir '=https' -fsSL https://get.docker.com | sh
fi
usermod -aG docker "$RUNNER_USER" || true

log "Installing Nomad and Consul (HashiCorp apt repo)"
# Refresh the signing key on every run: HashiCorp rotates it, and a stale key makes
# `apt update` fail with NO_PUBKEY for this repo.
curl --proto '=https' --proto-redir '=https' -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor --yes -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
  > /etc/apt/sources.list.d/hashicorp.list
apt-get update -y || true
apt-get install -y nomad consul

log "Writing lab configs (single-node dev setup, NOT for production)"
mkdir -p /etc/nomad.d /etc/consul.d /opt/nomad/data /opt/consul/data

cat > /etc/consul.d/consul.hcl <<'HCL'
datacenter = "lab"
data_dir   = "/opt/consul/data"
server     = true
bootstrap_expect = 1
bind_addr  = "127.0.0.1"
client_addr = "127.0.0.1"
ui_config { enabled = true }
HCL

cat > /etc/nomad.d/nomad.hcl <<'HCL'
datacenter = "lab"
data_dir   = "/opt/nomad/data"
bind_addr  = "127.0.0.1"

# Required when binding to loopback: Nomad refuses to default the advertise address
# to localhost ("Defaulting advertise to localhost is unsafe").
advertise {
  http = "127.0.0.1"
  rpc  = "127.0.0.1"
  serf = "127.0.0.1"
}

server {
  enabled          = true
  bootstrap_expect = 1
}

client {
  enabled = true
  # Loopback keeps service addresses stable when a laptop's DHCP address changes.
  network_interface = "lo"
}

consul {
  address = "127.0.0.1:8500"
}

plugin "docker" {
  config {
    allow_privileged = false
  }
}
HCL

# The HashiCorp package runs Consul as user "consul"; it must own its data and config.
if id consul >/dev/null 2>&1; then
  chown -R consul:consul /opt/consul /etc/consul.d
fi

log "Validating Nomad config"
nomad config validate /etc/nomad.d/nomad.hcl

start_service() {
  systemctl enable "$1" >/dev/null 2>&1 || true
  # A service that crash-looped is rate-limited by systemd ("start request repeated
  # too quickly") until its failed state is cleared.
  systemctl reset-failed "$1" >/dev/null 2>&1 || true
  if ! systemctl restart "$1"; then
    echo "ERROR: $1 failed to start. Last log lines:" >&2
    journalctl -u "$1" -n 40 --no-pager >&2 || true
    exit 1
  fi
}
# The packaged unit is Type=notify and, on a single-node lab server, systemd can time out
# waiting for Consul's "ready" signal even though Consul runs fine. Skip that handshake;
# the wait_for checks below verify the real HTTP endpoint instead. (Drop-in, so package
# upgrades do not overwrite it.)
mkdir -p /etc/systemd/system/consul.service.d
printf '[Service]\nType=simple\n' > /etc/systemd/system/consul.service.d/lab.conf
systemctl daemon-reload

start_service consul
start_service nomad

log "Starting lab registry on localhost:5000"
if ! docker ps -a --format '{{.Names}}' | grep -qx lab-registry; then
  docker run -d --restart=always --name lab-registry -p 127.0.0.1:5000:5000 registry:2
else
  docker start lab-registry >/dev/null || true
fi

if [[ -n "${RUNNER_URL:-}" && -n "${RUNNER_TOKEN:-}" ]]; then
  log "Registering GitHub Actions self-hosted runner"
  mkdir -p "$RUNNER_DIR"
  cd "$RUNNER_DIR"
  if [[ ! -f config.sh ]]; then
    curl --proto '=https' --proto-redir '=https' -fsSL -o runner.tar.gz \
      "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz"
    tar xzf runner.tar.gz && rm runner.tar.gz
  fi
  chown -R "$RUNNER_USER":"$RUNNER_USER" "$RUNNER_DIR"
  sudo -u "$RUNNER_USER" ./config.sh --unattended --replace \
    --url "$RUNNER_URL" --token "$RUNNER_TOKEN" --labels lab
  ./svc.sh install "$RUNNER_USER"
  ./svc.sh start
else
  log "Skipping runner registration (set RUNNER_URL and RUNNER_TOKEN to enable)"
fi

log "Waiting for Nomad and Consul to answer"
wait_for() {  # name url
  for _ in $(seq 1 60); do
    if curl -fsS "$2" >/dev/null 2>&1; then echo "$1: ok"; return 0; fi
    sleep 1
  done
  echo "ERROR: $1 did not come up at $2" >&2
  systemctl status "$3" --no-pager -l 2>&1 | tail -15 >&2 || true
  journalctl -u "$3" -n 40 --no-pager >&2 || true
  return 1
}
wait_for registry http://127.0.0.1:5000/v2/ docker
wait_for consul   http://127.0.0.1:8500/v1/status/leader consul
wait_for nomad    http://127.0.0.1:4646/v1/status/leader nomad
consul members || true
nomad node status || true

echo
echo "Lab is up. Nomad UI: http://localhost:4646  Consul UI: http://localhost:8500"
echo "Log out and back in so '$RUNNER_USER' picks up the docker group."
