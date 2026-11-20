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
  NODE_VERSION="24" NODE_MAX_OLD_SPACE_SIZE="${NODE_MAX_OLD_SPACE_SIZE:-1536}" setup_nodejs
  setup_mariadb
  setup_yq
  MARIADB_DB_NAME="booklore_db" MARIADB_DB_USER="booklore_user" MARIADB_DB_EXTRA_GRANTS="GRANT SELECT ON \`mysql\`.\`time_zone_name\`" setup_mariadb_db
  local release_file app_version
  release_file=$(mktemp)
  fetch_and_deploy_gh_release "booklore" "booklore-app/BookLore" "tarball" "latest" "/opt/booklore" "" "" "$release_file"
  app_version=$(jq -er '.tag_name' "$release_file")
  rm -f -- "$release_file"

  msg_info "Building Frontend"
  cd /opt/booklore/booklore-ui || exit
  $STD npm ci --force
  # Angular's parallel TypeScript heaps exceed the default CT memory budget.
  NG_BUILD_MAX_WORKERS=1 NG_BUILD_PARALLEL_TS=0 $STD npm run build -- --configuration=production
  msg_ok "Built Frontend"

  msg_info "Embedding Frontend into Backend"
  mkdir -p /opt/booklore/booklore-api/src/main/resources/static
  cp -r /opt/booklore/booklore-ui/dist/booklore/browser/* /opt/booklore/booklore-api/src/main/resources/static/
  msg_ok "Embedded Frontend into Backend"

  msg_info "Creating Environment"
  mkdir -p /opt/booklore_storage/{data,books,bookdrop}
  local env_stage
  env_stage=$(mktemp /opt/booklore_storage/.env.XXXXXXXX)
  chown root:root "$env_stage"
  chmod 0600 "$env_stage"
  cat << EOF > "$env_stage"
# Database Configuration
DATABASE_URL=jdbc:mariadb://localhost:3306/${MARIADB_DB_NAME}
DATABASE_USERNAME=${MARIADB_DB_USER}
DATABASE_PASSWORD=${MARIADB_DB_PASS}

# App Configuration (Spring Boot mapping from app.* properties)
APP_PATH_CONFIG=/opt/booklore_storage/data
APP_BOOKDROP_FOLDER=/opt/booklore_storage/bookdrop
BOOKLORE_PORT=80
EOF
  mv -f -- "$env_stage" /opt/booklore_storage/.env
  msg_ok "Created Environment"

  msg_info "Building Backend"
  cd /opt/booklore/booklore-api || exit
  yq eval ".app.version = \"${app_version}\"" -i src/main/resources/application.yaml
  $STD ./gradlew clean build -x test --no-daemon
  mkdir -p /opt/booklore/dist
  JAR_PATH=$(find /opt/booklore/booklore-api/build/libs -maxdepth 1 -type f -name "booklore-api-*.jar" ! -name "*plain*" | head -n1)
  if [[ -z "$JAR_PATH" ]]; then
    msg_error "Backend JAR not found"
    exit 1
  fi
  local jar_stage
  jar_stage=$(mktemp /opt/booklore/dist/.app.jar.XXXXXXXX)
  if cp "$JAR_PATH" "$jar_stage" && chmod 0644 "$jar_stage" && mv -f -- "$jar_stage" /opt/booklore/dist/app.jar; then
    :
  else
    local status=$?
    rm -f -- "$jar_stage"
    return "$status"
  fi
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
    exit 1
  fi
  if [[ ! -f /opt/booklore_storage/.env ]]; then
    msg_error "BookLore environment is missing; restore the existing configuration before updating."
    exit 1
  fi
  # PID 1 reads EnvironmentFile; the service needs no public secret access.
  chown root:root /opt/booklore_storage/.env
  chmod 0600 /opt/booklore_storage/.env
  if [[ ! -s /opt/booklore/dist/app.jar ]]; then
    export UPDATE_FORCE=1 FORCE_DEPLOY=1
  fi

  if check_for_gh_release "booklore" "booklore-app/BookLore"; then
    JAVA_VERSION="25" setup_java
    NODE_VERSION="24" NODE_MAX_OLD_SPACE_SIZE="${NODE_MAX_OLD_SPACE_SIZE:-1536}" setup_nodejs
    setup_mariadb
    setup_yq

    msg_info "Stopping Service"
    systemctl stop booklore
    msg_ok "Stopped Service"

    # Retain operator values and the configured listener/proxy. Only add aliases
    # for the old path names when their replacement has not been configured.
    local old_key new_key line
    for old_key in BOOKLORE_DATA_PATH BOOKLORE_BOOKDROP_PATH; do
      case "$old_key" in
        BOOKLORE_DATA_PATH) new_key=APP_PATH_CONFIG ;;
        BOOKLORE_BOOKDROP_PATH) new_key=APP_BOOKDROP_FOLDER ;;
      esac
      if ! grep -q "^${new_key}=" /opt/booklore_storage/.env; then
        while IFS= read -r line || [[ -n "$line" ]]; do
          if [[ "$line" == "${old_key}="* ]]; then
            printf '\n%s=%s\n' "$new_key" "${line#*=}" >> /opt/booklore_storage/.env
          fi
        done < /opt/booklore_storage/.env
      fi
    done

    # The checked replacement owner retains the live root and installed JAR.
    # Failed builds stay failed/pending; a retry never nests an old backup.
    local -a CLEAN_INSTALL_KEEP_PATHS=("${CLEAN_INSTALL_KEEP_PATHS[@]}" dist)
    local release_file app_version
    release_file=$(mktemp)
    fetch_and_deploy_gh_release "booklore" "booklore-app/BookLore" "tarball" "$CHECK_UPDATE_RELEASE" "/opt/booklore" "" "" "$release_file"
    app_version=$(jq -er '.tag_name' "$release_file")
    rm -f -- "$release_file"

    msg_info "Building Frontend"
    cd /opt/booklore/booklore-ui || exit
    $STD npm ci --force
    NG_BUILD_MAX_WORKERS=1 NG_BUILD_PARALLEL_TS=0 $STD npm run build -- --configuration=production
    msg_ok "Built Frontend"

    msg_info "Embedding Frontend into Backend"
    mkdir -p /opt/booklore/booklore-api/src/main/resources/static
    cp -r /opt/booklore/booklore-ui/dist/booklore/browser/* /opt/booklore/booklore-api/src/main/resources/static/
    msg_ok "Embedded Frontend into Backend"

    msg_info "Building Backend"
    cd /opt/booklore/booklore-api || exit
    yq eval ".app.version = \"${app_version}\"" -i src/main/resources/application.yaml
    $STD ./gradlew clean build -x test --no-daemon
    mkdir -p /opt/booklore/dist
    JAR_PATH=$(find /opt/booklore/booklore-api/build/libs -maxdepth 1 -type f -name "booklore-api-*.jar" ! -name "*plain*" | head -n1)
    if [[ -z "$JAR_PATH" ]]; then
      msg_error "Backend JAR not found"
      exit 1
    fi
    local jar_stage
    jar_stage=$(mktemp /opt/booklore/dist/.app.jar.XXXXXXXX)
    if cp "$JAR_PATH" "$jar_stage" && chmod 0644 "$jar_stage" && mv -f -- "$jar_stage" /opt/booklore/dist/app.jar; then
      :
    else
      local status=$?
      rm -f -- "$jar_stage"
      return "$status"
    fi
    msg_ok "Built Backend"

    msg_info "Starting Service"
    systemctl start booklore
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  else
    local status=$?
    [[ "$status" == 1 ]] || return "$status"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc") --script-id "booklore" -- "$@"
