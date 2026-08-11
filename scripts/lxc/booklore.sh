#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/booklore-app/BookLore

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="BookLore"
var_tags="${var_tags:-books;library}"
var_cpu="${var_cpu:-3}"
var_ram="${var_ram:-3072}"
var_disk="${var_disk:-7}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  JAVA_VERSION="25" setup_java
  NODE_VERSION="24" setup_nodejs
  setup_mariadb
  setup_yq
  MARIADB_DB_NAME="booklore_db" MARIADB_DB_USER="booklore_user" MARIADB_DB_EXTRA_GRANTS="GRANT SELECT ON \`mysql\`.\`time_zone_name\`" setup_mariadb_db
  fetch_and_deploy_gh_release "booklore" "booklore-app/BookLore" "tarball"

  msg_info "Building Frontend"
  cd /opt/booklore/booklore-ui || exit
  $STD npm ci --force
  $STD npm run build --configuration=production
  msg_ok "Built Frontend"

  msg_info "Embedding Frontend into Backend"
  mkdir -p /opt/booklore/booklore-api/src/main/resources/static
  cp -r /opt/booklore/booklore-ui/dist/booklore/browser/* /opt/booklore/booklore-api/src/main/resources/static/
  msg_ok "Embedded Frontend into Backend"

  msg_info "Creating Environment"
  mkdir -p /opt/booklore_storage/{data,books,bookdrop}
  cat << EOF > /opt/booklore_storage/.env
# Database Configuration
DATABASE_URL=jdbc:mariadb://localhost:3306/${MARIADB_DB_NAME}
DATABASE_USERNAME=${MARIADB_DB_USER}
DATABASE_PASSWORD=${MARIADB_DB_PASS}

# App Configuration (Spring Boot mapping from app.* properties)
APP_PATH_CONFIG=/opt/booklore_storage/data
APP_BOOKDROP_FOLDER=/opt/booklore_storage/bookdrop
BOOKLORE_PORT=80
EOF
  msg_ok "Created Environment"

  msg_info "Building Backend"
  cd /opt/booklore/booklore-api || exit
  APP_VERSION=$(get_latest_github_release "booklore-app/BookLore")
  yq eval ".app.version = \"${APP_VERSION}\"" -i src/main/resources/application.yaml
  $STD ./gradlew clean build -x test --no-daemon
  mkdir -p /opt/booklore/dist
  JAR_PATH=$(find /opt/booklore/booklore-api/build/libs -maxdepth 1 -type f -name "booklore-api-*.jar" ! -name "*plain*" | head -n1)
  if [[ -z "$JAR_PATH" ]]; then
    msg_error "Backend JAR not found"
    exit 1
  fi
  cp "$JAR_PATH" /opt/booklore/dist/app.jar
  msg_ok "Built Backend"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/booklore.service
[Unit]
Description=BookLore Java Service
After=network.target mariadb.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/booklore/dist
ExecStart=/usr/bin/java -XX:+UseG1GC -XX:+UseStringDeduplication -XX:+UseCompactObjectHeaders -jar /opt/booklore/dist/app.jar
EnvironmentFile=/opt/booklore_storage/.env
SuccessExitStatus=143
TimeoutStopSec=10
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now booklore
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/booklore ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "booklore" "booklore-app/BookLore"; then
    JAVA_VERSION="25" setup_java
    NODE_VERSION="24" setup_nodejs
    setup_mariadb
    setup_yq

    msg_info "Stopping Service"
    systemctl stop booklore
    msg_ok "Stopped Service"

    if grep -qE "^BOOKLORE_(DATA_PATH|BOOKDROP_PATH|BOOKS_PATH|PORT)=" /opt/booklore_storage/.env 2> /dev/null; then
      msg_info "Migrating old environment variables"
      sed -i 's/^BOOKLORE_DATA_PATH=/APP_PATH_CONFIG=/g' /opt/booklore_storage/.env
      sed -i 's/^BOOKLORE_BOOKDROP_PATH=/APP_BOOKDROP_FOLDER=/g' /opt/booklore_storage/.env
      sed -i '/^BOOKLORE_BOOKS_PATH=/d' /opt/booklore_storage/.env
      sed -i '/^BOOKLORE_PORT=/d' /opt/booklore_storage/.env
      msg_ok "Migrated old environment variables"
    fi

    msg_info "Backing up old installation"
    mv /opt/booklore /opt/booklore_bak
    msg_ok "Backed up old installation"

    fetch_and_deploy_gh_release "booklore" "booklore-app/BookLore" "tarball"

    msg_info "Building Frontend"
    cd /opt/booklore/booklore-ui || exit
    $STD npm ci --force
    $STD npm run build --configuration=production
    msg_ok "Built Frontend"

    msg_info "Embedding Frontend into Backend"
    mkdir -p /opt/booklore/booklore-api/src/main/resources/static
    cp -r /opt/booklore/booklore-ui/dist/booklore/browser/* /opt/booklore/booklore-api/src/main/resources/static/
    msg_ok "Embedded Frontend into Backend"

    msg_info "Building Backend"
    cd /opt/booklore/booklore-api || exit
    APP_VERSION=$(get_latest_github_release "booklore-app/BookLore")
    yq eval ".app.version = \"${APP_VERSION}\"" -i src/main/resources/application.yaml
    $STD ./gradlew clean build -x test --no-daemon
    mkdir -p /opt/booklore/dist
    JAR_PATH=$(find /opt/booklore/booklore-api/build/libs -maxdepth 1 -type f -name "booklore-api-*.jar" ! -name "*plain*" | head -n1)
    if [[ -z "$JAR_PATH" ]]; then
      msg_error "Backend JAR not found"
      exit
    fi
    cp "$JAR_PATH" /opt/booklore/dist/app.jar
    msg_ok "Built Backend"

    if systemctl is-active --quiet nginx 2> /dev/null; then
      msg_info "Removing Nginx (no longer needed)"
      systemctl disable --now nginx
      $STD apt-get purge -y nginx nginx-common
      msg_ok "Removed Nginx"
    fi

    if ! grep -q "^SERVER_PORT=" /opt/booklore_storage/.env 2> /dev/null; then
      echo "BOOKLORE_PORT=80" >> /opt/booklore_storage/.env
    fi

    sed -i 's|ExecStart=/usr/bin/java -jar|ExecStart=/usr/bin/java -XX:+UseG1GC -XX:+UseStringDeduplication -XX:+UseCompactObjectHeaders -jar|' /etc/systemd/system/booklore.service
    systemctl daemon-reload

    msg_info "Starting Service"
    systemctl start booklore
    rm -rf /opt/booklore_bak
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
