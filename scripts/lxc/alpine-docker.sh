#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.docker.com/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Alpine-Docker"
var_tags="${var_tags:-docker;alpine}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-alpine}"
var_version="${var_version:-3.23}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  ARCH=$(uname -m)

  msg_info "Installing Dependencies"
  $STD apk add tzdata openssl
  msg_ok "Installed Dependencies"

  msg_info "Installing Docker"
  $STD apk add docker
  $STD rc-update add docker
  msg_ok "Installed Docker"

  msg_info "Installing Docker Compose"
  DOCKER_COMPOSE_LATEST_VERSION=$(curl -fsSL https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | cut -d'"' -f4)
  mkdir -p ~/.docker/cli-plugins
  curl -fsSL "https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_LATEST_VERSION/docker-compose-linux-${ARCH}" -o ~/.docker/cli-plugins/docker-compose
  chmod +x ~/.docker/cli-plugins/docker-compose
  msg_ok "Installed Docker Compose"

  msg_info "Starting Docker"
  $STD rc-service docker start
  msg_ok "Started Docker"

  msg_info "Waiting for Docker"
  sleep 10
  $STD docker info
  msg_ok "Docker is running"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Alpine-Docker is ready. Use 'docker' commands inside the container.${CL}"
}

function update_script() {
  header_info
  msg_info "Updating $APP LXC"
  $STD apk -U upgrade
  msg_ok "Updated $APP LXC"

  msg_info "Updating Docker Compose"
  DOCKER_COMPOSE_LATEST_VERSION=$(curl -fsSL https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | cut -d'"' -f4)
  ARCH=$(uname -m)
  curl -fsSL "https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_LATEST_VERSION/docker-compose-linux-${ARCH}" -o ~/.docker/cli-plugins/docker-compose
  chmod +x ~/.docker/cli-plugins/docker-compose
  msg_ok "Updated Docker Compose"
  msg_ok "Updated successfully!"
  exit 0
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
