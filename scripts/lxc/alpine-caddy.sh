#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: cobalt (cobaltgit)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://caddyserver.com/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Alpine-Caddy"
var_tags="${var_tags:-webserver}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-256}"
var_disk="${var_disk:-3}"
var_os="${var_os:-alpine}"
var_version="${var_version:-3.23}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Caddy"
  $STD apk add --no-cache caddy caddy-openrc
  cat << EOF > /etc/caddy/Caddyfile
:80 {
  root * /var/www/html
  file_server
}
EOF
  mkdir -p /var/www/html
  cat << EOF > /var/www/html/index.html
<!DOCTYPE html>
<html>
  <head>
    <title>Caddy works!</title>
  </head>
  <body>
    <h1>Hello Caddy!</h1>
    <p>For more information, refer to the Caddy <a href="https://caddyserver.com/docs/">documentation</a><p>
  </body>
</html>
EOF
  msg_ok "Installed Caddy"

  msg_info "Enabling Caddy Service"
  $STD rc-update add caddy default
  msg_ok "Enabled Caddy Service"

  msg_info "Starting Caddy"
  $STD service caddy start
  msg_ok "Started Caddy"

  local prompt=""
  read -r -p "${TAB3}Would you like to install xCaddy Addon? <y/N> " prompt || true
  if [[ "${prompt,,}" =~ ^(y|yes)$ ]]; then
    touch /root/.xcaddy-requested
    # Cold amd64 builds: 488 MiB non-file memory, 2811 MiB additional disk.
    # Add 512 MiB margin, then round up to 256/512 MiB boundaries.
    local memory_mib memory_max=max disk_mib
    memory_mib=$(awk '/^MemAvailable:/ {print int($2 / 1024); exit}' "/proc/meminfo") || memory_mib=0
    [[ "$memory_mib" =~ ^[0-9]+$ ]] || memory_mib=0
    if [[ -r /sys/fs/cgroup/memory.max ]]; then
      read -r memory_max < /sys/fs/cgroup/memory.max || true
      if [[ "$memory_max" =~ ^[0-9]+$ ]] && ((memory_max / 1048576 < memory_mib)); then
        memory_mib=$((memory_max / 1048576))
      fi
    fi
    disk_mib=$(df -Pk /opt | awk 'NR == 2 {print int($4 / 1024)}') || disk_mib=0
    [[ "$disk_mib" =~ ^[0-9]+$ ]] || disk_mib=0
    if ((memory_mib < 1024 || disk_mib < 3584)); then
      msg_warn "xCaddy requires 1024 MiB available RAM and 3584 MiB free on /opt (available: ${memory_mib} MiB RAM, ${disk_mib} MiB disk). Optional build skipped; plain Caddy and existing built binaries are unchanged."
      msg_warn "Increase this CT in Proxmox Resources > Memory / Root Disk, then rerun update inside this CT."
      return 0
    fi
    local build_dir RELEASE arch
    build_dir=$(mktemp -d /opt/.xcaddy-build.XXXXXX)
    mkdir -p "$build_dir/tmp" "$build_dir/cache" "$build_dir/mod" "$build_dir/go"
    TMPDIR="$build_dir/tmp" GO_VERSION="$(curl -fsSL https://go.dev/VERSION?m=text | head -1 | cut -c3-)" setup_go
    msg_info "Setup xCaddy"
    RELEASE=$(curl -fsSL https://api.github.com/repos/caddyserver/xcaddy/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
    arch=$(get_system_arch uname)
    curl -fsSL "https://github.com/caddyserver/xcaddy/releases/download/${RELEASE}/xcaddy_${RELEASE:1}_linux_${arch}.tar.gz" -o "$build_dir/xcaddy.tar.gz"
    $STD tar xzf "$build_dir/xcaddy.tar.gz" -C /usr/local/bin xcaddy
    rm -f "$build_dir/xcaddy.tar.gz"
    if $STD env TMPDIR="$build_dir/tmp" GOTMPDIR="$build_dir/tmp" GOCACHE="$build_dir/cache" GOMODCACHE="$build_dir/mod" GOPATH="$build_dir/go" xcaddy build --output "$build_dir/caddy"; then
      if [[ -d /opt/caddy ]]; then
        msg_error "Cannot publish xCaddy build: /opt/caddy is a directory"
        rm -rf -- "$build_dir"
        return 1
      fi
      mv -f "$build_dir/caddy" /opt/caddy
    else
      local status=$?
      rm -rf -- "$build_dir"
      return "$status"
    fi
    rm -rf -- "$build_dir"
    rm -f /root/.xcaddy-requested
    msg_ok "Setup xCaddy"
  fi
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:80${CL}"
}

