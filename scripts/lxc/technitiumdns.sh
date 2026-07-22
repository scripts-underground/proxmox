#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://technitium.com/dns/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Technitium DNS"
var_tags="${var_tags:-dns}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  setup_deb822_repo \
    "microsoft" \
    "https://packages.microsoft.com/keys/microsoft-2025.asc" \
    "https://packages.microsoft.com/debian/13/prod/" \
    "trixie" \
    "main"
  $STD apt install -y aspnetcore-runtime-10.0
  msg_ok "Installed Dependencies"

  msg_info "Installing Technitium DNS"
  RELEASE=$(curl -fsSL https://technitium.com/dns/ | grep -oP 'Version \K[\d.]+')
  fetch_and_deploy_from_url "https://download.technitium.com/dns/DnsServerPortable.tar.gz" /opt/technitium/dns
  echo "${RELEASE}" > ~/.technitium
  msg_ok "Installed Technitium DNS"

  msg_info "Creating Service"
  mkdir -p /etc/dns /var/log/technitium/dns
  sed -i '/^User=/d;/^Group=/d' /opt/technitium/dns/systemd.service
  cp /opt/technitium/dns/systemd.service /etc/systemd/system/technitium.service
  systemctl enable -q --now technitium
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:5380${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /etc/dns ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if [[ -f /etc/systemd/system/dns.service ]]; then
    mv /etc/systemd/system/dns.service /etc/systemd/system/technitium.service
    systemctl daemon-reload
    systemctl enable -q --now technitium
  fi
  if ! is_package_installed "aspnetcore-runtime-10.0"; then
    $STD apt remove -y aspnetcore-runtime-8.0 aspnetcore-runtime-9.0 2> /dev/null || true
    [ -f /etc/apt/sources.list.d/microsoft-prod.list ] && rm -f /etc/apt/sources.list.d/microsoft-prod.list
    [ -f /usr/share/keyrings/microsoft-prod.gpg ] && rm -f /usr/share/keyrings/microsoft-prod.gpg
    setup_deb822_repo \
      "microsoft" \
      "https://packages.microsoft.com/keys/microsoft-2025.asc" \
      "https://packages.microsoft.com/debian/13/prod/" \
      "trixie" \
      "main"
    $STD apt install -y aspnetcore-runtime-10.0
  fi

  RELEASE=$(curl -fsSL https://technitium.com/dns/ | grep -oP 'Version \K[\d.]+')
  if [[ ! -f ~/.technitium || ${RELEASE} != "$(cat ~/.technitium 2> /dev/null)" ]]; then
    fetch_and_deploy_from_url "https://download.technitium.com/dns/DnsServerPortable.tar.gz" /opt/technitium/dns
    echo "${RELEASE}" > ~/.technitium
    systemctl restart technitium
    msg_ok "Updated successfully!"
  else
    msg_ok "No update required. Technitium DNS is already at v${RELEASE}."
  fi
  exit
}

# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
