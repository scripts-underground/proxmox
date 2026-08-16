#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/gtsteffaniak/filebrowser

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="FileBrowser Quantum"

# Bundle-consumed configuration (var_addon_* is baked into update/uninstall
# bundles at install time — hooks may reference these directly)
var_addon_bin_path="${var_addon_bin_path:-/usr/local/bin/filebrowser}"
var_addon_conf_dir="${var_addon_conf_dir:-/usr/local/community-scripts}"
var_addon_conf_path="${var_addon_conf_path:-${var_addon_conf_dir}/fq-config.yaml}"
var_addon_default_port="${var_addon_default_port:-8080}"
var_addon_src_dir="${var_addon_src_dir:-/}"

function install_script() {
  if [[ "$OS_FAMILY" != "debian" && "$OS_FAMILY" != "alpine" ]]; then
    msg_error "Unsupported OS: ${OS_TYPE} (Debian/Ubuntu and Alpine only)"
    exit 1
  fi

  # Detect legacy FileBrowser installation
  local legacy_db="/usr/local/community-scripts/filebrowser.db"
  if [[ -f "$legacy_db" || (-f "$var_addon_bin_path" && ! -f "$var_addon_conf_path") ]]; then
    msg_warn "Detected legacy FileBrowser installation."
    echo -n "${TAB}Uninstall legacy FileBrowser and continue with Quantum install? (y/n): "
    read -r remove_legacy || true
    if [[ "${remove_legacy,,}" =~ ^(y|yes)$ ]]; then
      msg_info "Uninstalling legacy FileBrowser"
      if [[ "$INIT_SYSTEM" == "openrc" ]]; then
        rc-service filebrowser stop &> /dev/null || true
        rc-update del filebrowser &> /dev/null || true
        rm -f /etc/init.d/filebrowser
      else
        systemctl disable --now filebrowser.service &> /dev/null || true
        rm -f /etc/systemd/system/filebrowser.service
      fi
      rm -f "$var_addon_bin_path" "$legacy_db"
      msg_ok "Legacy FileBrowser removed"
    else
      msg_error "Installation aborted by user."
      exit 0
    fi
  fi

  echo ""
  read -erp "${TAB}Enter port number [${var_addon_default_port}]: " PORT || true
  PORT=${PORT:-$var_addon_default_port}

  msg_info "Installing Dependencies"
  if [[ "$OS_FAMILY" == "debian" ]]; then
    $STD apt install -y curl ffmpeg
  else
    $STD apk add --no-cache curl ffmpeg
  fi
  msg_ok "Installed Dependencies"

  msg_info "Installing ${APP}"
  fetch_and_deploy_gh_release "filebrowser-quantum" "gtsteffaniak/filebrowser" "singlefile" "latest" "/usr/local/bin" "linux-$(get_system_arch uname)-filebrowser"
  mv -f /usr/local/bin/filebrowser-quantum "$var_addon_bin_path"
  msg_ok "Installed ${APP}"

  msg_info "Preparing configuration directory"
  mkdir -p "$var_addon_conf_dir"
  chown root:root "$var_addon_conf_dir"
  chmod 755 "$var_addon_conf_dir"
  msg_ok "Directory prepared"

  echo -n "${TAB}Use No Authentication? (y/N): "
  read -r noauth_prompt || true
  if [[ "${noauth_prompt,,}" =~ ^(y|yes)$ ]]; then
    cat << EOF > "$var_addon_conf_path"
server:
  port: ${PORT}
  sources:
    - path: "${var_addon_src_dir}"
      name: "RootFS"
      config:
        denyByDefault: false
        indexingIntervalMinutes: 240
        conditionals:
          rules:
            - neverWatchPath: "/proc"
            - neverWatchPath: "/sys"
            - neverWatchPath: "/dev"
            - neverWatchPath: "/run"
            - neverWatchPath: "/tmp"
            - neverWatchPath: "/lost+found"
auth:
  methods:
    noauth: true
EOF
    msg_ok "Configured with no authentication"
  else
    cat << EOF > "$var_addon_conf_path"
server:
  port: ${PORT}
  sources:
    - path: "${var_addon_src_dir}"
      name: "RootFS"
      config:
        denyByDefault: false
        indexingIntervalMinutes: 240
        conditionals:
          rules:
            - neverWatchPath: "/proc"
            - neverWatchPath: "/sys"
            - neverWatchPath: "/dev"
            - neverWatchPath: "/run"
            - neverWatchPath: "/tmp"
            - neverWatchPath: "/lost+found"
auth:
  adminUsername: admin
  adminPassword: community-scripts.org
EOF
    msg_ok "Configured with default admin (admin / community-scripts.org)"
  fi

  msg_info "Creating Service"
  if [[ "$INIT_SYSTEM" == "openrc" ]]; then
    cat << EOF > /etc/init.d/filebrowser
#!/sbin/openrc-run

command="${var_addon_bin_path}"
command_args="-c ${var_addon_conf_path}"
command_background=true
directory="${var_addon_conf_dir}"
pidfile="${var_addon_conf_dir}/pidfile"

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
Description=FileBrowser Quantum
After=network.target

[Service]
User=root
WorkingDirectory=${var_addon_conf_dir}
ExecStart=${var_addon_bin_path} -c ${var_addon_conf_path}
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
  if [[ "${noauth_prompt,,}" =~ ^(y|yes)$ ]]; then
    echo -e "${INFO}${YW}Authentication:${CL} disabled (noauth)"
  else
    echo -e "${INFO}${YW}Login:${CL} ${GN}admin${CL} / ${GN}community-scripts.org${CL}"
  fi
  echo -e "${INFO}${YW}Update:${CL} update-${APP_SLUG}   ${YW}Uninstall:${CL} uninstall-${APP_SLUG}"
}

function update_script() {
  if check_for_gh_release "filebrowser-quantum" "gtsteffaniak/filebrowser"; then
    msg_info "Stopping Service"
    if [[ "$INIT_SYSTEM" == "openrc" ]]; then
      rc-service filebrowser stop &> /dev/null || true
    else
      systemctl stop filebrowser &> /dev/null || true
    fi
    msg_ok "Stopped Service"

    msg_info "Updating ${APP}"
    fetch_and_deploy_gh_release "filebrowser-quantum" "gtsteffaniak/filebrowser" "singlefile" "latest" "/usr/local/bin" "linux-$(get_system_arch uname)-filebrowser"
    mv -f /usr/local/bin/filebrowser-quantum "$var_addon_bin_path"
    msg_ok "Updated ${APP}"

    msg_info "Starting Service"
    if [[ "$INIT_SYSTEM" == "openrc" ]]; then
      rc-service filebrowser start
    else
      systemctl start filebrowser
    fi
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
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
  rm -f "$var_addon_bin_path" "$var_addon_conf_path" "$HOME/.filebrowser-quantum"
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
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/addon")
