#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Michel Roegl-Brunner (michelroegl-brunner)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://zammad.com

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Zammad"
var_tags="${var_tags:-webserver;ticket-system}"
var_disk="${var_disk:-8}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    git \
    nginx \
    apt-transport-https
  msg_ok "Installed Dependencies"

  msg_info "Setting up Elasticsearch"
  setup_deb822_repo \
    "elasticsearch" \
    "https://artifacts.elastic.co/GPG-KEY-elasticsearch" \
    "https://artifacts.elastic.co/packages/7.x/apt" \
    "stable" \
    "main"
  $STD apt install -y elasticsearch
  sed -i 's/^#\{0,2\} *-Xms[0-9]*g.*/-Xms2g/' /etc/elasticsearch/jvm.options
  sed -i 's/^#\{0,2\} *-Xmx[0-9]*g.*/-Xmx2g/' /etc/elasticsearch/jvm.options
  cat << EOF > /etc/elasticsearch/elasticsearch.yml
path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch
discovery.type: single-node
network.host: 127.0.0.1
xpack.security.enabled: false
bootstrap.memory_lock: false
EOF
  $STD /usr/share/elasticsearch/bin/elasticsearch-plugin install ingest-attachment -b
  systemctl daemon-reload
  systemctl enable -q elasticsearch
  systemctl restart -q elasticsearch
  # shellcheck disable=SC2034
  for i in $(seq 1 30); do
    if curl -s http://127.0.0.1:9200 > /dev/null 2>&1; then
      break
    fi
    sleep 2
  done
  msg_ok "Setup Elasticsearch"

  msg_info "Installing Zammad"
  setup_deb822_repo \
    "zammad" \
    "https://dl.packager.io/srv/zammad/zammad/key" \
    "https://dl.packager.io/srv/deb/zammad/zammad/stable/debian" \
    "$(get_os_info version_id)" \
    "main"
  $STD apt install -y zammad
  $STD zammad run rails r "Setting.set('es_url', 'http://127.0.0.1:9200')"
  $STD zammad run rake zammad:searchindex:rebuild
  msg_ok "Installed Zammad"

  msg_info "Setup Services"
  cp /opt/zammad/contrib/nginx/zammad.conf /etc/nginx/sites-available/zammad.conf
  sed -i "s/server_name localhost;/server_name $LOCAL_IP;/g" /etc/nginx/sites-available/zammad.conf
  ln -sf /etc/nginx/sites-available/zammad.conf /etc/nginx/sites-enabled/
  rm -f /etc/nginx/sites-enabled/default
  $STD systemctl reload nginx
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/zammad ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Stopping Service"
  systemctl stop zammad
  msg_ok "Stopped Service"

  msg_info "Updating Zammad"
  $STD apt update
  $STD apt-mark hold zammad
  $STD apt upgrade -y
  $STD apt-mark unhold zammad
  $STD apt upgrade -y
  msg_ok "Updated Zammad"

  msg_info "Starting Service"
  systemctl start zammad
  msg_ok "Started Service"
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
