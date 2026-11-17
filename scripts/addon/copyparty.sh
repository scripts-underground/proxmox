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
  terminal_clear
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
  local source_url="${var_addon_src_url:-https://github.com/9001/copyparty/releases/latest/download/copyparty-sfx.py}"
  local managed_release=0 update_status=0 stage bin_dir marker_stage=""
  local was_running=0 service_touched=0 retain_stage=0 old_executable='' old_marker='' current=''
  # Only verified previous bytes/links, modes and owners admit failure recovery.
  function copyparty_file_state() {
    if [[ ! -e "$1" && ! -L "$1" ]]; then
      printf 'absent\n'
      return
    fi
    stat -c '%f:%u:%g' -- "$1" || return $?
    if [[ -L "$1" ]]; then readlink -- "$1"; else sha256sum < "$1"; fi
  }

  # The stock source is release-managed. A saved custom URL remains the
  # operator's source; GitHub cannot describe or certify its version.
  if [[ "$source_url" == https://github.com/9001/copyparty/releases/latest/download/copyparty-sfx.py ]]; then
    if check_for_gh_release "copyparty-sfx.py" "9001/copyparty"; then
      managed_release=1
    else
      local release_status=$?
      [[ "$release_status" == 1 ]] || return "$release_status"
    fi
    [[ "$managed_release" == 1 ]] || return 0
    msg_info "Updating ${APP} to ${CHECK_UPDATE_RELEASE}"
  else
    msg_info "Updating ${APP} from custom source; version is operator-managed"
  fi

  # Prepare the complete executable, owner and mode beside its final path.
  # Neither a partial custom download nor a failed preparation touches the old
  # executable. Private HOME keeps managed-release metadata staged as well.
  bin_dir=$(dirname -- "$var_addon_bin_path") || return $?
  stage=$(mktemp -d "$bin_dir/.copyparty-update.XXXXXXXX") || return $?
  if [[ "$managed_release" == 1 ]]; then
    HOME="$stage" fetch_and_deploy_gh_release "copyparty-sfx.py" "9001/copyparty" "singlefile" "$CHECK_UPDATE_RELEASE" "$stage" "copyparty-sfx.py" || update_status=$?
  else
    curl_download "$stage/copyparty-sfx.py" "$source_url" || update_status=$?
  fi
  if [[ "$update_status" == 0 ]]; then
    [[ -f "$stage/copyparty-sfx.py" && -s "$stage/copyparty-sfx.py" ]] || update_status=251
  fi
  if [[ "$update_status" == 0 ]]; then chmod 0755 "$stage/copyparty-sfx.py" || update_status=$?; fi
  if [[ "$update_status" == 0 ]]; then chown "$var_addon_svc_user:$var_addon_svc_group" "$stage/copyparty-sfx.py" || update_status=$?; fi
  if [[ "$update_status" == 0 && "$managed_release" == 1 ]]; then
    marker_stage=$(mktemp "$HOME/.copyparty-marker.XXXXXXXX") || update_status=$?
    if [[ "$update_status" == 0 ]]; then cp -- "$stage/.copyparty-sfx.py" "$marker_stage" || update_status=$?; fi
  fi
  if [[ "$update_status" == 0 && "$managed_release" == 0 ]]; then
    # Custom bytes must not retain a managed-release claim. Invalidate before
    # publication so even an invalidation failure leaves the old binary intact;
    # returning to the stock source will perform a fresh release selection.
    rm -f -- "$HOME/.copyparty-sfx.py" || update_status=$?
  fi

  if [[ "$update_status" == 0 ]]; then
    old_executable=$(copyparty_file_state "$var_addon_bin_path") || update_status=$?
    if [[ "$update_status" == 0 ]]; then cp -a -- "$var_addon_bin_path" "$stage/previous-executable" || update_status=$?; fi
    if [[ "$update_status" == 0 && "$managed_release" == 1 ]]; then
      old_marker=$(copyparty_file_state "$HOME/.copyparty-sfx.py") || update_status=$?
      if [[ "$update_status" == 0 && "$old_marker" != absent ]]; then cp -a -- "$HOME/.copyparty-sfx.py" "$stage/previous-marker" || update_status=$?; fi
    fi
  fi

  if [[ "$update_status" == 0 ]]; then
    if [[ "$INIT_SYSTEM" == openrc ]]; then
      if rc-service copyparty status > /dev/null 2>&1; then was_running=1; fi
    elif systemctl is-active --quiet copyparty; then was_running=1; fi
    msg_info "Stopping Service"
    service_touched=1
    if [[ "$INIT_SYSTEM" == "openrc" ]]; then
      rc-service copyparty stop &> /dev/null || update_status=$?
    else
      systemctl stop copyparty &> /dev/null || update_status=$?
    fi
  fi
  if [[ "$update_status" == 0 ]]; then
    msg_ok "Stopped Service"
    mv -fT -- "$stage/copyparty-sfx.py" "$var_addon_bin_path" || update_status=$?
  fi
  if [[ "$update_status" == 0 && "$managed_release" == 1 ]]; then
    mv -fT -- "$marker_stage" "$HOME/.copyparty-sfx.py" || update_status=$?
  fi
  if [[ "$update_status" != 0 && "$service_touched" == 1 ]]; then
    current=$(copyparty_file_state "$var_addon_bin_path") || current=unverified
    if [[ "$current" != "$old_executable" ]]; then
      mv -fT -- "$stage/previous-executable" "$var_addon_bin_path" || msg_warn "Previous executable retained at $stage/previous-executable"
    fi
    if [[ "$managed_release" == 1 ]]; then
      current=$(copyparty_file_state "$HOME/.copyparty-sfx.py") || current=unverified
      if [[ "$current" != "$old_marker" ]]; then
        if [[ "$old_marker" == absent ]]; then
          rm -f -- "$HOME/.copyparty-sfx.py" || msg_warn "Unable to remove unpublished release marker"
        else
          mv -fT -- "$stage/previous-marker" "$HOME/.copyparty-sfx.py" || msg_warn "Previous marker retained at $stage/previous-marker"
        fi
      fi
    fi
    current=$(copyparty_file_state "$var_addon_bin_path") || current=unverified
    if [[ "$current" != "$old_executable" ]]; then retain_stage=1; fi
    if [[ "$managed_release" == 1 ]]; then
      current=$(copyparty_file_state "$HOME/.copyparty-sfx.py") || current=unverified
      if [[ "$current" != "$old_marker" ]]; then retain_stage=1; fi
    fi
    if [[ "$retain_stage" == 0 && "$was_running" == 1 ]]; then
      if [[ "$INIT_SYSTEM" == openrc ]]; then
        rc-service copyparty start || msg_warn "Unable to restart previous Copyparty service"
      else
        systemctl start copyparty || msg_warn "Unable to restart previous Copyparty service"
      fi
    fi
  fi
  [[ -z "$marker_stage" ]] || rm -f -- "$marker_stage" || true
  if [[ "$retain_stage" == 0 ]]; then rm -rf -- "$stage" || true; else msg_warn "Unverified Copyparty recovery retained at $stage; service stays stopped"; fi
  [[ "$update_status" == 0 ]] || return "$update_status"
  msg_ok "Updated ${APP}"

  msg_info "Starting Service"
  if [[ "$was_running" == 1 ]]; then
    if [[ "$INIT_SYSTEM" == "openrc" ]]; then
      rc-service copyparty start
    else
      systemctl start copyparty
    fi
    msg_ok "Started Service"
  fi
  msg_ok "Updated successfully!"
  exit
}

function uninstall_script() {
  msg_info "Uninstalling ${APP}"
  svc_prepare_uninstall copyparty
  if [[ "$INIT_SYSTEM" == "openrc" ]]; then
    rm -f /etc/init.d/copyparty
  else
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
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/addon_lxc") --script-id copyparty -- "$@"