function update_script() {
  header_info
  if [[ ! -d /etc/caddy ]]; then
    msg_error "No ${APP} Installation Found!"
    exit 1
  fi
  if command -v xcaddy > /dev/null 2>&1 || [[ -f /root/.xcaddy-requested ]]; then
    # Same measured optional-build admission as install; no package, tool or
    # service effects precede refusal, and pending keeps the opt-in retryable.
    local memory_mib memory_max=max disk_mib
    memory_mib=$(awk '/^MemAvailable:/ {print int($2 / 1024); exit}' "/proc/meminfo") || memory_mib=0
    [[ "$memory_mib" =~ ^[0-9]+$ ]] || memory_mib=0
    if [[ -r /sys/fs/cgroup/memory.max ]]; then
      read -r memory_max < /sys/fs/cgroup/memory.max || true
      if [[ "$memory_max" =~ ^[0-9]+$ ]] && ((memory_max / 1048576 < memory_mib)); then
        memory_mib=$((memory_max / 1048576))
      fi
    fi
    disk_mib=$(df -Pk /opt | awk 'NR == 2 {print int($4 / 1024)}') || disk_mib=0
    [[ "$disk_mib" =~ ^[0-9]+$ ]] || disk_mib=0
    if ((memory_mib < 1024 || disk_mib < 3584)); then
      msg_warn "xCaddy requires 1024 MiB available RAM and 3584 MiB free on /opt (available: ${memory_mib} MiB RAM, ${disk_mib} MiB disk). Optional build skipped; plain Caddy and existing built binaries are unchanged."
      msg_warn "Increase this CT in Proxmox Resources > Memory / Root Disk, then rerun update inside this CT."
      return 1
    fi
    local build_dir RELEASE arch
    build_dir=$(mktemp -d /opt/.xcaddy-build.XXXXXX)
    mkdir -p "$build_dir/tmp" "$build_dir/cache" "$build_dir/mod" "$build_dir/go"
    TMPDIR="$build_dir/tmp" GO_VERSION="$(curl -fsSL https://go.dev/VERSION?m=text | head -1 | cut -c3-)" setup_go
    msg_info "Updating xCaddy"
    RELEASE=$(curl -fsSL https://api.github.com/repos/caddyserver/xcaddy/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
    arch=$(get_system_arch uname)
    curl -fsSL "https://github.com/caddyserver/xcaddy/releases/download/${RELEASE}/xcaddy_${RELEASE:1}_linux_${arch}.tar.gz" -o "$build_dir/xcaddy.tar.gz"
    $STD tar xzf "$build_dir/xcaddy.tar.gz" -C /usr/local/bin xcaddy
    rm -f "$build_dir/xcaddy.tar.gz"
    if $STD env TMPDIR="$build_dir/tmp" GOTMPDIR="$build_dir/tmp" GOCACHE="$build_dir/cache" GOMODCACHE="$build_dir/mod" GOPATH="$build_dir/go" xcaddy build --output "$build_dir/caddy"; then
      if [[ -d /opt/caddy ]]; then
        msg_error "Cannot publish xCaddy build: /opt/caddy is a directory"
        rm -rf -- "$build_dir"
        return 1
      fi
      mv -f "$build_dir/caddy" /opt/caddy
    else
      local status=$?
      rm -rf -- "$build_dir"
      return "$status"
    fi
    rm -rf -- "$build_dir"
    rm -f /root/.xcaddy-requested
    msg_ok "Updated xCaddy"
  fi
  msg_info "Updating $APP LXC"
  $STD apk -U upgrade
  msg_ok "Updated $APP LXC"
  msg_info "Restarting Caddy"
  rc-service caddy restart
  msg_ok "Restarted Caddy"
  msg_ok "Updated successfully!"
  exit 0
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc") --script-id "alpine-caddy" -- "$@"
