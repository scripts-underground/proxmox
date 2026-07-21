#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://forgejo.org/

# shellcheck disable=SC2034
APP="Forgejo"
var_tags="${var_tags:-git}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y git git-lfs
  msg_ok "Installed Dependencies"

  fetch_and_deploy_codeberg_release "forgejo" "forgejo/forgejo" "singlefile" "latest" "/opt/forgejo" "forgejo-*-linux-$(get_system_arch)"
  ln -sf /opt/forgejo/forgejo /usr/local/bin/forgejo

  msg_info "Creating Forgejo User"
  $STD adduser --system --group --disabled-password --disabled-login --shell /bin/bash --home /var/lib/forgejo git
  msg_ok "Created Forgejo User"

  msg_info "Creating Directory Structure"
  mkdir -p /var/lib/forgejo/{custom,data,log}
  mkdir -p /etc/forgejo
  chown -R git:git /var/lib/forgejo /opt/forgejo
  chown root:git /etc/forgejo
  chmod 770 /etc/forgejo
  msg_ok "Created Directory Structure"

  msg_info "Creating Service"
  cat << 'EOF' > /etc/systemd/system/forgejo.service
[Unit]
Description=Forgejo
After=syslog.target network.target

[Service]
Type=simple
User=git
Group=git
WorkingDirectory=/var/lib/forgejo/
ExecStart=/usr/local/bin/forgejo web --config /etc/forgejo/app.ini
Restart=always
RestartSec=2s
Environment=FORGEJO_WORK_DIR=/var/lib/forgejo
Environment=USER=git
Environment=HOME=/var/lib/forgejo

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now forgejo
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:3000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/forgejo ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_codeberg_release "forgejo" "forgejo/forgejo"; then
    msg_info "Stopping Service"
    systemctl stop forgejo
    msg_ok "Stopped Service"

    fetch_and_deploy_codeberg_release "forgejo" "forgejo/forgejo" "singlefile" "latest" "/opt/forgejo" "forgejo-*-linux-$(get_system_arch)"
    ln -sf /opt/forgejo/forgejo /usr/local/bin/forgejo

    if grep -q "GITEA_WORK_DIR" /etc/systemd/system/forgejo.service; then
      msg_info "Updating Service File"
      sed -i "s/GITEA_WORK_DIR/FORGEJO_WORK_DIR/g" /etc/systemd/system/forgejo.service
      systemctl daemon-reload
      msg_ok "Updated Service File"
    fi

    msg_info "Starting Service"
    systemctl start forgejo
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  else
    msg_ok "No update required. ${APP} is already at the latest version."
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
