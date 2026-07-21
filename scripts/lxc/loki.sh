#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: hoholms
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/grafana/loki

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Loki"
var_tags="${var_tags:-monitoring;logs}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Setting up Grafana Repository"
  setup_deb822_repo \
    "grafana" \
    "https://apt.grafana.com/gpg.key" \
    "https://apt.grafana.com" \
    "stable" \
    "main"
  msg_ok "Grafana Repository setup successfully"

  msg_info "Installing Loki"
  $STD apt install -y loki
  mkdir -p /var/lib/loki/{chunks,boltdb-shipper-active,boltdb-shipper-cache}
  chown -R loki /var/lib/loki
  cat << EOF > /etc/loki/config.yml
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

query_range:
  results_cache:
    cache:
      embedded_cache:
        enabled: true
        max_size_mb: 100

limits_config:
  metric_aggregation_enabled: true

ruler:
  alertmanager_url: http://localhost:9093
EOF
  chown loki /etc/loki/config.yml
  systemctl enable -q --now loki
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
  check_container_storage
  check_container_resources

  if ! dpkg -s loki > /dev/null 2>&1; then
    msg_error "No ${APP} Installation Found!"
    exit 233
  fi

  if [[ -f /etc/apt/sources.list.d/grafana.list ]] || [[ ! -f /etc/apt/sources.list.d/grafana.sources ]]; then
    setup_deb822_repo \
      "grafana" \
      "https://apt.grafana.com/gpg.key" \
      "https://apt.grafana.com" \
      "stable" \
      "main"
  fi

  msg_info "Updating ${APP} LXC"
  $STD apt update
  $STD apt --only-upgrade install -y loki
  systemctl restart loki
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
