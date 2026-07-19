#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.commafeed.com/#/welcome | Github: https://github.com/Athou/commafeed

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="CommaFeed"
var_tags="${var_tags:-rss-reader}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y rsync
  msg_ok "Installed Dependencies"

  JAVA_VERSION="25" setup_java
  fetch_and_deploy_gh_release "commafeed" "Athou/commafeed" "prebuild" "latest" "/opt/commafeed" "commafeed-*-h2-jvm.zip"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/commafeed.service
[Unit]
Description=CommaFeed Service
After=network.target

[Service]
ExecStart=java -Xminf0.05 -Xmaxf0.1 -jar quarkus-run.jar
WorkingDirectory=/opt/commafeed/
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now commafeed
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8082${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/commafeed ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  JAVA_VERSION="25" setup_java
  if check_for_gh_release "commafeed" "Athou/commafeed"; then
    msg_info "Stopping Service"
    systemctl stop commafeed
    msg_ok "Stopped Service"

    ensure_dependencies rsync
    create_backup /opt/commafeed/data

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "commafeed" "Athou/commafeed" "prebuild" "latest" "/opt/commafeed" "commafeed-*-h2-jvm.zip"

    restore_backup

    msg_info "Starting Service"
    systemctl start commafeed
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
