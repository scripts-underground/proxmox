#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2026 scripts-underground.org
# Author: Alex Indigo (alexindigo)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/kopia/kopia

# shellcheck disable=SC2034
APP="Kopia"
var_tags="${var_tags:-backup}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_lxc_git_repo="${var_lxc_git_repo:-kopia/kopia}"

function install_script() {
  local SYS_ARCH
  SYS_ARCH=$(get_system_arch)
  fetch_and_deploy_gh_release "kopia" "$var_lxc_git_repo" "binary" "latest" "/opt/kopia" "kopia-*_linux_${SYS_ARCH}.tar.gz"
  chmod +x /opt/kopia/kopia
  mkdir -p /opt/kopia/repository /opt/kopia/config

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/kopia.service
[Unit]
Description=Kopia Repository Server
After=network.target

[Service]
Type=simple
User=root
Environment=KOPIA_PASSWORD=
ExecStart=/opt/kopia/kopia server start --address 0.0.0.0:80 --server-username kopia --server-password kopia --tls-generate-cert --without-password
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now kopia
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access the web UI at:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
  echo -e "${INFO}${YW}Default login: kopia / kopia — change after first login.${CL}"
}

function update_script() {
  render_header
  check_container_storage
  check_container_resources

  if [[ ! -f /opt/kopia/kopia ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "kopia" "$var_lxc_git_repo"; then
    systemctl stop kopia
    local SYS_ARCH
    SYS_ARCH=$(get_system_arch)
    fetch_and_deploy_gh_release "kopia" "$var_lxc_git_repo" "binary" "latest" "/opt/kopia" "kopia-*_linux_${SYS_ARCH}.tar.gz"
    chmod +x /opt/kopia/kopia
    systemctl start kopia
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
