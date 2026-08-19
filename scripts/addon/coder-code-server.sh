#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 tteck
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://coder.com/ | Github: https://github.com/coder/code-server

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Coder Code Server"

# Bundle-consumed configuration (var_addon_* is baked into update/uninstall
# bundles at install time — hooks may reference these directly)
var_addon_app="${var_addon_app:-coder-code-server}"
var_addon_pkg="${var_addon_pkg:-code-server}"
var_addon_gh_repo="${var_addon_gh_repo:-coder/code-server}"
var_addon_svc_user="${var_addon_svc_user:-${USER:-root}}"
var_addon_default_port="${var_addon_default_port:-8680}"

function install_script() {
  if [[ "$OS_FAMILY" != "debian" ]]; then
    msg_error "Unsupported OS: ${OS_TYPE} (Debian/Ubuntu only)"
    exit 1
  fi

  msg_info "Installing Dependencies"
  $STD apt update
  $STD apt install -y \
    curl \
    git
  msg_ok "Installed Dependencies"

  msg_info "Installing ${APP}"
  local config_path="${HOME}/.config/code-server/config.yaml"
  local preexisting_config=false
  if [[ -f "$config_path" ]]; then
    preexisting_config=true
  fi

  fetch_and_deploy_gh_release "$var_addon_app" "$var_addon_gh_repo" "binary" "latest" "/opt/coder-code-server" "code-server_*_$(get_system_arch).deb"
  mkdir -p "${HOME}/.config/code-server/"

  if [[ "$preexisting_config" == false ]]; then
    cat << EOF > "$config_path"
bind-addr: 0.0.0.0:${var_addon_default_port}
auth: none
password:
cert: false
EOF
  fi
  systemctl enable -q --now "code-server@${var_addon_svc_user}"
  systemctl restart "code-server@${var_addon_svc_user}"
  if ! systemctl is-active --quiet "code-server@${var_addon_svc_user}"; then
    msg_error "code-server service failed to start."
    exit 150
  fi
  msg_ok "Installed ${APP}"
}

function post_install_script() {
  echo ""
  msg_ok "${APP} installed successfully"
  echo -e "${INFO}${YW}Web UI:${CL} ${BGN}http://${LOCAL_IP}:${var_addon_default_port}${CL}"
  echo -e "${INFO}${YW}Config:${CL} ${HOME}/.config/code-server/config.yaml (auth: none by default)"
  echo -e "${INFO}${YW}Update:${CL} update-${APP_SLUG}   ${YW}Uninstall:${CL} uninstall-${APP_SLUG}"
}

function update_script() {
  if check_for_gh_release "$var_addon_app" "$var_addon_gh_repo"; then
    msg_info "Updating ${APP}"
    fetch_and_deploy_gh_release "$var_addon_app" "$var_addon_gh_repo" "binary" "latest" "/opt/coder-code-server" "code-server_*_$(get_system_arch).deb"
    systemctl restart "code-server@${var_addon_svc_user}"
    msg_ok "Updated successfully!"
  fi
  exit
}

function uninstall_script() {
  msg_info "Uninstalling ${APP}"
  systemctl disable --now "code-server@${var_addon_svc_user}" &> /dev/null || true
  $STD apt remove -y "$var_addon_pkg"
  rm -f "$HOME/.${var_addon_app}"
  msg_ok "${APP} has been uninstalled"
}

# Addons run inside arbitrary containers that may lack curl — ensure the
# transport before sourcing the framework (everything else is bootstrapped
# by install.func from this point on)
if ! command -v curl > /dev/null 2>&1; then
  if [[ -f /etc/alpine-release ]]; then
    apk update &> /dev/null && apk add --no-cache curl &> /dev/null
  else
    apt-get update &> /dev/null && apt-get install -y curl &> /dev/null
  fi
fi
command -v curl > /dev/null 2>&1 || {
  echo "FATAL: curl is required and could not be installed" >&2
  exit 1
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/addon_lxc")
