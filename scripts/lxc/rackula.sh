#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: gVNS (ggfevans)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/RackulaLives/Rackula

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Rackula"
var_tags="${var_tags:-homelab}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y nginx
  msg_ok "Installed Dependencies"

  msg_info "Installing Bun"
  export BUN_INSTALL="/opt/bun"
  curl -fsSL https://bun.sh/install | $STD bash
  ln -sf /opt/bun/bin/bun /usr/local/bin/bun
  msg_ok "Installed Bun"

  fetch_and_deploy_gh_release "rackula" "RackulaLives/Rackula" "prebuild" "latest" "/opt/rackula" "rackula-lxc-*.tar.gz"

  msg_info "Setting up Rackula"
  mkdir -p /opt/rackula/data /etc/nginx/snippets
  SECURITY_HEADERS_SRC="/opt/rackula/config/security-headers.conf"
  cp "$SECURITY_HEADERS_SRC" /etc/nginx/snippets/security-headers.conf
  chown -R root:root /opt/rackula/frontend
  find /opt/rackula/frontend -type d -exec chmod 755 {} \;
  find /opt/rackula/frontend -type f -exec chmod 644 {} \;
  chmod 750 /opt/rackula/data

  API_WRITE_TOKEN=$(openssl rand -hex 32)
  cat << EOF > /opt/rackula/data/.env
RACKULA_API_WRITE_TOKEN=${API_WRITE_TOKEN}
CORS_ORIGIN=http://localhost
ALLOW_INSECURE_CORS=false
EOF
  chmod 600 /opt/rackula/data/.env

  cat << EOF > /etc/nginx/snippets/rackula-api-token.conf
map \$host \$rackula_api_write_token {
  default "${API_WRITE_TOKEN}";
}
map \$host \$rackula_has_api_write_token {
  default 1;
}
EOF
  chmod 640 /etc/nginx/snippets/rackula-api-token.conf
  msg_ok "Set up Rackula"

  msg_info "Configuring nginx"
  cp /opt/rackula/config/nginx.conf /etc/nginx/sites-available/rackula
  rm -f /etc/nginx/sites-enabled/default
  ln -sf /etc/nginx/sites-available/rackula /etc/nginx/sites-enabled/rackula
  $STD nginx -t
  msg_ok "Configured nginx"

  msg_info "Creating Services"
  cp /opt/rackula/config/rackula-api.service /etc/systemd/system/rackula-api.service
  if grep -q '^User=' /etc/systemd/system/rackula-api.service; then
    sed -i 's/^User=.*/User=root/' /etc/systemd/system/rackula-api.service
  else
    sed -i '/^\[Service\]/a User=root' /etc/systemd/system/rackula-api.service
  fi
  if grep -q '^Group=' /etc/systemd/system/rackula-api.service; then
    sed -i 's/^Group=.*/Group=root/' /etc/systemd/system/rackula-api.service
  else
    sed -i '/^\[Service\]/a Group=root' /etc/systemd/system/rackula-api.service
  fi
  mkdir -p /etc/systemd/system/nginx.service.d
  cp /opt/rackula/config/nginx.service.d-override.conf /etc/systemd/system/nginx.service.d/override.conf
  systemctl daemon-reload
  systemctl enable -q nginx rackula-api
  systemctl restart nginx rackula-api
  msg_ok "Created Services"
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

  if [[ ! -d /opt/rackula ]]; then
    msg_error "No ${APP} Installation Found!"
    exit 1
  fi

  if check_for_gh_release "rackula" "RackulaLives/Rackula"; then
    msg_info "Stopping Services"
    systemctl stop rackula-api nginx
    msg_ok "Stopped Services"

    create_backup /opt/rackula/data
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "rackula" "RackulaLives/Rackula" "prebuild" "latest" "/opt/rackula" "rackula-lxc-*.tar.gz"
    restore_backup

    msg_info "Updating Configuration"
    cp /opt/rackula/config/nginx.conf /etc/nginx/sites-available/rackula
    cp /opt/rackula/config/security-headers.conf /etc/nginx/snippets/security-headers.conf
    cp /opt/rackula/config/rackula-api.service /etc/systemd/system/rackula-api.service
    if grep -q '^User=' /etc/systemd/system/rackula-api.service; then
      sed -i 's/^User=.*/User=root/' /etc/systemd/system/rackula-api.service
    else
      sed -i '/^\[Service\]/a User=root' /etc/systemd/system/rackula-api.service
    fi
    if grep -q '^Group=' /etc/systemd/system/rackula-api.service; then
      sed -i 's/^Group=.*/Group=root/' /etc/systemd/system/rackula-api.service
    else
      sed -i '/^\[Service\]/a Group=root' /etc/systemd/system/rackula-api.service
    fi
    mkdir -p /etc/systemd/system/nginx.service.d
    cp /opt/rackula/config/nginx.service.d-override.conf /etc/systemd/system/nginx.service.d/override.conf
    chown -R root:root /opt/rackula/frontend
    find /opt/rackula/frontend -type d -exec chmod 755 {} \;
    find /opt/rackula/frontend -type f -exec chmod 644 {} \;
    chmod 750 /opt/rackula/data
    msg_ok "Updated Configuration"

    msg_info "Starting Services"
    $STD nginx -t
    systemctl daemon-reload
    systemctl start nginx rackula-api
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
