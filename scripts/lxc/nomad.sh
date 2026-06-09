#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"
source <(curl -fsSL "$REPO_BASE/misc/build.func")

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Alex Indigo (alexindigo)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/Crosstalk-Solutions/project-nomad | https://www.projectnomad.us

APP="Nomad"
var_tags="${var_tags:-offline;knowledge;education;ai}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-16}"
var_port="${var_port:-80}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_gpu="${var_gpu:-yes}"
var_nesting="${var_nesting:-1}"
var_keyctl="${var_keyctl:-1}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/project-nomad ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "nomad" "Crosstalk-Solutions/project-nomad"; then
    msg_info "Updating Nomad"
    cd /opt/project-nomad

    APP_KEY=$(grep 'APP_KEY=' /opt/project-nomad/compose.yml | head -1 | sed 's/.*APP_KEY=//')
    DB_PASS=$(grep 'DB_PASSWORD=' /opt/project-nomad/compose.yml | head -1 | sed 's/.*DB_PASSWORD=//')
    DB_ROOT_PASS=$(grep 'MYSQL_ROOT_PASSWORD=' /opt/project-nomad/compose.yml | head -1 | sed 's/.*MYSQL_ROOT_PASSWORD=//')
    DB_USER_PASS=$(grep 'MYSQL_PASSWORD=' /opt/project-nomad/compose.yml | head -1 | sed 's/.*MYSQL_PASSWORD=//')
    NOMAD_URL=$(grep 'URL=' /opt/project-nomad/compose.yml | head -1 | sed 's/.*URL=//')

    fetch_and_deploy_gh_release "nomad" "Crosstalk-Solutions/project-nomad" "tarball"

    cp /opt/nomad/install/management_compose.yaml /opt/project-nomad/compose.yml
    cp /opt/nomad/install/start_nomad.sh /opt/project-nomad/start_nomad.sh
    cp /opt/nomad/install/stop_nomad.sh /opt/project-nomad/stop_nomad.sh
    cp /opt/nomad/install/update_nomad.sh /opt/project-nomad/update_nomad.sh
    chmod +x /opt/project-nomad/*.sh

    sed -i "s|URL=replaceme|URL=${NOMAD_URL}|g" /opt/project-nomad/compose.yml
    [[ -n "$APP_KEY" ]] && sed -i "s|APP_KEY=replaceme|APP_KEY=${APP_KEY}|g" /opt/project-nomad/compose.yml
    [[ -n "$DB_PASS" ]] && sed -i "s|DB_PASSWORD=replaceme|DB_PASSWORD=${DB_PASS}|g" /opt/project-nomad/compose.yml
    [[ -n "$DB_ROOT_PASS" ]] && sed -i "s|MYSQL_ROOT_PASSWORD=replaceme|MYSQL_ROOT_PASSWORD=${DB_ROOT_PASS}|g" /opt/project-nomad/compose.yml
    [[ -n "$DB_USER_PASS" ]] && sed -i "s|MYSQL_PASSWORD=replaceme|MYSQL_PASSWORD=${DB_USER_PASS}|g" /opt/project-nomad/compose.yml
    sed -i 's|"8080:8080"|"80:8080"|g' /opt/project-nomad/compose.yml

    $STD docker compose pull
    $STD docker compose up -d --force-recreate
    msg_ok "Updated Successfully"
  fi
  exit
}

function install_script() {
  NOMAD_DIR="/opt/project-nomad"

  echo ""
  echo "License Agreement & Terms of Use"
  echo "__________________________"
  echo ""
  echo "Project N.O.M.A.D. is licensed under the Apache License 2.0."
  echo "Full license: https://www.apache.org/licenses/LICENSE-2.0"
  echo ""
  read -p "I have read and accept License Agreement & Terms of Use (y/N)? " choice
  case "$choice" in
    y|Y )
      echo "License accepted."
      ;;
    * )
      msg_error "License not accepted. Installation cannot continue."
      exit 1
      ;;
  esac

  USE_DOCKER_REPO=true setup_docker
  setup_hwaccel

  if command -v nvidia-smi &>/dev/null || lspci 2>/dev/null | grep -qi nvidia; then
    if ! command -v nvidia-ctk &>/dev/null; then
      msg_info "Installing NVIDIA Container Toolkit"
      curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg 2>/dev/null || true
      curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list 2>/dev/null \
        | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
        | tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null 2>&1 || true
      $STD apt update 2>/dev/null || true
      $STD apt install -y nvidia-container-toolkit 2>/dev/null || true
      if command -v nvidia-ctk &>/dev/null; then
        nvidia-ctk runtime configure --runtime=docker 2>/dev/null || true
        systemctl restart docker 2>/dev/null || true
      fi
      msg_ok "NVIDIA Container Toolkit configured"
    fi
  fi

  fetch_and_deploy_gh_release "nomad" "Crosstalk-Solutions/project-nomad" "tarball"

  msg_info "Setting up Nomad"
  mkdir -p ${NOMAD_DIR}/storage/logs
  cp /opt/nomad/install/management_compose.yaml ${NOMAD_DIR}/compose.yml
  cp /opt/nomad/install/start_nomad.sh ${NOMAD_DIR}/start_nomad.sh
  cp /opt/nomad/install/stop_nomad.sh ${NOMAD_DIR}/stop_nomad.sh
  cp /opt/nomad/install/update_nomad.sh ${NOMAD_DIR}/update_nomad.sh
  chmod +x ${NOMAD_DIR}/*.sh

  APP_KEY=$(openssl rand -base64 18 | tr -dc 'A-Za-z0-9' | head -c32)
  DB_ROOT_PASSWORD=$(openssl rand -base64 18 | tr -dc 'A-Za-z0-9' | head -c13)
  DB_USER_PASSWORD=$(openssl rand -base64 18 | tr -dc 'A-Za-z0-9' | head -c13)

  sed -i "s|URL=replaceme|URL=http://${LOCAL_IP}|g" ${NOMAD_DIR}/compose.yml
  sed -i "s|APP_KEY=replaceme|APP_KEY=${APP_KEY}|g" ${NOMAD_DIR}/compose.yml
  sed -i "s|DB_PASSWORD=replaceme|DB_PASSWORD=${DB_USER_PASSWORD}|g" ${NOMAD_DIR}/compose.yml
  sed -i "s|MYSQL_ROOT_PASSWORD=replaceme|MYSQL_ROOT_PASSWORD=${DB_ROOT_PASSWORD}|g" ${NOMAD_DIR}/compose.yml
  sed -i "s|MYSQL_PASSWORD=replaceme|MYSQL_PASSWORD=${DB_USER_PASSWORD}|g" ${NOMAD_DIR}/compose.yml
  sed -i 's|"8080:8080"|"80:8080"|g' ${NOMAD_DIR}/compose.yml
  msg_ok "Set up Nomad"

  msg_info "Starting Nomad"
  cd ${NOMAD_DIR}
  $STD docker compose up -d
  msg_ok "Started Nomad"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
}

source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
