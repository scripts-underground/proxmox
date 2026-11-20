#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://tomcat.apache.org/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Apache-Tomcat"
var_tags="${var_tags:-webserver}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-5}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

# Keep the documented environment overrides and transport them into the bundles.
var_lxc_tomcat_version="${var_lxc_tomcat_version:-${TOMCAT_VERSION:-11}}"
var_lxc_java_version="${var_lxc_java_version:-${JAVA_VERSION:-21}}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y curl
  msg_ok "Installed Dependencies"

  JAVA_VERSION="$var_lxc_java_version" setup_java

  local tomcat_major=$var_lxc_tomcat_version java_version=$var_lxc_java_version
  local listing latest_version tomcat_url tomcat_dir="/opt/tomcat-$var_lxc_tomcat_version"
  msg_info "Installing Tomcat ${tomcat_major}"
  listing=$(curl -fsSL "https://dlcdn.apache.org/tomcat/tomcat-${tomcat_major}/") || return $?
  # A listing without release links yields an empty version, not an errexit abort.
  latest_version=$(printf '%s\n' "$listing" | { grep -oP 'v[0-9]+\.[0-9]+\.[0-9]+(-M[0-9]+)?/' || [[ $? == 1 ]]; } | sort -V | tail -n1 | sed 's/\/$//; s/v//')
  if [[ -z "$latest_version" ]]; then
    msg_error "Failed to fetch latest version for Tomcat ${tomcat_major}"
    return 65
  fi
  tomcat_url="https://dlcdn.apache.org/tomcat/tomcat-${tomcat_major}/v${latest_version}/bin/apache-tomcat-${latest_version}.tar.gz"
  fetch_and_deploy_from_url "$tomcat_url" "$tomcat_dir"
  chown -R root:root "$tomcat_dir"
  msg_ok "Tomcat ${latest_version} installed"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/tomcat.service
[Unit]
Description=Apache Tomcat Web Application Container
After=network.target

