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
  curl -fsSL https://get.docker.com | sh
fi
usermod -aG docker "$RUNNER_USER" || true

log "Installing Nomad and Consul (HashiCorp apt repo)"
if [[ ! -f /usr/share/keyrings/hashicorp-archive-keyring.gpg ]]; then
  curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
    > /etc/apt/sources.list.d/hashicorp.list
  apt-get update -y
fi
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
bind_addr  = "0.0.0.0"

server {
  enabled          = true
  bootstrap_expect = 1
}

client {
  enabled = true
}

consul {
  address = "127.0.0.1:8500"
}

plugin "docker" {
  config {
    allow_privileges = false
  }
}
HCL

systemctl enable --now consul
systemctl enable --now nomad

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
    curl -fsSL -o runner.tar.gz \
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

log "Checking everything is up"
sleep 5
curl -fsS http://127.0.0.1:5000/v2/ >/dev/null && echo "registry: ok"
consul members || true
nomad node status || true

echo
echo "Lab is up. Nomad UI: http://localhost:4646  Consul UI: http://localhost:8500"
echo "Log out and back in so '$RUNNER_USER' picks up the docker group."
