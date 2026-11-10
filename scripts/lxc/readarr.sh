#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://readarr.com/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Readarr"
var_tags="${var_tags:-media;comic;eBook}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y sqlite3 libicu-dev
  msg_ok "Installed Dependencies"

  msg_info "Installing retired Readarr test release v0.4.18.2805"
  local ARCH digest archive stage rc=0 cleanup_rc
  ARCH=$(get_system_arch both x64 arm64) || return $?
  case "$ARCH" in
    x64) digest=842ab11fac4f2e103e57badeaac1e2d44636b14dc727a1123098a2597adc5141 ;;
    arm64) digest=ecda47df6b6410e615c9fc0806af4b08a028d0843521e8587ca8beaa20737fca ;;
    *)
      msg_error "Unsupported Readarr architecture: $ARCH"
      return 65
      ;;
  esac
  archive="Readarr.develop.0.4.18.2805.linux-core-${ARCH}.tar.gz"
  mkdir -p /var/lib/readarr/
  chmod 775 /var/lib/readarr/
  stage=$(mktemp -d "${TMPDIR:?}/readarr.XXXXXX") || return $?
  # Keep the helper's marker/downloads private; integrity is checked before tar.
  # Explicit status handling preserves the caller's traps even in conditional hooks.
  if HOME="$stage" TMPDIR="$stage" var_appversion='' USE_ORIGINAL_FILENAME=true \
    fetch_and_deploy_gh_release readarr Readarr/Readarr singlefile v0.4.18.2805 "$stage/download" "$archive" &&
    printf '%s  %s\n' "$digest" "$stage/download/$archive" | $STD sha256sum -c - &&
    mkdir -p "$stage/extract" &&
    $STD tar -xzf "$stage/download/$archive" -C "$stage/extract" &&
    mv "$stage/extract/Readarr" /opt/Readarr &&
    chmod 775 /opt/Readarr; then
    rc=0
  else
    rc=$?
  fi
  rm -rf -- "$stage" || {
    cleanup_rc=$?
    msg_error "Failed to remove Readarr staging: $stage"
    [[ "$rc" != 0 ]] || rc=$cleanup_rc
  }
  [[ "$rc" == 0 ]] || return "$rc"
  msg_ok "Installed retired Readarr test release; metadata service is not qualified"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/readarr.service
[Unit]
Description=Readarr Daemon
After=syslog.target network.target

[Service]
UMask=0002
Type=simple
ExecStart=/opt/Readarr/Readarr -nobrowser -data=/var/lib/readarr/
TimeoutStopSec=20
KillMode=process
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  systemctl -q daemon-reload
  systemctl enable --now -q readarr
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8787${CL}"
  echo "Readarr is retired; UI availability does not establish working metadata lookup."
  echo "The update command updates OS packages only, not Readarr."
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /var/lib/readarr/ ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating OS packages only; this does not update Readarr"
  $STD apt update
  $STD apt -y upgrade
  msg_ok "Updated OS packages only; this does not update Readarr"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc") --script-id "readarr" -- "$@"
