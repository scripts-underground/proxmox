#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MrYadro
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://recyclarr.dev/wiki/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Recyclarr"
var_tags="${var_tags:-arr}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y git libicu-dev cron
  msg_ok "Installed Dependencies"

  fetch_and_deploy_gh_release "recyclarr" "recyclarr/recyclarr" "prebuild" "latest" "/usr/local/bin" "recyclarr-linux-$(get_system_arch).tar.xz"

  msg_info "Configuring Recyclarr"
  mkdir -p /root/.config/recyclarr/{configs,includes}
  $STD recyclarr config create
  msg_ok "Configured Recyclarr"

  msg_info "Setting up Daily Sync Cron"
  cat << EOF > /etc/cron.d/recyclarr
@daily root /usr/local/bin/recyclarr sync >> /root/.config/recyclarr/sync.log 2>&1
EOF
  chmod 644 /etc/cron.d/recyclarr
  msg_ok "Setup Daily Sync Cron"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Recyclarr is a CLI tool. SSH into the container to run:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}recyclarr sync${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /root/.config/recyclarr/recyclarr.yml ]] && [[ ! -d /root/.config/recyclarr/configs ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "recyclarr" "recyclarr/recyclarr"; then
    fetch_and_deploy_gh_release "recyclarr" "recyclarr/recyclarr" "prebuild" "latest" "/usr/local/bin" "recyclarr-linux-$(get_system_arch).tar.xz"

    RECYCLARR_DIR="/root/.config/recyclarr"
    mkdir -p "$RECYCLARR_DIR/includes"
    if [[ -d "$RECYCLARR_DIR/configs" ]]; then
      for item in "$RECYCLARR_DIR/configs"/*/; do
        [[ -d "$item" ]] || continue
        dir_name=$(basename "$item")
        if [[ "$dir_name" != "configs" ]] && [[ ! -d "$RECYCLARR_DIR/includes/$dir_name" ]]; then
          mv "$item" "$RECYCLARR_DIR/includes/"
        fi
      done
    fi

    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
