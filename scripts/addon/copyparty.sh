#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/9001/copyparty

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="CopyParty"

# Bundle-consumed configuration (var_addon_* is baked into update/uninstall
# bundles at install time — hooks may reference these directly)
var_addon_bin_path="${var_addon_bin_path:-/usr/local/bin/copyparty-sfx.py}"
var_addon_conf_path="${var_addon_conf_path:-/etc/copyparty.conf}"
var_addon_log_path="${var_addon_log_path:-/var/log/copyparty}"
var_addon_data_path="${var_addon_data_path:-/var/lib/copyparty}"
var_addon_src_url="${var_addon_src_url:-https://github.com/9001/copyparty/releases/latest/download/copyparty-sfx.py}"
var_addon_svc_user="${var_addon_svc_user:-copyparty}"
var_addon_svc_group="${var_addon_svc_group:-copyparty}"
var_addon_default_port="${var_addon_default_port:-3923}"

function header_info() {
  clear
  cat << "EOF"
   ______                  ____             __
  / ____/___  ____  __  __/ __ \____ ______/ /___  __
 / /   / __ \/ __ \/ / / / /_/ / __ `/ ___/ __/ / / /
/ /___/ /_/ / /_/ / /_/ / ____/ /_/ / /  / /_/ /_/ /
\____/\____/ .___/\__, /_/    \__,_/_/   \__/\__, /
          /_/    /____/                     /____/
EOF
}

function install_script() {
  if [[ "$OS_FAMILY" != "debian" && "$OS_FAMILY" != "alpine" ]]; then
    msg_error "Unsupported OS: ${OS_TYPE} (Debian/Ubuntu and Alpine only)"
    exit 1
  fi

  echo ""
  read -erp "${TAB}Enter port for ${APP} [${var_addon_default_port}]: " CPP_PORT || true
  CPP_PORT=${CPP_PORT:-$var_addon_default_port}

  read -erp "${TAB}Set data directory [${var_addon_data_path}]: " CPP_DATA_PATH || true
  CPP_DATA_PATH=${CPP_DATA_PATH:-$var_addon_data_path}

  CPP_ADMIN_USER=""
  CPP_ADMIN_PASS=""
  echo -n "${TAB}Enable authentication? (Y/n): "
  read -r CPP_AUTH || true
  if [[ ! "${CPP_AUTH,,}" =~ ^(n|no)$ ]]; then
    read -erp "${TAB}Set admin username [admin]: " CPP_ADMIN_USER || true
    CPP_ADMIN_USER=${CPP_ADMIN_USER:-admin}
    read -rsp "${TAB}Set admin password [community-scripts.org]: " CPP_ADMIN_PASS || true
    echo ""
    CPP_ADMIN_PASS=${CPP_ADMIN_PASS:-community-scripts.org}
    msg_ok "Configured with admin user: ${CPP_ADMIN_USER}"
  else
    msg_ok "Configured without authentication"
  fi

  msg_info "Installing Dependencies"
  if [[ "$OS_FAMILY" == "debian" ]]; then
    $STD apt install -y python3 python3-pil ffmpeg curl
  else
    $STD apk add --no-cache python3 py3-pillow ffmpeg curl
  fi
  msg_ok "Installed Dependencies (with thumbnail support)"

  msg_info "Creating ${var_addon_svc_user} user and directories"
  if ! id "$var_addon_svc_user" &> /dev/null; then
    if [[ "$OS_FAMILY" == "debian" ]]; then
      useradd -r -s /sbin/nologin -d "$var_addon_data_path" "$var_addon_svc_user"
    else
      addgroup -S "$var_addon_svc_group" 2> /dev/null || true
      adduser -S -D -H -G "$var_addon_svc_group" -h "$var_addon_data_path" -s /sbin/nologin "$var_addon_svc_user" 2> /dev/null || true
    fi
  fi
  mkdir -p "$var_addon_data_path" "$var_addon_log_path" "$CPP_DATA_PATH"
  chown -R "$var_addon_svc_user:$var_addon_svc_group" "$var_addon_data_path" "$var_addon_log_path" "$CPP_DATA_PATH"
  chmod 755 "$var_addon_data_path" "$var_addon_log_path"
  msg_ok "User/Group/Dirs ready"

  msg_info "Downloading ${APP}"
  curl -fsSL "$var_addon_src_url" -o "$var_addon_bin_path"
  chmod +x "$var_addon_bin_path"
  chown "$var_addon_svc_user:$var_addon_svc_group" "$var_addon_bin_path"
  msg_ok "Downloaded to ${var_addon_bin_path}"

  msg_info "Creating configuration"
  cat << EOF > "$var_addon_conf_path"
[global]
  p: ${CPP_PORT}
  ansi
  e2dsa
  e2ts
  theme: 2
  grid
  no-robots
  force-js
  lo: ${var_addon_log_path}/cpp-%Y-%m%d.txt.xz

EOF

  if [[ -n "$CPP_ADMIN_USER" && -n "$CPP_ADMIN_PASS" ]]; then
    cat << EOF >> "$var_addon_conf_path"
[accounts]
  ${CPP_ADMIN_USER}: ${CPP_ADMIN_PASS}

EOF
  fi

  cat << EOF >> "$var_addon_conf_path"
[/]
  ${CPP_DATA_PATH}
  accs:
EOF

  if [[ -n "$CPP_ADMIN_USER" ]]; then
    cat << EOF >> "$var_addon_conf_path"
    rw: *
    rwmda: ${CPP_ADMIN_USER}
EOF
  else
    cat << EOF >> "$var_addon_conf_path"
    rw: *
EOF
  fi

  chmod 640 "$var_addon_conf_path"
  chown "$var_addon_svc_user:$var_addon_svc_group" "$var_addon_conf_path"
  msg_ok "Created configuration"

  msg_info "Creating Service"
  if [[ "$INIT_SYSTEM" == "openrc" ]]; then
    cat << 'EOF' > /etc/init.d/copyparty
#!/sbin/openrc-run

name="copyparty"
description="CopyParty file server"

command="$(command -v python3)"
command_args="/usr/local/bin/copyparty-sfx.py -c /etc/copyparty.conf"
command_background=true
directory="/var/lib/copyparty"
pidfile="/run/copyparty.pid"
output_log="/var/log/copyparty/copyparty.log"
error_log="/var/log/copyparty/copyparty.err"

depend() {
    need net
}
EOF
    chmod +x /etc/init.d/copyparty
    $STD rc-update add copyparty default
    $STD rc-service copyparty start
  else
    cat << EOF > /etc/systemd/system/copyparty.service
[Unit]
Description=CopyParty file server
After=network.target

[Service]
User=${var_addon_svc_user}
Group=${var_addon_svc_group}
WorkingDirectory=${CPP_DATA_PATH}
ExecStart=/usr/bin/python3 ${var_addon_bin_path} -c ${var_addon_conf_path}
Restart=always
StandardOutput=append:${var_addon_log_path}/copyparty.log
StandardError=append:${var_addon_log_path}/copyparty.err

[Install]
WantedBy=multi-user.target
EOF
    systemctl enable -q --now copyparty
  fi
  msg_ok "Created and started Service"
}

function post_install_script() {
  echo ""
  msg_ok "${APP} installed successfully"
  echo -e "${INFO}${YW}Web UI:${CL} ${BGN}http://${LOCAL_IP}:${CPP_PORT}${CL}"
  echo -e "${INFO}${YW}Storage:${CL} ${CPP_DATA_PATH}"
  echo -e "${INFO}${YW}Config:${CL} ${var_addon_conf_path}"
  if [[ -n "$CPP_ADMIN_USER" ]]; then
    echo -e "${INFO}${YW}Login:${CL} ${GN}${CPP_ADMIN_USER}${CL} / ${GN}${CPP_ADMIN_PASS}${CL}"
  fi
  echo -e "${INFO}${YW}Update:${CL} update-${APP_SLUG}   ${YW}Uninstall:${CL} uninstall-${APP_SLUG}"
}

function update_script() {
  if check_for_gh_release "copyparty-sfx.py" "9001/copyparty"; then
    msg_info "Stopping Service"
    if [[ "$INIT_SYSTEM" == "openrc" ]]; then
      rc-service copyparty stop &> /dev/null || true
    else
      systemctl stop copyparty &> /dev/null || true
    fi
    msg_ok "Stopped Service"

    msg_info "Updating ${APP}"
    curl -fsSL "$var_addon_src_url" -o "$var_addon_bin_path"
    chmod +x "$var_addon_bin_path"
    chown "$var_addon_svc_user:$var_addon_svc_group" "$var_addon_bin_path"
    msg_ok "Updated ${APP}"

    msg_info "Starting Service"
    if [[ "$INIT_SYSTEM" == "openrc" ]]; then
      rc-service copyparty start
    else
      systemctl start copyparty
    fi
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

function uninstall_script() {
  msg_info "Uninstalling ${APP}"
  if [[ "$INIT_SYSTEM" == "openrc" ]]; then
    rc-service copyparty stop &> /dev/null || true
    rc-update del copyparty &> /dev/null || true
    rm -f /etc/init.d/copyparty
  else
    systemctl disable --now copyparty &> /dev/null || true
    rm -f /etc/systemd/system/copyparty.service
  fi
  rm -f "$var_addon_bin_path" "$var_addon_conf_path"
  rm -rf "$var_addon_data_path" "$var_addon_log_path"
  userdel "$var_addon_svc_user" 2> /dev/null || true
  groupdel "$var_addon_svc_group" 2> /dev/null || true
  rm -f "$HOME/.copyparty"
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
