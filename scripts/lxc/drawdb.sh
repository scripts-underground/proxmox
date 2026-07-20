#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/drawdb-io/drawdb

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="DrawDB"
var_tags="${var_tags:-database;dev-tools}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-6144}"
var_disk="${var_disk:-5}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    nginx
  msg_ok "Installed Dependencies"

  NODE_VERSION="22" setup_nodejs

  fetch_and_deploy_gh_tag "drawdb" "drawdb-io/drawdb" "latest" "/opt/drawdb"

  msg_info "Building Frontend"
  cd /opt/drawdb || exit
  $STD npm ci
  NODE_OPTIONS="--max-old-space-size=4096" $STD npm run build
  sed -i '/<head>/a <script>if(!crypto.randomUUID){crypto.randomUUID=function(){return([1e7]+-1e3+-4e3+-8e3+-1e11).replace(/[018]/g,function(c){return(c^(crypto.getRandomValues(new Uint8Array(1))[0]&(15>>c/4))).toString(16)})}};</script>' /opt/drawdb/dist/index.html
  msg_ok "Built Frontend"

  msg_info "Configuring Nginx"
  cat << EOF > /etc/nginx/sites-available/drawdb
server {
    listen 3000;
    server_name _;
    root /opt/drawdb/dist;
    index index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
EOF
  ln -sf /etc/nginx/sites-available/drawdb /etc/nginx/sites-enabled/drawdb
  rm -f /etc/nginx/sites-enabled/default
  systemctl reload nginx
  msg_ok "Configured Nginx"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/drawdb ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_tag "drawdb" "drawdb-io/drawdb"; then
    msg_info "Stopping Nginx"
    systemctl stop nginx
    msg_ok "Stopped Nginx"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_tag "drawdb" "drawdb-io/drawdb" "latest" "/opt/drawdb"

    msg_info "Rebuilding Frontend"
    cd /opt/drawdb || exit
    $STD npm ci
    NODE_OPTIONS="--max-old-space-size=4096" $STD npm run build
    sed -i '/<head>/a <script>if(!crypto.randomUUID){crypto.randomUUID=function(){return([1e7]+-1e3+-4e3+-8e3+-1e11).replace(/[018]/g,function(c){return(c^(crypto.getRandomValues(new Uint8Array(1))[0]&(15>>c/4))).toString(16)})}};</script>' /opt/drawdb/dist/index.html
    msg_ok "Rebuilt Frontend"

    msg_info "Starting Nginx"
    systemctl start nginx
    msg_ok "Started Nginx"

    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
