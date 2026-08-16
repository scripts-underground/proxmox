#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2026 scripts-underground.org
# Author: Alex Indigo (alexindigo)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/alexindigo/localsend-nas

# shellcheck disable=SC2034
APP="LocalSend NAS"
var_tags="${var_tags:-file-sharing;localsend}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_lxc_git_repo="${var_lxc_git_repo:-alexindigo/localsend-nas}"

function install_script() {
  msg_info "Installing LocalSend NAS"
  local SYS_ARCH
  SYS_ARCH=$(get_system_arch)
  fetch_and_deploy_gh_release "localsend-nas" "$var_lxc_git_repo" "prebuild" "latest" "/opt/localsend-nas" "localsend-nas_*_linux_${SYS_ARCH}.tar.gz"
  chmod +x /opt/localsend-nas/localsend-nas
  mkdir -p /data
  msg_ok "Installed LocalSend NAS"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/localsend-nas.service
[Unit]
Description=LocalSend NAS
After=network.target

[Service]
Type=simple
User=root
Environment=LOCALSEND_NAS_LISTEN=:80
Environment=LOCALSEND_NAS_DATA_DIR=/data
Environment=LOCALSEND_NAS_SHARES=files=/opt
ExecStart=/opt/localsend-nas/localsend-nas
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now localsend-nas
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access the web UI at:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
  echo -e "${INFO}${YW}LocalSend protocol listens on port 53317 (TCP+UDP, multicast discovery).${CL}"
  echo -e "${INFO}${YW}The CT's /opt directory is the default share root — mount your storage anywhere under /opt (pct mp, NFS, virtiofs) and it appears in the picker with no config changes.${CL}"
}

function update_script() {
  render_header
  check_container_storage
  check_container_resources

  if [[ ! -f /opt/localsend-nas/localsend-nas ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "localsend-nas" "$var_lxc_git_repo"; then
    msg_info "Updating ${APP}"
    systemctl stop localsend-nas
    local SYS_ARCH
    SYS_ARCH=$(get_system_arch)
    fetch_and_deploy_gh_release "localsend-nas" "$var_lxc_git_repo" "prebuild" "latest" "/opt/localsend-nas" "localsend-nas_*_linux_${SYS_ARCH}.tar.gz"
    chmod +x /opt/localsend-nas/localsend-nas
    systemctl start localsend-nas
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
