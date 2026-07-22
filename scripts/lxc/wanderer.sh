#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: rrole
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://wanderer.to | Github: https://github.com/open-wanderer/wanderer

# shellcheck disable=SC2034
APP="Wanderer"
var_tags="${var_tags:-travelling;sport}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y build-essential
  msg_ok "Installed Dependencies"

  setup_go
  NODE_VERSION="22" setup_nodejs

  if [[ "$(get_system_arch)" == "arm64" ]]; then
    fetch_and_deploy_gh_release "meilisearch" "meilisearch/meilisearch" "singlefile" "latest" "/usr/local/bin" "meilisearch-linux-aarch64"
  else
    fetch_and_deploy_gh_release "meilisearch" "meilisearch/meilisearch" "binary" "latest" "/opt/wanderer/source/search"
  fi

  mkdir -p /opt/wanderer/{source,data/pb_data,data/meili_data,data/plugins}
  fetch_and_deploy_gh_release "wanderer" "open-wanderer/wanderer" "tarball" "latest" "/opt/wanderer/source"
  mkdir -p /opt/wanderer/source/db/data
  [[ -e /opt/wanderer/source/db/data/plugins ]] || ln -sfn /opt/wanderer/data/plugins /opt/wanderer/source/db/data/plugins

  msg_info "Installing wanderer (patience)"
  cd /opt/wanderer/source/db || exit
  $STD go mod tidy
  $STD go build
  cd /opt/wanderer/source/web || exit
  $STD npm ci
  $STD npm run build
  msg_ok "Installed wanderer"

  msg_info "Installing wanderer plugins"
  for plugin in hammerhead komoot strava; do
    fetch_and_deploy_gh_release "wanderer-plugin-${plugin}" "open-wanderer/wanderer" "prebuild" "latest" "/opt/wanderer/data/plugins" "wanderer-plugin-${plugin}.tar.gz" || msg_warn "Failed to install wanderer plugin: ${plugin}"
  done
  msg_ok "Installed wanderer plugins"

  msg_info "Creating Service"
  MEILI_KEY=$(openssl rand -hex 32)
  POCKETBASE_KEY=$(openssl rand -hex 16)

  cat << EOF > /opt/wanderer/.env
ORIGIN=http://${LOCAL_IP}:3000
MEILI_HTTP_ADDR=${LOCAL_IP}:7700
MEILI_URL=http://${LOCAL_IP}:7700
MEILI_MASTER_KEY=${MEILI_KEY}
PB_URL=${LOCAL_IP}:8090
PUBLIC_POCKETBASE_URL=http://${LOCAL_IP}:8090
PUBLIC_VALHALLA_URL=https://valhalla1.openstreetmap.de
POCKETBASE_ENCRYPTION_KEY=${POCKETBASE_KEY}
PB_DB_LOCATION=/opt/wanderer/data/pb_data
MEILI_DB_PATH=/opt/wanderer/data/meili_data
EOF

  cat << EOF > /opt/wanderer/start.sh
#!/usr/bin/env bash

trap "kill 0" EXIT

cd /opt/wanderer/source/search && meilisearch --experimental-dumpless-upgrade --master-key \$MEILI_MASTER_KEY &
sleep 1
cd /opt/wanderer/source/db && ./pocketbase serve --http=\$PB_URL --dir=\$PB_DB_LOCATION &
cd /opt/wanderer/source/web && node build &

wait -n
EOF
  chmod +x /opt/wanderer/start.sh

  cat << 'EOF' > /usr/local/bin/wanderer-pb
#!/usr/bin/env bash
set -a
source /opt/wanderer/.env
set +a
cd /opt/wanderer/source/db
exec ./pocketbase "$@" --dir="$PB_DB_LOCATION"
EOF
  chmod +x /usr/local/bin/wanderer-pb

  cat << EOF > /etc/systemd/system/wanderer-web.service
[Unit]
Description=wanderer
After=network.target
StartLimitIntervalSec=10
StartLimitBurst=5

[Service]
Type=simple
EnvironmentFile=/opt/wanderer/.env
ExecStart=/usr/bin/bash /opt/wanderer/start.sh
Restart=always
RestartSec=1

[Install]
WantedBy=multi-user.target
EOF
  sleep 1
  systemctl enable -q --now wanderer-web
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:3000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /opt/wanderer/start.sh ]]; then
    msg_error "No wanderer Installation Found!"
    exit
  fi

  if check_for_gh_release "wanderer" "open-wanderer/wanderer"; then
    msg_info "Stopping service"
    systemctl stop wanderer-web
    msg_ok "Stopped service"

    create_backup /opt/wanderer/source/search
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "wanderer" "open-wanderer/wanderer" "tarball" "latest" "/opt/wanderer/source"
    restore_backup

    msg_info "Updating wanderer"
    cd /opt/wanderer/source/db || exit
    $STD go mod tidy
    $STD go build
    cd /opt/wanderer/source/web || exit
    $STD npm ci
    $STD npm run build
    mkdir -p /opt/wanderer/data/plugins /opt/wanderer/source/db/data
    [[ -e /opt/wanderer/source/db/data/plugins ]] || ln -sfn /opt/wanderer/data/plugins /opt/wanderer/source/db/data/plugins
    msg_info "Installing wanderer plugins"
    for plugin in hammerhead komoot strava; do
      fetch_and_deploy_gh_release "wanderer-plugin-${plugin}" "open-wanderer/wanderer" "prebuild" "${CHECK_UPDATE_RELEASE:-latest}" "/opt/wanderer/data/plugins" "wanderer-plugin-${plugin}.tar.gz" || msg_warn "Failed to install wanderer plugin: ${plugin}"
    done
    msg_ok "Installed wanderer plugins"
    msg_ok "Updated wanderer"

    msg_info "Starting service"
    systemctl start wanderer-web
    msg_ok "Started service"
    msg_ok "Update Successful"
  fi
  if check_for_gh_release "meilisearch" "meilisearch/meilisearch"; then
    msg_info "Stopping service"
    systemctl stop wanderer-web
    msg_ok "Stopped service"

    fetch_and_deploy_gh_release "meilisearch" "meilisearch/meilisearch" "binary" "latest" "/opt/wanderer/source/search"
    grep -q -- '--experimental-dumpless-upgrade' /opt/wanderer/start.sh || sed -i 's|meilisearch --master-key|meilisearch --experimental-dumpless-upgrade --master-key|' /opt/wanderer/start.sh

    msg_info "Starting service"
    systemctl start wanderer-web
    msg_ok "Started service"
    msg_ok "Update Successful"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