[Service]
Type=forking
User=root
Group=root
Environment=JAVA_HOME=/usr/lib/jvm/temurin-${java_version}-jdk-$(get_system_arch)
Environment=CATALINA_HOME=${tomcat_dir}
Environment=CATALINA_BASE=${tomcat_dir}
Environment=CATALINA_PID=${tomcat_dir}/temp/tomcat.pid
ExecStart=${tomcat_dir}/bin/catalina.sh start
ExecStop=${tomcat_dir}/bin/catalina.sh stop
PIDFile=${tomcat_dir}/temp/tomcat.pid
SuccessExitStatus=143
Restart=on-abnormal

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now tomcat
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8080${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  local tomcat_dir tomcat_major current_version listing latest_version staged_version tomcat_url stage rc=0
  local -a trees=()
  mapfile -t trees < <(compgen -G '/opt/tomcat-*' || true)
  if [[ ${#trees[@]} -gt 1 ]]; then
    msg_error "Multiple Tomcat trees found (${trees[*]}); cannot select the runtime to update"
    return 65
  fi
  tomcat_dir=${trees[0]:-}
  if [[ -z $tomcat_dir || ! -d $tomcat_dir ]]; then
    msg_error "No ${APP} Installation Found!"
    return 1
  fi

  tomcat_major=$(basename "$tomcat_dir" | grep -oP 'tomcat-\K[0-9]+')
  if [[ -z $tomcat_major ]]; then
    msg_error "Cannot determine Tomcat major version from path: $tomcat_dir"
    return 65
  fi
  current_version=$(grep -oP 'Apache Tomcat Version \K[0-9]+\.[0-9]+\.[0-9]+(-M[0-9]+)?' "$tomcat_dir/RELEASE-NOTES" 2> /dev/null | head -n1) || current_version=unknown
  listing=$(curl -fsSL "https://dlcdn.apache.org/tomcat/tomcat-${tomcat_major}/") || return $?
  # A listing without release links yields an empty version, not an errexit abort.
  latest_version=$(printf '%s\n' "$listing" | { grep -oP 'v[0-9]+\.[0-9]+\.[0-9]+(-M[0-9]+)?/' || [[ $? == 1 ]]; } | sort -V | tail -n1 | sed 's/\/$//; s/v//')

  if [[ -z $latest_version ]]; then
    msg_error "Failed to fetch latest version for Tomcat ${tomcat_major}"
    return 65
  fi

  if [[ $current_version == "$latest_version" && ${UPDATE_FORCE:-0} != 1 && ${FORCE_DEPLOY:-0} != 1 ]]; then
    msg_ok "${APP} ${current_version} is already up to date"
    return 0
  fi

  # Prepare a complete distribution before disturbing the running application.
  stage=$(_tools_stage_dir tomcat-update) || return $?
  tomcat_url="https://dlcdn.apache.org/tomcat/tomcat-${tomcat_major}/v${latest_version}/bin/apache-tomcat-${latest_version}.tar.gz"
  fetch_and_deploy_from_url "$tomcat_url" "$stage" || rc=$?
  if [[ "$rc" == 0 ]]; then
    staged_version=$(grep -oP 'Apache Tomcat Version \K[0-9]+\.[0-9]+\.[0-9]+(-M[0-9]+)?' "$stage/RELEASE-NOTES" 2> /dev/null | head -n1) || staged_version=''
    if [[ ! -x "$stage/bin/catalina.sh" || ! -f "$stage/lib/catalina.jar" || "$staged_version" != "$latest_version" ]]; then
      msg_error "Downloaded distribution does not match Tomcat ${latest_version}"
      rc=65
    fi
  fi

  # CATALINA_BASE shares this tree with the distribution. Keep operator-owned
  # paths in place; merge mode also retains old-only files such as added jars.
  local CLEAN_INSTALL_KEEP="${CLEAN_INSTALL_KEEP:-}"
  local -a CLEAN_INSTALL_KEEP_PATHS=("${CLEAN_INSTALL_KEEP_PATHS[@]}" conf webapps logs work temp bin/setenv.sh bin/setenv.bat)
  # Fingerprint the replaceable runtime; keep paths never leave the live tree.
  function tomcat_runtime_state() {
    local entry
    local -a keep=() prune=(-path './.deploy-aside.*')
    read -r -a keep <<< "$CLEAN_INSTALL_KEEP"
    for entry in "${CLEAN_INSTALL_KEEP_PATHS[@]}" "${keep[@]}"; do prune+=(-o -path "./$entry"); done
    (
      set -o pipefail
      cd -- "$tomcat_dir" || exit
      {
        find . -mindepth 1 \( "${prune[@]}" \) -prune -o -printf '%P\t%y\t%m\t%U:%G\t%l\n' | LC_ALL=C sort || exit
        find . -mindepth 1 \( "${prune[@]}" \) -prune -o -type f -print0 | LC_ALL=C sort -z | xargs -0r sha256sum || exit
      } | sha256sum
    )
  }
  local was_active=0 stopped=0 before_state='' after_state=''
  if [[ "$rc" == 0 ]]; then
    before_state=$(tomcat_runtime_state) || rc=$?
  fi
  if [[ "$rc" == 0 ]]; then
    if systemctl is-active --quiet tomcat; then was_active=1; fi
    msg_info "Stopping Tomcat service"
    stopped=1
    systemctl stop tomcat || rc=$?
  fi
  if [[ "$rc" == 0 ]]; then
    msg_info "Installing Tomcat ${latest_version}"
    _deploy_replace_contents "$stage" "$tomcat_dir" 0 || rc=$?
  fi
  local cleanup_rc=0
  rm -rf -- "$stage" || cleanup_rc=$?
  if [[ "$rc" != 0 ]]; then
    # Restart a previously running service only on the verified old runtime.
    if [[ "$stopped" == 1 && "$was_active" == 1 ]]; then
      if after_state=$(tomcat_runtime_state) && [[ "$after_state" == "$before_state" ]]; then
        systemctl start tomcat || msg_error "Unable to restart the restored Tomcat runtime"
      else
        msg_error "Previous Tomcat runtime is not verified; service left stopped"
      fi
    fi
    return "$rc"
  fi

  msg_info "Starting Tomcat service"
  systemctl start tomcat || return $?
  msg_ok "Started Tomcat service"
  [[ "$cleanup_rc" == 0 ]] || msg_warn "Unable to remove Tomcat staging directory $stage"
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc") --script-id "apache-tomcat" -- "$@"
