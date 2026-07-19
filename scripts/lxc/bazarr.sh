#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.bazarr.media/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Bazarr"
var_tags="${var_tags:-arr}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  PYTHON_VERSION="3.12" setup_uv
  fetch_and_deploy_gh_release "bazarr" "morpheus65535/bazarr" "prebuild" "latest" "/opt/bazarr" "bazarr.zip"

  msg_info "Installing Bazarr"
  mkdir -p /var/lib/bazarr/
  chmod 775 /opt/bazarr /var/lib/bazarr/
  sed -i.bak 's/--only-binary=Pillow//g' /opt/bazarr/requirements.txt
  $STD uv venv --clear /opt/bazarr/venv --python 3.12
  $STD uv pip install -r /opt/bazarr/requirements.txt --python /opt/bazarr/venv/bin/python3
  msg_ok "Installed Bazarr"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/bazarr.service
[Unit]
Description=Bazarr Daemon
After=syslog.target network.target

[Service]
WorkingDirectory=/opt/bazarr/
UMask=0002
Restart=on-failure
RestartSec=5
Type=simple
ExecStart=/opt/bazarr/venv/bin/python3 /opt/bazarr/bazarr.py
KillSignal=SIGINT
TimeoutStopSec=20
SyslogIdentifier=bazarr

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now bazarr
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:6767${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /var/lib/bazarr/ ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "bazarr" "morpheus65535/bazarr"; then
    msg_info "Stopping Service"
    systemctl stop bazarr
    msg_ok "Stopped Service"

    PYTHON_VERSION="3.12" setup_uv
    fetch_and_deploy_gh_release "bazarr" "morpheus65535/bazarr" "prebuild" "latest" "/opt/bazarr" "bazarr.zip"

    msg_info "Setup Bazarr"
    mkdir -p /var/lib/bazarr/
    chmod 775 /opt/bazarr /var/lib/bazarr/
    if [[ ! -d /opt/bazarr/venv/ ]]; then
      $STD uv venv --clear /opt/bazarr/venv --python 3.12
    fi
    if [[ -f /etc/systemd/system/bazarr.service ]] && grep -q "ExecStart=/usr/bin/python3" /etc/systemd/system/bazarr.service; then
      sed -i "s|ExecStart=/usr/bin/python3 /opt/bazarr/bazarr.py|ExecStart=/opt/bazarr/venv/bin/python3 /opt/bazarr/bazarr.py|g" /etc/systemd/system/bazarr.service
      systemctl daemon-reload
    fi
    sed -i.bak 's/--only-binary=Pillow//g' /opt/bazarr/requirements.txt
    $STD uv pip install -r /opt/bazarr/requirements.txt --python /opt/bazarr/venv/bin/python3
    msg_ok "Setup Bazarr"

    msg_info "Starting Service"
    systemctl start bazarr
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
