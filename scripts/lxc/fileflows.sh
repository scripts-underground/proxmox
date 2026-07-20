#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: kkroboth
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://fileflows.com/

APP="FileFlows"
var_tags="${var_tags:-media;automation}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_gpu="${var_gpu:-yes}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y unzip
  msg_ok "Installed Dependencies"

  msg_info "Ensuring ASP.NET Core Runtime"
  if [[ "$(get_system_arch)" == "arm64" ]]; then
    if [[ ! -x /usr/lib/dotnet10/dotnet ]]; then
      curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
      $STD bash /tmp/dotnet-install.sh --channel 10.0 --runtime aspnetcore --install-dir /usr/lib/dotnet10
      ln -sf /usr/lib/dotnet10/dotnet /usr/bin/dotnet
      rm -f /tmp/dotnet-install.sh
    fi
  elif ! is_package_installed "aspnetcore-runtime-10.0"; then
    setup_deb822_repo \
      "microsoft" \
      "https://packages.microsoft.com/keys/microsoft-2025.asc" \
      "https://packages.microsoft.com/debian/13/prod/" \
      "trixie"
    $STD apt install -y aspnetcore-runtime-10.0
  fi
  msg_ok "Ensured ASP.NET Core Runtime"

  msg_info "Downloading FileFlows"
  fetch_and_deploy_from_url "https://fileflows.com/downloads/zip" "/opt/fileflows"
  msg_ok "Downloaded FileFlows"

  msg_info "Installing Service"
  cd /opt/fileflows/Server || exit
  $STD dotnet FileFlows.Server.dll --systemd install --root true
  systemctl enable -q --now fileflows
  msg_ok "Installed Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:19200${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/fileflows ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  local proceed=false

  if systemctl list-unit-files 'fileflows.service' --no-legend 2> /dev/null | grep -q '^fileflows\.service'; then
    tmp=$(mktemp)
    http_code=$(curl -sSL -X 'GET' "http://localhost:19200/api/status/update-available" -H 'accept: application/json' -o "$tmp" -w '%{http_code}' 2> /dev/null) || http_code="000"
    if [[ "$http_code" == "200" ]]; then
      update_available=$(jq -r '.UpdateAvailable // false' "$tmp" 2> /dev/null)
      rm -f "$tmp"
      if [[ "${update_available}" == "true" ]]; then
        proceed=true
      else
        msg_ok "No update required. ${APP} is already at latest version"
        exit
      fi
    else
      rm -f "$tmp"
      if [[ "$http_code" == "401" ]]; then
        msg_warn "Could not check for updates: API returned 401 (security may be enabled)."
      else
        msg_warn "Could not check for updates: API unreachable (HTTP ${http_code})."
      fi
      if [[ "${FORCE_UPDATE:-}" == "1" ]]; then
        proceed=true
      else
        read -r -p "${TAB3}Force update without version check? [y/N]: " CONFIRM
        if [[ "$CONFIRM" =~ ^([yY][eE][sS]|[yY])$ ]]; then
          proceed=true
        else
          msg_error "Update aborted."
          exit
        fi
      fi
    fi
  else
    proceed=true
  fi

  if [[ "$proceed" != "true" ]]; then
    exit
  fi

  msg_info "Stopping Service"
  systemctl --all stop 'fileflows*'
  msg_ok "Stopped Service"

  msg_info "Creating Backup"
  ls /opt/*.tar.gz &> /dev/null && rm -f /opt/*.tar.gz
  backup_filename="/opt/${APP}_backup_$(date +%F).tar.gz"
  tar -czf "$backup_filename" -C /opt/fileflows Data
  msg_ok "Backup Created"

  msg_info "Ensuring ASP.NET Core Runtime"
  if [[ "$(get_system_arch)" == "arm64" ]]; then
    if [[ ! -x /usr/lib/dotnet10/dotnet ]]; then
      curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
      $STD bash /tmp/dotnet-install.sh --channel 10.0 --runtime aspnetcore --install-dir /usr/lib/dotnet10
      ln -sf /usr/lib/dotnet10/dotnet /usr/bin/dotnet
      rm -f /tmp/dotnet-install.sh
    fi
  elif ! is_package_installed "aspnetcore-runtime-10.0"; then
    $STD apt remove -y aspnetcore-runtime-8.0 aspnetcore-runtime-9.0 2> /dev/null || true
    setup_deb822_repo \
      "microsoft" \
      "https://packages.microsoft.com/keys/microsoft-2025.asc" \
      "https://packages.microsoft.com/debian/13/prod/" \
      "trixie"
    $STD apt install -y aspnetcore-runtime-10.0
  fi
  msg_ok "Ensured ASP.NET Core Runtime"

  fetch_and_deploy_from_url "https://fileflows.com/downloads/zip" "/opt/fileflows"

  msg_info "Starting Service"
  systemctl --all start 'fileflows*'
  msg_ok "Started Service"
  msg_ok "Updated successfully!"

  exit
}

# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
