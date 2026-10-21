#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Johann3s-H (An!ma)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://forgejo.org/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Alpine-Forgejo"
var_tags="${var_tags:-alpine;git}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-8}"
var_os="${var_os:-alpine}"
var_version="${var_version:-3.23}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  local config_preexisting=no
  [[ ! -e /etc/forgejo/app.ini && ! -L /etc/forgejo/app.ini ]] || config_preexisting=yes
  msg_info "Installing Forgejo"
  $STD apk add --no-cache forgejo forgejo-openrc libcap-utils
  # The distro owns the forgejo account/home/init contract. Do not relocate it.
  # Only the new configuration gets the fresh HTTP default; existing values stay.
  if [[ "$config_preexisting" == no ]]; then
    local config_stage
    [[ -f /etc/forgejo/app.ini && ! -L /etc/forgejo/app.ini ]] || exit 65
    config_stage=$(mktemp /etc/forgejo/.app-ini.XXXXXX) || exit $?
    if awk '/^\[server\][[:space:]]*$/ {found++; print; print "HTTP_PORT = 80"; next} {print} END {if(found!=1)exit 65}' /etc/forgejo/app.ini > "$config_stage" &&
      chown forgejo:www-data "$config_stage" && chmod 0600 "$config_stage" && mv -f -- "$config_stage" /etc/forgejo/app.ini; then :; else
      local config_rc=$?
      rm -f -- "$config_stage"
      exit "$config_rc"
    fi
    chmod 0750 /var/lib/forgejo /etc/forgejo /var/log/forgejo
    $STD setcap cap_net_bind_service=+ep /usr/bin/forgejo
  fi
  msg_ok "Installed Forgejo"

  msg_info "Enabling Forgejo Service"
  $STD rc-update add forgejo default
  msg_ok "Enabled Forgejo Service"

  msg_info "Starting Forgejo"
  $STD rc-service forgejo start
  msg_ok "Started Forgejo"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
}

function update_script() {
  header_info
  if [[ ! -f /usr/bin/forgejo ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  local capabilities=''
  if command -v getcap > /dev/null 2>&1; then
    capabilities=$(getcap /usr/bin/forgejo) || exit $?
    capabilities="${capabilities#/usr/bin/forgejo }"
  fi
  msg_info "Updating $APP LXC"
  $STD apk -U upgrade
  # Package replacement drops file capabilities. Restore only the already
  # configured capabilities, preserving existing high-port/no-cap installations.
  if [[ -n "$capabilities" ]]; then
    $STD apk add --no-cache libcap-utils
    $STD setcap "$capabilities" /usr/bin/forgejo
  fi
  msg_ok "Updated $APP LXC"

  msg_info "Restarting Forgejo"
  $STD rc-service forgejo restart
  msg_ok "Restarted Forgejo"
  msg_ok "Updated successfully!"
  exit 0
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
