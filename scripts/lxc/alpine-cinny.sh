#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Tobias Salzmann (Eun)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/cinnyapp/cinny

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Alpine-Cinny"
var_tags="${var_tags:-alpine;matrix}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-256}"
var_disk="${var_disk:-1}"
var_os="${var_os:-alpine}"
var_version="${var_version:-3.23}"
var_nesting="${var_nesting:-0}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apk add --no-cache \
    jq \
    nginx
  msg_ok "Installed Dependencies"

  fetch_and_deploy_gh_release "cinny" "cinnyapp/cinny" "prebuild" "latest" "/opt/cinny" "cinny-*.tar.gz"

  msg_info "Configuring Cinny"
  cat << 'EOF' > /etc/nginx/http.d/default.conf
server {
  listen 8080;
  server_name localhost;

  location / {
        root /opt/cinny;

        rewrite ^/config.json$ /config.json break;
        rewrite ^/manifest.json$ /manifest.json break;

        rewrite ^/sw.js$ /sw.js break;
        rewrite ^/pdf.worker.min.js$ /pdf.worker.min.js break;

        rewrite ^/public/(.*)$ /public/$1 break;
        rewrite ^/assets/(.*)$ /assets/$1 break;

        rewrite ^(.+)$ /index.html break;
    }
}
EOF
  $STD rc-update add nginx default
  $STD rc-service nginx start
  msg_ok "Configured Cinny"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following IP:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
}

function update_script() {
  header_info

  if [[ ! -d /opt/cinny ]]; then
    msg_error "No ${APP} Installation Found!"
    return 1
  fi
  if [[ ! -f /opt/cinny/config.json ]]; then
    msg_error "Missing /opt/cinny/config.json; restore the saved configuration before updating."
    return 1
  fi

  if check_for_gh_release "cinny" "cinnyapp/cinny"; then
    # Read by the framework's checked replacement owner.
    # shellcheck disable=SC2034
    local CLEAN_INSTALL=1 CLEAN_INSTALL_KEEP="${CLEAN_INSTALL_KEEP:-} config.json"
    fetch_and_deploy_gh_release "cinny" "cinnyapp/cinny" "prebuild" "$CHECK_UPDATE_RELEASE" "/opt/cinny" "cinny-*.tar.gz"

    msg_info "Restarting nginx"
    $STD rc-service nginx restart
    msg_ok "Updated successfully!"
  else
    local status=$?
    [[ "$status" == 1 ]] || return "$status"
  fi
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc") --script-id "alpine-cinny" -- "$@"
