#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://about.gitea.com/ | GitHub: https://github.com/go-gitea/gitea

# shellcheck disable=SC2034
APP="Gitea"
var_tags="${var_tags:-git;code;devops}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y git sqlite3
  msg_ok "Installed Dependencies"

  fetch_and_deploy_gh_release "gitea" "go-gitea/gitea" "singlefile" "latest" "/usr/local/bin" "gitea-*-linux-$(get_system_arch)"

  msg_info "Configuring Gitea"
  chmod +x /usr/local/bin/gitea
  $STD adduser --system --group --disabled-password --shell /bin/bash --home /etc/gitea gitea
  mkdir -p /var/lib/gitea/{custom,data,log}
  chown -R gitea:gitea /var/lib/gitea/
  chmod -R 750 /var/lib/gitea/
  chown root:gitea /etc/gitea
  chmod 770 /etc/gitea
  sudo -u gitea ln -s /var/lib/gitea/data/.ssh/ /etc/gitea/.ssh
  msg_ok "Configured Gitea"

  msg_info "Creating Service"
  cat << 'EOF' > /etc/systemd/system/gitea.service
[Unit]
Description=Gitea (Git with a cup of tea)
After=syslog.target
After=network.target

[Service]
RestartSec=2s
Type=simple
User=gitea
Group=gitea
WorkingDirectory=/var/lib/gitea
RuntimeDirectory=gitea
ExecStart=/usr/local/bin/gitea web --config /etc/gitea/app.ini
Restart=always
Environment=USER=gitea HOME=/var/lib/gitea/data GITEA_WORK_DIR=/var/lib/gitea

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now gitea
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
  if [[ ! -f /usr/local/bin/gitea ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "gitea" "go-gitea/gitea"; then
    msg_info "Stopping Service"
    systemctl stop gitea
    msg_ok "Stopped Service"

    fetch_and_deploy_gh_release "gitea" "go-gitea/gitea" "singlefile" "latest" "/usr/local/bin" "gitea-*-linux-$(get_system_arch)"
    chmod +x /usr/local/bin/gitea

    msg_info "Starting Service"
    systemctl start gitea
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  else
    msg_ok "No update required. ${APP} is already at the latest version."
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
