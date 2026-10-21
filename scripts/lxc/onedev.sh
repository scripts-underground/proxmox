#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"
# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: kristocopani
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://onedev.io/
# shellcheck disable=SC2034
APP="OneDev"
var_tags="${var_tags:-git}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y git git-lfs
  msg_ok "Installed Dependencies"

  JAVA_VERSION="21" setup_java

  msg_info "Installing OneDev"
  local release="${var_appversion:-latest}" stage stage_rc=0 cleanup_rc=0
  if [[ "$release" == latest ]]; then release=$(get_latest_github_release "theonedev/onedev" false) || exit $?; fi
  [[ ! -e /opt/onedev && ! -L /opt/onedev ]] || {
    msg_error "Existing OneDev target retained; use its update command"
    exit 65
  }
  stage=$(mktemp -d /opt/.onedev-release.XXXXXX) || exit $?
  # Only this owned stage is extracted/removed. Unknown legacy extraction paths
  # are never reused, swept or moved into the installation.
  function onedev_install_release() {
    local deployed installed service=onedev.server
    curl -fsSL "https://code.onedev.io/onedev/server/~sites/public/onedev-latest.tar.gz" -o "$stage/archive.tar.gz" || return $?
    tar -xzf "$stage/archive.tar.gz" -C "$stage" || return $?
    deployed=$(awk -F= '$1=="version" {if(NF!=2)exit 65; value=$2; count++} END {if(count!=1)exit 65; print value}' "$stage/onedev-latest/release.properties") || return 65
    [[ "$deployed" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 65
    [[ "$deployed" == "${release#v}" ]] || {
      msg_error "OneDev artifact version $deployed differs from selected $release"
      return 250
    }
    mv -T -- "$stage/onedev-latest" /opt/onedev || return $?
    $STD /opt/onedev/bin/server.sh install || return $?
    [[ ! -f /etc/systemd/system/onedev.service ]] || service=onedev
    installed=$(awk -F= '$1=="version" {if(NF!=2)exit 65; value=$2; count++} END {if(count!=1)exit 65; print value}' /opt/onedev/release.properties) || return 65
    [[ "$installed" == "$deployed" ]] || return 250
    systemctl start "$service" || return $?
    printf '%s\n' "$release" > "$HOME/.onedev"
  }
  onedev_install_release || stage_rc=$?
  _deploy_remove_owned_trees "$stage" || cleanup_rc=$?
  [[ "$stage_rc" == 0 ]] || exit "$stage_rc"
  [[ "$cleanup_rc" == 0 ]] || exit "$cleanup_rc"
  msg_ok "Installed OneDev"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:6610${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  local service=onedev.server
  [[ ! -f /etc/systemd/system/onedev.service ]] || service=onedev
  if [[ ! -f "/etc/systemd/system/$service.service" ]]; then
    msg_error "No ${APP} Installation Found!"
    exit 1
  fi
  if check_for_gh_release "onedev" "theonedev/onedev"; then
    JAVA_VERSION="21" setup_java
    msg_info "Updating OneDev"
    local stage stage_rc=0 cleanup_rc=0
    stage=$(mktemp -d /opt/.onedev-release.XXXXXX) || exit $?
    function onedev_upgrade_release() {
      local deployed installed
      curl -fsSL "https://code.onedev.io/onedev/server/~sites/public/onedev-latest.tar.gz" -o "$stage/archive.tar.gz" || return $?
      tar -xzf "$stage/archive.tar.gz" -C "$stage" || return $?
      deployed=$(awk -F= '$1=="version" {if(NF!=2)exit 65; value=$2; count++} END {if(count!=1)exit 65; print value}' "$stage/onedev-latest/release.properties") || return 65
      [[ "$deployed" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 65
      [[ "$deployed" == "${CHECK_UPDATE_RELEASE#v}" ]] || {
        msg_error "OneDev artifact version $deployed differs from selected $CHECK_UPDATE_RELEASE"
        return 250
      }
      systemctl stop "$service" || return $?
      $STD "$stage/onedev-latest/bin/upgrade.sh" /opt/onedev || return $?
      installed=$(awk -F= '$1=="version" {if(NF!=2)exit 65; value=$2; count++} END {if(count!=1)exit 65; print value}' /opt/onedev/release.properties) || return 65
      [[ "$installed" == "$deployed" ]] || return 250
      service=onedev.server
      [[ ! -f /etc/systemd/system/onedev.service ]] || service=onedev
      systemctl start "$service" || return $?
      printf '%s\n' "$CHECK_UPDATE_RELEASE" > "$HOME/.onedev"
    }
    onedev_upgrade_release || stage_rc=$?
    _deploy_remove_owned_trees "$stage" || cleanup_rc=$?
    [[ "$stage_rc" == 0 ]] || exit "$stage_rc"
    [[ "$cleanup_rc" == 0 ]] || exit "$cleanup_rc"
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  else
    local checker_rc=$?
    [[ "$checker_rc" == 1 ]] || exit "$checker_rc"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
