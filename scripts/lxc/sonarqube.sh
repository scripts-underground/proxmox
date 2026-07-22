#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: prop4n
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://docs.sonarsource.com/sonarqube-server

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="SonarQube"
var_tags="${var_tags:-automation}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-6144}"
var_disk="${var_disk:-25}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  JAVA_VERSION="21" setup_java
  PG_VERSION="17" setup_postgresql
  PG_DB_NAME="sonarqube" PG_DB_USER="sonarqube" setup_postgresql_db
  msg_ok "Installed Dependencies"

  msg_info "Setting up SonarQube"
  RELEASE=$(curl -s "https://binaries.sonarsource.com/s3api?prefix=Distribution/sonarqube/sonarqube-&delimiter=/" |
    grep -oP 'sonarqube-[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\.zip' |
    sort -V | tail -n1)
  fetch_and_deploy_from_url "https://binaries.sonarsource.com/Distribution/sonarqube/${RELEASE}" /opt/sonarqube
  $STD useradd -r -m -U -d /opt/sonarqube -s /bin/bash sonarqube
  chown -R sonarqube:sonarqube /opt/sonarqube
  chmod -R 755 /opt/sonarqube
  mkdir -p /opt/sonarqube/conf
  cat << EOF > /opt/sonarqube/conf/sonar.properties
sonar.jdbc.username=${PG_DB_USER}
sonar.jdbc.password=${PG_DB_PASS}
sonar.jdbc.url=jdbc:postgresql://localhost/${PG_DB_NAME}
sonar.web.host=0.0.0.0
sonar.web.port=9000
EOF
  chmod +x /opt/sonarqube/bin/linux-x86-64/sonar.sh
  echo ${RELEASE} >> ~/.sonarqube
  msg_ok "Configured SonarQube"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/sonarqube.service
[Unit]
Description=SonarQube service
After=postgresql.service

[Service]
Type=forking
ExecStart=/opt/sonarqube/bin/linux-x86-64/sonar.sh start
ExecStop=/opt/sonarqube/bin/linux-x86-64/sonar.sh stop
User=sonarqube
Group=sonarqube
Restart=on-failure
LimitNOFILE=131072
LimitNPROC=8192

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now sonarqube
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:9000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/sonarqube ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "sonarqube" "SonarSource/sonarqube"; then
    msg_info "Stopping Service"
    systemctl stop sonarqube
    msg_ok "Stopped Service"

    msg_info "Creating Backup"
    BACKUP_DIR="/opt/sonarqube-backup"
    mv /opt/sonarqube ${BACKUP_DIR}
    msg_ok "Created Backup"

    msg_info "Updating SonarQube"
    RELEASE=$(curl -s "https://binaries.sonarsource.com/s3api?prefix=Distribution/sonarqube/sonarqube-&delimiter=/" |
      grep -oP 'sonarqube-[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\.zip' |
      sort -V | tail -n1)
    fetch_and_deploy_from_url "https://binaries.sonarsource.com/Distribution/sonarqube/${RELEASE}" /opt/sonarqube
    echo "${RELEASE}" > ~/.sonarqube
    msg_ok "Updated SonarQube"

    msg_info "Restoring Backup"
    cp -rp ${BACKUP_DIR}/data/ /opt/sonarqube/data/
    cp -rp ${BACKUP_DIR}/extensions/ /opt/sonarqube/extensions/
    cp -p ${BACKUP_DIR}/conf/sonar.properties /opt/sonarqube/conf/sonar.properties
    rm -rf ${BACKUP_DIR}
    chown -R sonarqube:sonarqube /opt/sonarqube
    msg_ok "Restored Backup"

    msg_info "Starting Service"
    systemctl start sonarqube
    msg_ok "Service Started"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
