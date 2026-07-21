#!/usr/bin/env bash
# shellcheck disable=SC2034
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: michelroegl-brunner
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/opf/openproject

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="OpenProject"
var_tags="${var_tags:-project-management;erp}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    apt-transport-https \
    build-essential \
    autoconf
  msg_ok "Installed Dependencies"

  PG_VERSION="17" setup_postgresql
  PG_DB_NAME="openproject" PG_DB_USER="openproject" setup_postgresql_db
  API_KEY=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | cut -c1-13)
  echo "OpenProject API Key: $API_KEY" >> ~/openproject.creds
  fetch_and_deploy_gh_release "jemalloc" "jemalloc/jemalloc" "tarball"

  msg_info "Compiling jemalloc (Patience)"
  cd /opt/jemalloc || exit
  $STD ./autogen.sh
  $STD make
  $STD make install
  msg_ok "Compiled jemalloc"

  setup_deb822_repo \
    "openproject" \
    "https://packages.openproject.com/srv/deb/opf/openproject/gpg-key.gpg" \
    "https://packages.openproject.com/srv/deb/opf/openproject/stable/17/debian/" \
    "12"

  msg_info "Installing OpenProject"
  $STD apt install -y openproject
  msg_ok "Installed OpenProject"

  msg_info "Configuring OpenProject"
  cat << EOF > /etc/openproject/installer.dat
openproject/edition default

postgres/retry retry
postgres/autoinstall reuse
postgres/db_host 127.0.0.1
postgres/db_port 5432
postgres/db_username ${PG_DB_USER}
postgres/db_password ${PG_DB_PASS}
postgres/db_name ${PG_DB_NAME}
server/autoinstall install
server/variant apache2

server/hostname ${LOCAL_IP}
server/server_path_prefix /openproject
server/ssl no
server/variant apache2
repositories/api-key ${API_KEY}
repositories/svn-install skip
repositories/git-install install
repositories/git-path /var/db/openproject/git
repositories/git-http-backend /usr/lib/git-core/git-http-backend/
memcached/autoinstall install
openproject/admin_email admin@example.net
openproject/default_language en
EOF
  $STD openproject configure
  systemctl stop openproject-web-1
  if ! grep -qF 'Environment=LD_PRELOAD=/usr/local/lib/libjemalloc.so.2' /etc/systemd/system/openproject-web-1.service; then
    sed -i '/^\[Service\]/a Environment=LD_PRELOAD=/usr/local/lib/libjemalloc.so.2' /etc/systemd/system/openproject-web-1.service
  fi
  systemctl start openproject-web-1
  msg_ok "Configured OpenProject"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}/openproject${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /etc/openproject/installer.dat ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating OpenProject"
  $STD apt update
  $STD apt install --only-upgrade -y openproject
  msg_ok "Updated OpenProject"
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
