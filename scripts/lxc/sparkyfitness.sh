#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Tom Frenzel (tomfrenzel)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/CodeWithCJ/SparkyFitness

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="SparkyFitness"
var_tags="${var_tags:-health;fitness}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-7}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y nginx
  msg_ok "Installed Dependencies"

  PG_VERSION="18" setup_postgresql
  PG_DB_NAME="sparkyfitness" PG_DB_USER="sparky" PG_DB_GRANT_SUPERUSER="true" setup_postgresql_db

  fetch_and_deploy_gh_release sparkyfitness "CodeWithCJ/SparkyFitness" "tarball" "latest"

  PNPM_VERSION="$(jq -r '.packageManager | split("@")[1]' /opt/sparkyfitness/package.json)"
  NODE_VERSION="25" NODE_MODULE="pnpm@${PNPM_VERSION}" setup_nodejs

  msg_info "Configuring Sparky Fitness"
  mkdir -p "/etc/sparkyfitness" "/var/lib/sparkyfitness/uploads" "/var/lib/sparkyfitness/backup" "/var/www/sparkyfitness"
  cp "/opt/sparkyfitness/docker/.env.example" "/etc/sparkyfitness/.env"
  sed \
    -i \
    -e "s|^#\?SPARKY_FITNESS_DB_HOST=.*|SPARKY_FITNESS_DB_HOST=localhost|" \
    -e "s|^#\?SPARKY_FITNESS_DB_PORT=.*|SPARKY_FITNESS_DB_PORT=5432|" \
    -e "s|^SPARKY_FITNESS_DB_NAME=.*|SPARKY_FITNESS_DB_NAME=sparkyfitness|" \
    -e "s|^SPARKY_FITNESS_DB_USER=.*|SPARKY_FITNESS_DB_USER=sparky|" \
    -e "s|^SPARKY_FITNESS_DB_PASSWORD=.*|SPARKY_FITNESS_DB_PASSWORD=${PG_DB_PASS}|" \
    -e "s|^SPARKY_FITNESS_APP_DB_USER=.*|SPARKY_FITNESS_APP_DB_USER=sparky_app|" \
    -e "s|^SPARKY_FITNESS_APP_DB_PASSWORD=.*|SPARKY_FITNESS_APP_DB_PASSWORD=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c20)|" \
    -e "s|^SPARKY_FITNESS_SERVER_HOST=.*|SPARKY_FITNESS_SERVER_HOST=localhost|" \
    -e "s|^SPARKY_FITNESS_SERVER_PORT=.*|SPARKY_FITNESS_SERVER_PORT=3010|" \
    -e "s|^SPARKY_FITNESS_FRONTEND_URL=.*|SPARKY_FITNESS_FRONTEND_URL=http://${LOCAL_IP}:80|" \
    -e "s|^GARMIN_MICROSERVICE_URL=.*|GARMIN_MICROSERVICE_URL=http://${LOCAL_IP}:8000|" \
    -e "s|^SPARKY_FITNESS_API_ENCRYPTION_KEY=.*|SPARKY_FITNESS_API_ENCRYPTION_KEY=$(openssl rand -hex 32)|" \
    -e "s|^BETTER_AUTH_SECRET=.*|BETTER_AUTH_SECRET=$(openssl rand -hex 32)|" \
    "/etc/sparkyfitness/.env"
  msg_ok "Configured Sparky Fitness"

  msg_info "Building Backend"
  cd /opt/sparkyfitness/SparkyFitnessServer || exit
  $STD pnpm install
  msg_ok "Built Backend"

  msg_info "Building Frontend (Patience)"
  cd /opt/sparkyfitness || exit
  $STD pnpm install
  cd /opt/sparkyfitness/SparkyFitnessFrontend || exit
  $STD pnpm run build
  cp -a /opt/sparkyfitness/SparkyFitnessFrontend/dist/. /var/www/sparkyfitness/
  msg_ok "Built Frontend"

  msg_info "Creating SparkyFitness Service"
  cat << EOF > /etc/systemd/system/sparkyfitness-server.service
