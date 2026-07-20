#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/minio/minio

APP="MinIO"
var_tags="${var_tags:-object-storage}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-5}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

FEATURE_RICH_VERSION="2025-04-22T22-12-26Z"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt-get install -y curl sudo mc
  msg_ok "Installed Dependencies"

  msg_info "Setting up MinIO"
  RELEASE="$FEATURE_RICH_VERSION"
  DOWNLOAD_URL="https://dl.min.io/server/minio/release/linux-amd64/archive/minio.RELEASE.${FEATURE_RICH_VERSION}"
  curl -fsSL "$DOWNLOAD_URL" -o /usr/local/bin/minio
  chmod +x /usr/local/bin/minio
  useradd -r minio-user -s /sbin/nologin
  mkdir -p /home/minio-user
  chown minio-user:minio-user /home/minio-user
  mkdir -p /data
  chown minio-user:minio-user /data
  MINIO_ADMIN_USER="minioadmin"
  MINIO_ADMIN_PASSWORD="$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | cut -c1-13)"
  cat << EOF > /etc/default/minio
MINIO_ROOT_USER=${MINIO_ADMIN_USER}
MINIO_ROOT_PASSWORD=${MINIO_ADMIN_PASSWORD}
EOF
  {
    echo ""
    echo "MinIO Credentials"
    echo "MinIO Admin User: $MINIO_ADMIN_USER"
    echo "MinIO Admin Password: $MINIO_ADMIN_PASSWORD"
  } >> ~/minio.creds
  echo "${RELEASE}" > /opt/${APP,,}_version.txt
  msg_ok "Set up MinIO"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/minio.service
[Unit]
Description=MinIO
Documentation=https://docs.min.io
Wants=network-online.target
After=network-online.target

[Service]
User=minio-user
Group=minio-user
EnvironmentFile=-/etc/default/minio
ExecStart=/usr/local/bin/minio server --console-address ":9001" /data
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now minio
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:9001${CL}"
  echo -e "${INFO}${YW}API available at: ${CL}${BGN}http://${IP}:9000${CL}"
  echo -e "${INFO}${YW}Credentials stored in: ~/minio.creds${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /usr/local/bin/minio ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  RELEASE=$(curl -fsSL https://api.github.com/repos/minio/minio/releases/latest | grep '"tag_name"' | awk -F '"' '{print $4}')
  CURRENT_VERSION=""
  [[ -f /opt/${APP,,}_version.txt ]] && CURRENT_VERSION=$(cat /opt/${APP,,}_version.txt)

  if [[ "${CURRENT_VERSION}" == "${FEATURE_RICH_VERSION}" && "${RELEASE}" != "${FEATURE_RICH_VERSION}" ]]; then
    echo
    echo "You are currently running the last feature-rich community version: ${FEATURE_RICH_VERSION}"
    echo "WARNING: Updating to the latest version will REMOVE most management features from the Console UI."
    echo "Do you still want to upgrade to the latest version? [y/N]: "
    read -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      msg_ok "No update performed. Staying on the feature-rich version."
      exit
    fi
  fi

  if [[ "${CURRENT_VERSION}" != "${RELEASE}" ]]; then
    msg_info "Stopping ${APP}"
    systemctl stop minio
    msg_ok "${APP} Stopped"

    msg_info "Updating ${APP} to ${RELEASE}"
    mv /usr/local/bin/minio /usr/local/bin/minio_bak
    curl -fsSL "https://dl.min.io/server/minio/release/linux-amd64/minio" -o /usr/local/bin/minio
    chmod +x /usr/local/bin/minio
    echo "${RELEASE}" > /opt/${APP,,}_version.txt
    msg_ok "Updated ${APP}"

    msg_info "Starting ${APP}"
    systemctl start minio
    msg_ok "Started ${APP}"

    msg_info "Cleaning up"
    rm -f /usr/local/bin/minio_bak
    msg_ok "Cleaned"

    msg_ok "Updated Successfully"
  else
    msg_ok "No update required. ${APP} is already at ${RELEASE}"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
