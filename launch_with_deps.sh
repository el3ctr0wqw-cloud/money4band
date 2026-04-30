#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${ROOT_DIR}/bin"
AMD64_URL="https://github.com/el3ctr0wqw-cloud/money4band/releases/download/test/Money4Band-linux-amd64"
ARM64_URL="https://github.com/el3ctr0wqw-cloud/money4band/releases/download/test/Money4Band-linux-arm64"
SUDO=""

info() { echo "[INFO] $*" >&2; }
warn() { echo "[WARN] $*" >&2; }
fail() { echo "[FAIL] $*" >&2; exit 1; }

require_sudo() {
  if [[ "${EUID}" -eq 0 ]]; then
    SUDO=""
    return 0
  fi
  if ! command -v sudo >/dev/null 2>&1; then
    fail "sudo is required for dependency installation. Re-run as root or install sudo."
  fi
  SUDO="sudo"
}

install_docker_if_missing() {
  if command -v docker >/dev/null 2>&1; then
    info "Docker CLI already installed."
    return 0
  fi

  require_sudo
  info "Docker not found. Installing Docker..."

  if [[ -f /etc/debian_version ]]; then
    ${SUDO} apt-get update
    ${SUDO} apt-get install -y ca-certificates curl gnupg lsb-release
    ${SUDO} install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/$(. /etc/os-release; echo "${ID}")/gpg | ${SUDO} gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    ${SUDO} chmod a+r /etc/apt/keyrings/docker.gpg
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$(. /etc/os-release; echo "${ID}") \
      $(. /etc/os-release; echo "${VERSION_CODENAME}") stable" | ${SUDO} tee /etc/apt/sources.list.d/docker.list >/dev/null
    ${SUDO} apt-get update
    ${SUDO} apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  elif command -v dnf >/dev/null 2>&1; then
    ${SUDO} dnf -y install dnf-plugins-core
    ${SUDO} dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
    ${SUDO} dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  elif command -v yum >/dev/null 2>&1; then
    ${SUDO} yum install -y yum-utils
    ${SUDO} yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    ${SUDO} yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  else
    fail "Unsupported distro for auto-install. Install Docker manually and rerun."
  fi
}

ensure_downloader() {
  if command -v curl >/dev/null 2>&1; then
    return 0
  fi
  if command -v wget >/dev/null 2>&1; then
    return 0
  fi

  require_sudo
  info "Installing curl (downloader dependency)..."
  if [[ -f /etc/debian_version ]]; then
    ${SUDO} apt-get update
    ${SUDO} apt-get install -y curl
  elif command -v dnf >/dev/null 2>&1; then
    ${SUDO} dnf -y install curl
  elif command -v yum >/dev/null 2>&1; then
    ${SUDO} yum -y install curl
  else
    fail "No curl/wget and unsupported distro for auto-install."
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
    ${SUDO} systemctl enable docker >/dev/null 2>&1 || true
    ${SUDO} systemctl start docker
  else
    ${SUDO} service docker start
  fi

  if ! docker info >/dev/null 2>&1; then
    if getent group docker >/dev/null 2>&1 && ! id -nG "${USER}" | grep -qw docker; then
      warn "Docker is installed but current user is not in docker group."
      warn "Run: ${SUDO:-sudo }usermod -aG docker ${USER} && newgrp docker"
    fi
    fail "Docker engine is not ready. Start Docker manually and rerun."
  fi
}

download_binary_for_arch() {
  local arch
  local url=""
  local out_bin=""
  arch="$(uname -m)"
  case "${arch}" in
    x86_64|amd64)
      url="${AMD64_URL}"
      out_bin="${BIN_DIR}/Money4Band-linux-amd64"
      ;;
    aarch64|arm64)
      url="${ARM64_URL}"
      out_bin="${BIN_DIR}/Money4Band-linux-arm64"
      ;;
    *)
      fail "Unsupported architecture: ${arch}"
      ;;
  esac

  mkdir -p "${BIN_DIR}"
  info "Detected architecture: ${arch}"
  info "Downloading binary from: ${url}"

  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 --connect-timeout 10 -o "${out_bin}" "${url}"
  else
    wget -O "${out_bin}" "${url}"
  fi

  chmod +x "${out_bin}"
  echo "${out_bin}"
}

main() {
  info "Working directory: ${ROOT_DIR}"
  ensure_downloader
  install_docker_if_missing
  ensure_docker_running

  local bin
  bin="$(download_binary_for_arch)"
  info "Launching binary: ${bin}"
  if "${bin}" --autopilot-services; then
    echo "[STATUS] OK - Money4Band launched successfully with --autopilot-services" >&2
  else
    code=$?
    echo "[STATUS] FAIL - Money4Band exited with code ${code}" >&2
    exit "${code}"
  fi
}

main "$@"
