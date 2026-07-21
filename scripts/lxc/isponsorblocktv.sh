#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Matthew Stern (sternma) | MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/dmunozv04/iSponsorBlockTV

# shellcheck disable=SC2034
APP="iSponsorBlockTV"
var_tags="${var_tags:-media;automation}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y python3 python3-pip
  msg_ok "Installed Dependencies"

  msg_info "Installing iSponsorBlockTV"
  if [[ "$(get_system_arch)" == "arm64" ]]; then
    ISBTV_BINARY="iSponsorBlockTV-aarch64-linux"
  elif grep -q ' avx ' /proc/cpuinfo 2> /dev/null &&
    grep -q ' avx2 ' /proc/cpuinfo 2> /dev/null &&
    grep -q ' movbe ' /proc/cpuinfo 2> /dev/null; then
    ISBTV_BINARY="iSponsorBlockTV-x86_64-linux"
  else
    ISBTV_BINARY="iSponsorBlockTV-x86_64-linux-v1"
  fi
  fetch_and_deploy_gh_release "isponsorblocktv" "dmunozv04/iSponsorBlockTV" "singlefile" "latest" "/opt/isponsorblocktv" "${ISBTV_BINARY}"
  chmod +x "/opt/isponsorblocktv/${ISBTV_BINARY}"
  ln -sf "/opt/isponsorblocktv/${ISBTV_BINARY}" /opt/isponsorblocktv/isponsorblocktv
  install -d /var/lib/isponsorblocktv
  cat << 'WRAPPER' > /usr/local/bin/iSponsorBlockTV
#!/usr/bin/env bash
export iSPBTV_data_dir=/var/lib/isponsorblocktv
exec /opt/isponsorblocktv/isponsorblocktv "$@"
WRAPPER
  chmod +x /usr/local/bin/iSponsorBlockTV
  ln -sf /usr/local/bin/iSponsorBlockTV /usr/bin/iSponsorBlockTV
  msg_ok "Installed iSponsorBlockTV"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/isponsorblocktv.service
[Unit]
Description=iSponsorBlockTV
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=root
Group=root
Environment=iSPBTV_data_dir=/var/lib/isponsorblocktv
ExecStart=/opt/isponsorblocktv/isponsorblocktv
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now isponsorblocktv
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Run the setup wizard inside the container with:${CL}"
  echo -e "${GATEWAY}${BGN}iSponsorBlockTV setup${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/isponsorblocktv ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "isponsorblocktv" "dmunozv04/iSponsorBlockTV"; then
    msg_info "Stopping Service"
    systemctl stop isponsorblocktv
    msg_ok "Stopped Service"

    if [[ "$(get_system_arch)" == "arm64" ]]; then
      ISBTV_BINARY="iSponsorBlockTV-aarch64-linux"
    elif grep -q ' avx ' /proc/cpuinfo 2> /dev/null &&
      grep -q ' avx2 ' /proc/cpuinfo 2> /dev/null &&
      grep -q ' movbe ' /proc/cpuinfo 2> /dev/null; then
      ISBTV_BINARY="iSponsorBlockTV-x86_64-linux"
    else
      ISBTV_BINARY="iSponsorBlockTV-x86_64-linux-v1"
    fi
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "isponsorblocktv" "dmunozv04/iSponsorBlockTV" "singlefile" "latest" "/opt/isponsorblocktv" "${ISBTV_BINARY}"
    chmod +x "/opt/isponsorblocktv/${ISBTV_BINARY}"
    ln -sf "/opt/isponsorblocktv/${ISBTV_BINARY}" /opt/isponsorblocktv/isponsorblocktv

    msg_info "Starting Service"
    systemctl start isponsorblocktv
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