[Unit]
Description=SparkyFitness Backend Service
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
WorkingDirectory=/opt/sparkyfitness/SparkyFitnessServer
EnvironmentFile=/etc/sparkyfitness/.env
ExecStart=/opt/sparkyfitness/SparkyFitnessServer/node_modules/.bin/tsx SparkyFitnessServer.js
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now sparkyfitness-server
  msg_ok "Created SparkyFitness Service"

  msg_info "Configuring Nginx"
  sed \
    -e 's|${SPARKY_FITNESS_SERVER_HOST}|127.0.0.1|g' \
    -e 's|${SPARKY_FITNESS_SERVER_PORT}|3010|g' \
    -e 's|${NGINX_LISTEN_PORT}|80|g' \
    -e 's|${NGINX_ACCESS_LOG}|/var/log/nginx/sparkyfitness.access.log|g' \
    -e 's|${NGINX_ERROR_LOG}|/var/log/nginx/sparkyfitness.error.log|g' \
    -e 's|root /usr/share/nginx/html;|root /var/www/sparkyfitness;|g' \
    -e 's|server_name localhost;|server_name _;|g' \
    "/opt/sparkyfitness/docker/nginx.conf" > /etc/nginx/sites-available/sparkyfitness
  ln -sf /etc/nginx/sites-available/sparkyfitness /etc/nginx/sites-enabled/sparkyfitness
  rm -f /etc/nginx/sites-enabled/default
  $STD nginx -t
  $STD systemctl enable -q --now nginx
  $STD systemctl reload nginx
  msg_ok "Configured Nginx"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/sparkyfitness ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "sparkyfitness" "CodeWithCJ/SparkyFitness"; then
    msg_info "Stopping Services"
    systemctl stop sparkyfitness-server nginx
    msg_ok "Stopped Services"

    msg_info "Creating Backup"
    cp -a /opt/sparkyfitness/SparkyFitnessServer/uploads /opt/sparkyfitness_uploads_backup
    cp -a /opt/sparkyfitness/SparkyFitnessServer/backup /opt/sparkyfitness_backup_backup
    msg_ok "Created Backup"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "sparkyfitness" "CodeWithCJ/SparkyFitness" "tarball"

    msg_info "Restoring Backup"
    rm -rf /opt/sparkyfitness/SparkyFitnessServer/uploads /opt/sparkyfitness/SparkyFitnessServer/backup
    mv /opt/sparkyfitness_uploads_backup /opt/sparkyfitness/SparkyFitnessServer/uploads
    mv /opt/sparkyfitness_backup_backup /opt/sparkyfitness/SparkyFitnessServer/backup
    msg_ok "Restored Backup"

    PNPM_VERSION="$(jq -r '.packageManager | split("@")[1]' /opt/sparkyfitness/package.json)"
    NODE_VERSION="25" NODE_MODULE="pnpm@${PNPM_VERSION}" setup_nodejs

    msg_info "Updating Sparky Fitness Backend"
    cd /opt/sparkyfitness/SparkyFitnessServer || exit
    $STD pnpm install
    msg_ok "Updated Sparky Fitness Backend"

    msg_info "Updating Sparky Fitness Frontend (Patience)"
    cd /opt/sparkyfitness || exit
    $STD pnpm install
    cd /opt/sparkyfitness/SparkyFitnessFrontend || exit
    $STD pnpm run build
    cp -a /opt/sparkyfitness/SparkyFitnessFrontend/dist/. /var/www/sparkyfitness/
    msg_ok "Updated Sparky Fitness Frontend"

    msg_info "Refreshing Nginx Config"
    sed \
      -e 's|${SPARKY_FITNESS_SERVER_HOST}|127.0.0.1|g' \
      -e 's|${SPARKY_FITNESS_SERVER_PORT}|3010|g' \
      -e 's|${NGINX_LISTEN_PORT}|80|g' \
      -e 's|${NGINX_ACCESS_LOG}|/var/log/nginx/sparkyfitness.access.log|g' \
      -e 's|${NGINX_ERROR_LOG}|/var/log/nginx/sparkyfitness.error.log|g' \
      -e 's|root /usr/share/nginx/html;|root /var/www/sparkyfitness;|g' \
      -e 's|server_name localhost;|server_name _;|g' \
      "/opt/sparkyfitness/docker/nginx.conf" > /etc/nginx/sites-available/sparkyfitness
    msg_ok "Refreshed Nginx Config"

    msg_info "Refreshing SparkyFitness Service"
    cat << EOF > /etc/systemd/system/sparkyfitness-server.service
[Unit]
Description=SparkyFitness Backend Service
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
WorkingDirectory=/opt/sparkyfitness/SparkyFitnessServer
EnvironmentFile=/etc/sparkyfitness/.env
ExecStart=/opt/sparkyfitness/SparkyFitnessServer/node_modules/.bin/tsx SparkyFitnessServer.js
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    msg_ok "Refreshed SparkyFitness Service"

    msg_info "Starting Services"
    $STD systemctl start sparkyfitness-server nginx
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
