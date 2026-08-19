#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster) | Co-Author: MickLesk
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://filebrowser.org/ | Github: https://github.com/filebrowser/filebrowser

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="File Browser"

# Bundle-consumed configuration (var_addon_* is baked into update/uninstall
# bundles at install time — hooks may reference these directly)
var_addon_bin_path="${var_addon_bin_path:-/usr/local/bin/filebrowser}"
var_addon_db_dir="${var_addon_db_dir:-/usr/local/scripts-underground}"
var_addon_db_path="${var_addon_db_path:-${var_addon_db_dir}/filebrowser.db}"
var_addon_dist_path="${var_addon_dist_path:-/opt/filebrowser-dist}"
var_addon_default_port="${var_addon_default_port:-8080}"

function header_info() {
  clear
  cat << "EOF"
    _______ __     ____
   / ____(_) /__  / __ )_________ _      __________  _____
  / /_  / / / _ \/ __  / ___/ __ \ | /| / / ___/ _ \/ ___/
 / __/ / / /  __/ /_/ / /  / /_/ / |/ |/ (__  )  __/ /
/_/   /_/_/\___/_____/_/   \____/|__/|__/____/\___/_/
EOF
}

function install_script() {
  if [[ "$OS_FAMILY" != "debian" && "$OS_FAMILY" != "alpine" ]]; then
    msg_error "Unsupported OS: ${OS_TYPE} (Debian/Ubuntu and Alpine only)"
    exit 1
  fi

  echo ""
  read -erp "${TAB}Enter port number [${var_addon_default_port}]: " PORT || true
  PORT=${PORT:-$var_addon_default_port}

  msg_info "Installing ${APP} on ${OS_FAMILY^}"
  if [[ "$OS_FAMILY" == "debian" ]]; then
    $STD apt install -y tar curl
  else
    $STD apk add --no-cache tar curl
  fi
  fetch_and_deploy_gh_release "filebrowser" "filebrowser/filebrowser" "prebuild" "latest" "$var_addon_dist_path" "linux-$(get_system_arch uname)-filebrowser.tar.gz"
  install -m 755 "$var_addon_dist_path/filebrowser" "$var_addon_bin_path"
  rm -rf "$var_addon_dist_path"
  msg_ok "Installed ${APP}"

  msg_info "Creating ${APP} directory"
  mkdir -p "$var_addon_db_dir"
  chown root:root "$var_addon_db_dir"
  chmod 755 "$var_addon_db_dir"
  touch "$var_addon_db_path"
  chown root:root "$var_addon_db_path"
  chmod 644 "$var_addon_db_path"
  msg_ok "Directory created successfully"

  echo -n "${TAB}Would you like to use No Authentication? (y/N): "
  read -r auth_prompt || true
  if [[ "${auth_prompt,,}" =~ ^(y|yes)$ ]]; then
    msg_info "Configuring No Authentication"
    cd "$var_addon_db_dir" || exit
    $STD filebrowser config init -a '0.0.0.0' -p "$PORT" -d "$var_addon_db_path"
    $STD filebrowser config set -a '0.0.0.0' -p "$PORT" -d "$var_addon_db_path"
    $STD filebrowser config set --auth.method=noauth --database "$var_addon_db_path"
    if ! filebrowser users update 1 --perm.admin --database "$var_addon_db_path" &> /dev/null; then
      $STD filebrowser users add admin community-scripts.org --perm.admin --database "$var_addon_db_path"
    fi
    msg_ok "No Authentication configured"
  else
    msg_info "Setting up default authentication"
    cd "$var_addon_db_dir" || exit
    $STD filebrowser config init -a '0.0.0.0' -p "$PORT" -d "$var_addon_db_path"
    $STD filebrowser config set -a '0.0.0.0' -p "$PORT" -d "$var_addon_db_path"
    $STD filebrowser users add admin community-scripts.org --perm.admin --database "$var_addon_db_path"
    msg_ok "Default authentication configured (admin:community-scripts.org)"
  fi

  msg_info "Creating service"
  if [[ "$INIT_SYSTEM" == "openrc" ]]; then
    cat << EOF > /etc/init.d/filebrowser
#!/sbin/openrc-run

command="${var_addon_bin_path}"
command_args="-r / -d ${var_addon_db_path} -p ${PORT}"
command_background=true
pidfile="/var/run/filebrowser.pid"
directory="${var_addon_db_dir}"

depend() {
    need net
}
EOF
    chmod +x /etc/init.d/filebrowser
    $STD rc-update add filebrowser default
    $STD rc-service filebrowser start
  else
    cat << EOF > /etc/systemd/system/filebrowser.service
[Unit]
Description=Filebrowser
After=network-online.target

[Service]
User=root
WorkingDirectory=${var_addon_db_dir}
ExecStartPre=/bin/touch ${var_addon_db_path}
ExecStartPre=${var_addon_bin_path} config set -a "0.0.0.0" -p ${PORT} -d ${var_addon_db_path}
ExecStart=${var_addon_bin_path} -r / -d ${var_addon_db_path} -p ${PORT}
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    systemctl enable -q --now filebrowser
  fi
  msg_ok "Service created successfully"
}

function post_install_script() {
  echo ""
  msg_ok "${APP} is reachable at: ${BL}http://${LOCAL_IP}:${PORT}${CL}"
  echo -e "${INFO}${YW}Update:${CL} update-${APP_SLUG}   ${YW}Uninstall:${CL} uninstall-${APP_SLUG}"
}

function update_script() {
  if check_for_gh_release "filebrowser" "filebrowser/filebrowser"; then
    msg_info "Updating ${APP}"
    fetch_and_deploy_gh_release "filebrowser" "filebrowser/filebrowser" "prebuild" "latest" "$var_addon_dist_path" "linux-$(get_system_arch uname)-filebrowser.tar.gz"
    install -m 755 "$var_addon_dist_path/filebrowser" "$var_addon_bin_path"
    rm -rf "$var_addon_dist_path"
    msg_ok "Updated ${APP}"
  fi
  exit
}

function uninstall_script() {
  msg_info "Uninstalling ${APP}"
  if [[ "$INIT_SYSTEM" == "openrc" ]]; then
    rc-service filebrowser stop &> /dev/null || true
    rc-update del filebrowser &> /dev/null || true
    rm -f /etc/init.d/filebrowser
  else
    systemctl disable --now filebrowser.service &> /dev/null || true
    rm -f /etc/systemd/system/filebrowser.service
  fi
  rm -f "$var_addon_bin_path" "$var_addon_db_path" "$HOME/.filebrowser"
  msg_ok "${APP} has been uninstalled."
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
