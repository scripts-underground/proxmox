#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://couchdb.apache.org/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Apache-CouchDB"
var_tags="${var_tags:-database}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Apache CouchDB"
  ERLANG_COOKIE=$(openssl rand -base64 32)
  ADMIN_PASS=$(openssl rand -base64 18 | cut -c1-13)
  debconf-set-selections <<< "couchdb couchdb/cookie string $ERLANG_COOKIE"
  debconf-set-selections <<< "couchdb couchdb/mode select standalone"
  debconf-set-selections <<< "couchdb couchdb/bindaddress string 0.0.0.0"
  debconf-set-selections <<< "couchdb couchdb/adminpass password $ADMIN_PASS"
  debconf-set-selections <<< "couchdb couchdb/adminpass_again password $ADMIN_PASS"
  setup_deb822_repo \
    "couchdb" \
    "https://couchdb.apache.org/repo/keys.asc" \
    "https://apache.jfrog.io/artifactory/couchdb-deb" \
    "$(get_os_info codename)" \
    "main"
  $STD apt install -y couchdb
  cat << EOF > ~/couchdb.creds
CouchDB Credentials
CouchDB Erlang Cookie: $ERLANG_COOKIE
CouchDB Admin Password: $ADMIN_PASS
EOF
  msg_ok "Installed Apache CouchDB"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:5984/_utils/${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /usr/lib/systemd/system/couchdb.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating Apache CouchDB"
  $STD apt update
  $STD apt install -y --only-upgrade couchdb
  msg_ok "Updated Apache CouchDB"
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
