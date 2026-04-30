#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AMD64_BIN="${ROOT_DIR}/dist-portable/Money4Band-linux-amd64"
ARM64_BIN="${ROOT_DIR}/dist-portable-arm64/Money4Band-linux-arm64"

info() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*"; }
fail() { echo "[FAIL] $*"; exit 1; }

require_sudo() {
  if [[ "${EUID}" -eq 0 ]]; then
    return 0
  fi
  if ! command -v sudo >/dev/null 2>&1; then
    fail "sudo is required for dependency installation. Re-run as root or install sudo."
  fi
}

install_docker_if_missing() {
  if command -v docker >/dev/null 2>&1; then
    info "Docker CLI already installed."
    return 0
  fi

  require_sudo
  info "Docker not found. Installing Docker..."

  if [[ -f /etc/debian_version ]]; then
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg lsb-release
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/$(. /etc/os-release; echo "${ID}")/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$(. /etc/os-release; echo "${ID}") \
      $(. /etc/os-release; echo "${VERSION_CODENAME}") stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf -y install dnf-plugins-core
    sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
    sudo dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  elif command -v yum >/dev/null 2>&1; then
    sudo yum install -y yum-utils
    sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  else
    fail "Unsupported distro for auto-install. Install Docker manually and rerun."
  fi
}

ensure_docker_running() {
  if docker info >/dev/null 2>&1; then
    info "Docker engine already running."
    return 0
  fi

  require_sudo
  info "Starting Docker service..."
  if command -v systemctl >/dev/null 2>&1; then
    sudo systemctl enable docker >/dev/null 2>&1 || true
    sudo systemctl start docker
  else
    sudo service docker start
  fi

  if ! docker info >/dev/null 2>&1; then
    if getent group docker >/dev/null 2>&1 && ! id -nG "${USER}" | grep -qw docker; then
      warn "Docker is installed but current user is not in docker group."
      warn "Run: sudo usermod -aG docker ${USER} && newgrp docker"
    fi
    fail "Docker engine is not ready. Start Docker manually and rerun."
  fi
}

select_binary() {
  local arch
  arch="$(uname -m)"
  case "${arch}" in
    x86_64|amd64)
      [[ -x "${AMD64_BIN}" ]] || fail "Missing amd64 binary: ${AMD64_BIN}. Build it first."
      echo "${AMD64_BIN}"
      ;;
    aarch64|arm64)
      [[ -x "${ARM64_BIN}" ]] || fail "Missing arm64 binary: ${ARM64_BIN}. Build it first."
      echo "${ARM64_BIN}"
      ;;
    *)
      fail "Unsupported architecture: ${arch}"
      ;;
  esac
}

main() {
  info "Working directory: ${ROOT_DIR}"
  install_docker_if_missing
  ensure_docker_running

  local bin
  bin="$(select_binary)"
  info "Launching binary: ${bin}"
  "${bin}" --autopilot-services
}

main "$@"
