#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.meilisearch.com/

# shellcheck disable=SC2034
APP="Meilisearch"
var_tags="${var_tags:-full-text-search}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-7}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  MEILISEARCH_BIND="0.0.0.0:7700" setup_meilisearch

  read -r -p "${TAB3}Would you like to add meilisearch-ui? <y/N> " prompt
  if [[ ${prompt,,} =~ ^(y|yes)$ ]]; then
    NODE_VERSION="22" NODE_MODULE="pnpm@latest" setup_nodejs
    fetch_and_deploy_gh_release "meilisearch-ui" "riccox/meilisearch-ui" "tarball"

    msg_info "Configuring Meilisearch-UI"
    cd /opt/meilisearch-ui || exit
    sed -i 's|const hash = execSync("git rev-parse HEAD").toString().trim();|const hash = "unknown";|' /opt/meilisearch-ui/vite.config.ts
    $STD pnpm install
    cat << EOF > /opt/meilisearch-ui/.env.local
VITE_SINGLETON_MODE=true
VITE_SINGLETON_HOST=http://${LOCAL_IP}:7700
VITE_SINGLETON_API_KEY=${MEILISEARCH_MASTER_KEY}
EOF
    msg_ok "Configured Meilisearch-UI"

    msg_info "Creating Meilisearch-UI Service"
    cat << EOF > /etc/systemd/system/meilisearch-ui.service
[Unit]
Description=Meilisearch UI Service
After=network.target meilisearch.service
Requires=meilisearch.service

[Service]
User=root
WorkingDirectory=/opt/meilisearch-ui
ExecStart=/usr/bin/pnpm start
Restart=always
RestartSec=5
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=meilisearch-ui

[Install]
WantedBy=multi-user.target
EOF
    systemctl enable -q --now meilisearch-ui
    msg_ok "Created Meilisearch-UI Service"
  fi
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}meilisearch: http://${IP}:7700 | meilisearch-ui: http://${IP}:24900${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  setup_meilisearch

  if [[ -d /opt/meilisearch-ui ]]; then
    if check_for_gh_release "meilisearch-ui" "riccox/meilisearch-ui"; then
      msg_info "Stopping Meilisearch-UI"
      systemctl stop meilisearch-ui
      msg_ok "Stopped Meilisearch-UI"

      cp /opt/meilisearch-ui/.env.local /tmp/.env.local.bak
      rm -rf /opt/meilisearch-ui
      fetch_and_deploy_gh_release "meilisearch-ui" "riccox/meilisearch-ui" "tarball"

      msg_info "Configuring Meilisearch-UI"
      cd /opt/meilisearch-ui || exit
      sed -i 's|const hash = execSync("git rev-parse HEAD").toString().trim();|const hash = "unknown";|' /opt/meilisearch-ui/vite.config.ts
      mv /tmp/.env.local.bak /opt/meilisearch-ui/.env.local
      $STD pnpm install
      msg_ok "Configured Meilisearch-UI"

      msg_info "Starting Meilisearch-UI"
      systemctl start meilisearch-ui
      msg_ok "Started Meilisearch-UI"
    fi
  fi

  msg_ok "Updated successfully!"
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
