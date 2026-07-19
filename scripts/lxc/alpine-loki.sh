#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: hoholms
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/grafana/loki

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Alpine-Loki"
var_tags="${var_tags:-alpine;monitoring}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-alpine}"
var_version="${var_version:-3.23}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Loki"
  $STD apk add loki
  $STD sed -i '/http_addr/s/127.0.0.1/0.0.0.0/g' /etc/conf.d/loki
  mkdir -p /var/lib/loki/{chunks,boltdb-shipper-active,boltdb-shipper-cache}
  chown -R loki:grafana /var/lib/loki
  mkdir -p /var/log/loki
  chown -R loki:grafana /var/log/loki
  cat << EOF > /etc/loki/loki-local-config.yaml
auth_enabled: false
server:
  http_listen_port: 3100
  log_level: info
common:
  instance_addr: 127.0.0.1
  path_prefix: /var/lib/loki
  storage:
    filesystem:
      chunks_directory: /var/lib/loki/chunks
      rules_directory: /var/lib/loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory
schema_config:
  configs:
    - from: 2020-10-24
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h
limits_config:
  metric_aggregation_enabled: true
EOF
  chown loki:grafana /etc/loki/loki-local-config.yaml
  chmod 644 /etc/loki/loki-local-config.yaml
  echo 'output_log="${output_log:-/var/log/loki/output.log}"' >> /etc/init.d/loki
  echo 'error_log="${error_log:-/var/log/loki/error.log}"' >> /etc/init.d/loki
  echo 'start_stop_daemon_args="${SSD_OPTS} -1 ${output_log} -2 ${error_log}"' >> /etc/init.d/loki
  $STD rc-update add loki default
  $STD rc-service loki start
  msg_ok "Installed Loki"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3100${CL}"
}

function update_script() {
  header_info
  msg_info "Updating $APP LXC"
  $STD apk -U upgrade
  msg_ok "Updated $APP LXC"
  msg_info "Restarting Loki"
  rc-service loki restart
  msg_ok "Restarted Loki"
  msg_ok "Updated successfully!"
  exit 0
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
