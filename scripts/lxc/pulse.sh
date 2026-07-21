#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: rcourtman (rcourtman) | vhsdream (vhsdream)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/rcourtman/Pulse

APP="Pulse"
var_tags="${var_tags:-monitoring;proxmox}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    diffutils \
    polkitd
  msg_ok "Installed Dependencies"

  msg_info "Creating User"
  useradd -r -m -d /opt/pulse-home -s /usr/sbin/nologin pulse
  msg_ok "Created User"

  mkdir -p /etc/pulse
  fetch_and_deploy_gh_release "pulse" "rcourtman/Pulse" "prebuild" "latest" "/opt/pulse" "pulse-v*-linux-$(get_system_arch).tar.gz"
  ln -sf /opt/pulse/bin/pulse /usr/local/bin/pulse
  chown -R pulse:pulse /etc/pulse /opt/pulse
  msg_ok "Installed Pulse"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/pulse.service
[Unit]
Description=Pulse Monitoring Server
After=network.target

[Service]
Type=simple
User=pulse
Group=pulse
WorkingDirectory=/opt/pulse
ExecStart=/opt/pulse/bin/pulse
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Environment="PULSE_DATA_DIR=/etc/pulse"

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now pulse
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:7655${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/pulse ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "pulse" "rcourtman/Pulse"; then
    SERVICE_PATH="/etc/systemd/system"
    msg_info "Stopping Services"
    systemctl stop pulse*.service
    msg_ok "Stopped Services"

    if [[ -f /opt/pulse/pulse ]]; then
      rm -f /opt/pulse/pulse
    fi

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "pulse" "rcourtman/Pulse" "prebuild" "latest" "/opt/pulse" "pulse-v*-linux-$(get_system_arch).tar.gz"
    ln -sf /opt/pulse/bin/pulse /usr/local/bin/pulse
    mkdir -p /etc/pulse
    chown pulse:pulse /etc/pulse
    chown -R pulse:pulse /opt/pulse
    chmod 700 /etc/pulse
    if [[ -f "$SERVICE_PATH"/pulse-backend.service ]]; then
      mv "$SERVICE_PATH"/pulse-backend.service "$SERVICE_PATH"/pulse.service
    fi
    sed -i -e 's|pulse/pulse|pulse/bin/pulse|' \
      -e 's/^Environment="API.*$//' "$SERVICE_PATH"/pulse.service
    systemctl daemon-reload
    if grep -q 'pulse-home:/bin/bash' /etc/passwd; then
      usermod -s /usr/sbin/nologin pulse
    fi

    msg_info "Starting Services"
    systemctl start pulse
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
