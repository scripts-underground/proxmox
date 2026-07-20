#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: madelyn (DysfunctionalProgramming)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://komga.org/

# shellcheck disable=SC2034
APP="Komga"
var_tags="${var_tags:-media;eBook;comic}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y libarchive-dev libjxl-dev libheif-dev libwebp-dev
  msg_ok "Installed Dependencies"

  JAVA_VERSION="23" setup_java

  kepubify_arch=$(uname -m)
  [[ "$kepubify_arch" == "x86_64" ]] && kepubify_arch="64bit"
  [[ "$kepubify_arch" == "aarch64" ]] && kepubify_arch="arm64"
  fetch_and_deploy_gh_release "kepubify" "pgaskin/kepubify" "singlefile" "latest" "/usr/bin" "kepubify-linux-${kepubify_arch}"

  USE_ORIGINAL_FILENAME="true" fetch_and_deploy_gh_release "komga" "gotson/komga" "singlefile" "latest" "/opt/komga" "komga*.jar"
  mv /opt/komga/komga-*.jar /opt/komga/komga.jar

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/komga.service
[Unit]
Description=Komga
After=syslog.target network.target

[Service]
Type=simple
WorkingDirectory=/opt/komga/
Environment=LD_LIBRARY_PATH=/usr/lib/$(uname -m)-linux-gnu
ExecStart=/usr/bin/java --enable-native-access=ALL-UNNAMED -jar -Xmx2g komga.jar
TimeoutStopSec=20
KillMode=process
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now komga
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:25600${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /opt/komga/komga.jar ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "komga" "gotson/komga"; then
    msg_info "Stopping Service"
    systemctl stop komga
    msg_ok "Stopped Service"

    rm -f /opt/komga/komga.jar
    USE_ORIGINAL_FILENAME="true" fetch_and_deploy_gh_release "komga" "gotson/komga" "singlefile" "latest" "/opt/komga" "komga*.jar"
    mv /opt/komga/komga-*.jar /opt/komga/komga.jar

    msg_info "Starting Service"
    systemctl start komga
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
