#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: havardthom
# Co-Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://ollama.com/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Ollama"
var_tags="${var_tags:-ai}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-40}"
var_os="${var_os:-ubuntu}"
var_version="${var_version:-24.04}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_gpu="${var_gpu:-yes}"

function install_script() {
  setup_hwaccel

  msg_info "Installing Dependencies"
  $STD apt install -y curl
  msg_ok "Installed Dependencies"

  msg_info "Installing Ollama"
  $STD curl -fsSL https://ollama.com/install.sh | sh
  msg_ok "Installed Ollama"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:11434${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /usr/local/lib/ollama ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  [[ -f /root/.ollama ]] && rm -f /root/.ollama

  if check_for_gh_release "ollama-com" "ollama/ollama"; then
    ensure_dependencies zstd
    msg_info "Stopping Services"
    systemctl stop ollama
    msg_ok "Services Stopped"

    local OLLAMA_ARCH
    case "$(uname -m)" in
      x86_64) OLLAMA_ARCH="amd64" ;;
      aarch64) OLLAMA_ARCH="arm64" ;;
      *) OLLAMA_ARCH="amd64" ;;
    esac

    OLLAMA_INSTALL_DIR="/usr/local/lib/ollama"
    rm -rf "$OLLAMA_INSTALL_DIR" /usr/local/bin/ollama
    mkdir -p "$OLLAMA_INSTALL_DIR"
    if ! fetch_and_deploy_gh_release "ollama-com" "ollama/ollama" "prebuild" "latest" "$OLLAMA_INSTALL_DIR" "ollama-linux-${OLLAMA_ARCH}.tar.zst"; then
      msg_error "Download or deployment failed – check network connectivity and GitHub API availability"
      exit 250
    fi
    ln -sf "$OLLAMA_INSTALL_DIR/bin/ollama" /usr/local/bin/ollama
    msg_ok "Updated Ollama"

    msg_info "Starting Services"
    systemctl start ollama
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
