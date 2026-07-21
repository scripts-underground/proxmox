#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/qdrant/qdrant

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Qdrant"
var_tags="${var_tags:-database;vector}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-5}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y curl ca-certificates
  msg_ok "Installed Dependencies"

  local QDRANT_ARCH
  case "$(uname -m)" in
    x86_64) QDRANT_ARCH="amd64" ;;
    aarch64) QDRANT_ARCH="arm64" ;;
    *) QDRANT_ARCH="amd64" ;;
  esac

  msg_info "Installing Qdrant"
  if [[ "${QDRANT_ARCH}" == "arm64" ]]; then
    fetch_and_deploy_gh_release "qdrant" "qdrant/qdrant" "prebuild" "latest" "/usr/bin" "qdrant-aarch64-unknown-linux-musl.tar.gz"
  else
    fetch_and_deploy_gh_release "qdrant" "qdrant/qdrant" "binary" "latest" "/usr/bin/qdrant"
  fi
  msg_ok "Installed Qdrant"

  msg_info "Creating Qdrant Configuration"
  mkdir -p /etc/qdrant
  mkdir -p /var/lib/qdrant/{storage,snapshots}
  chown -R root:root /var/lib/qdrant
  chmod -R 755 /var/lib/qdrant

  cat << EOF > /etc/qdrant/config.yaml
log_level: INFO

storage:
  storage_path: /var/lib/qdrant/storage
  snapshots_path: /var/lib/qdrant/snapshots

service:
  host: 0.0.0.0
  http_port: 6333
  grpc_port: 6334
  enable_cors: true
EOF
  msg_ok "Created Qdrant Configuration"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/qdrant.service
[Unit]
Description=Qdrant Vector Search Engine
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/qdrant --config-path /etc/qdrant/config.yaml
WorkingDirectory=/var/lib/qdrant
Restart=on-failure
RestartSec=5
User=root
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now qdrant
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:6333/dashboard${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /var/lib/qdrant ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "qdrant" "qdrant/qdrant"; then
    msg_info "Stopping Service"
    systemctl stop qdrant
    msg_ok "Stopped Service"

    local QDRANT_ARCH
    case "$(uname -m)" in
      x86_64) QDRANT_ARCH="amd64" ;;
      aarch64) QDRANT_ARCH="arm64" ;;
      *) QDRANT_ARCH="amd64" ;;
    esac

    if [[ "${QDRANT_ARCH}" == "arm64" ]]; then
      fetch_and_deploy_gh_release "qdrant" "qdrant/qdrant" "prebuild" "latest" "/usr/bin" "qdrant-aarch64-unknown-linux-musl.tar.gz"
    else
      fetch_and_deploy_gh_release "qdrant" "qdrant/qdrant" "binary" "latest" "/usr/bin/qdrant"
    fi
    chown -R root:root /var/lib/qdrant
    chmod -R 755 /var/lib/qdrant

    msg_info "Starting Service"
    systemctl start qdrant
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
