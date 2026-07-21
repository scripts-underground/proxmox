#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://openobserve.ai/ | Github: https://github.com/openobserve/openobserve

# shellcheck disable=SC2034
APP="OpenObserve"
var_tags="${var_tags:-monitoring}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-3}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y openssl
  msg_ok "Installed Dependencies"

  mkdir -p /opt/openobserve/data
  RELEASE=$(get_latest_github_release "openobserve/openobserve")
  msg_info "Downloading OpenObserve ${RELEASE}"
  tar zxf <(curl -fsSL "https://downloads.openobserve.ai/releases/openobserve/v${RELEASE}/openobserve-v${RELEASE}-linux-$(get_system_arch).tar.gz") -C /opt/openobserve
  ROOT_PASS="$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c9)Aa1!"

  cat << EOF > /opt/openobserve/data/.env
ZO_ROOT_USER_EMAIL = "admin@example.com"
ZO_ROOT_USER_PASSWORD = "${ROOT_PASS}"
ZO_DATA_DIR = "/opt/openobserve/data"
ZO_HTTP_PORT = "5080"
EOF
  echo "${RELEASE}" > /opt/${APP}_version.txt
  msg_ok "Downloaded OpenObserve ${RELEASE}"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/openobserve.service
[Unit]
Description=OpenObserve
After=network.target

[Service]
Type=simple
EnvironmentFile=/opt/openobserve/data/.env
ExecStart=/opt/openobserve/openobserve
ExecStop=killall -QUIT openobserve
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now openobserve
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:5080${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/openobserve/ ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "openobserve" "openobserve/openobserve"; then
    msg_info "Updating OpenObserve"
    systemctl stop openobserve
    RELEASE=$(get_latest_github_release "openobserve/openobserve")
    tar zxf <(curl -fsSL "https://downloads.openobserve.ai/releases/openobserve/v${RELEASE}/openobserve-v${RELEASE}-linux-$(get_system_arch).tar.gz") -C /opt/openobserve
    echo "${RELEASE}" > /opt/${APP}_version.txt
    systemctl start openobserve
    msg_ok "Updated OpenObserve"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
# Dynamic URL resolved at runtime
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
