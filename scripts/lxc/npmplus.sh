#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/ZoeyVid/NPMplus

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="NPMplus"
var_tags="${var_tags:-proxy;nginx}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-3}"
var_os="${var_os:-alpine}"
var_version="${var_version:-3.23}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apk add \
    tzdata \
    gawk \
    yq
  msg_ok "Installed Dependencies"

  msg_info "Installing Docker & Compose"
  $STD apk add docker
  $STD rc-service docker start
  $STD rc-update add docker default

  get_latest_release() {
    curl -fsSL "https://api.github.com/repos/$1/releases/latest" | grep '"tag_name":' | cut -d'"' -f4
  }
  DOCKER_COMPOSE_LATEST_VERSION=$(get_latest_release "docker/compose")
  DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
  mkdir -p "$DOCKER_CONFIG/cli-plugins"
  curl -fsSL "https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_LATEST_VERSION/docker-compose-linux-$(uname -m)" -o "$DOCKER_CONFIG/cli-plugins/docker-compose"
  chmod +x "$DOCKER_CONFIG/cli-plugins/docker-compose"
  msg_ok "Installed Docker & Compose"

  msg_info "Fetching NPMplus"
  cd /opt || exit
  curl -fsSL "https://raw.githubusercontent.com/ZoeyVid/NPMplus/refs/heads/develop/compose.yaml" -o compose.yaml
  msg_ok "Fetched NPMplus"

  attempts=0
  while true; do
    read -r -p "${TAB3}Enter your TZ Identifier (e.g., Europe/Berlin): " TZ_INPUT
    if validate_tz "$TZ_INPUT"; then
      break
    fi
    msg_error "Invalid timezone! Please enter a valid TZ identifier."

    attempts=$((attempts + 1))
    if [[ "$attempts" -ge 3 ]]; then
      msg_error "Maximum attempts reached. Exiting."
      exit 254
    fi
  done

  read -r -p "${TAB3}Enter your ACME Email: " ACME_EMAIL_INPUT

  yq -i "
    .services.npmplus.environment |=
      (map(select(. != \"TZ=*\" and . != \"ACME_EMAIL=*\" and . != \"INITIAL_ADMIN_EMAIL=*\" and . != \"INITIAL_ADMIN_PASSWORD=*\")) +
      [\"TZ=$TZ_INPUT\", \"ACME_EMAIL=$ACME_EMAIL_INPUT\", \"INITIAL_ADMIN_EMAIL=admin@local.com\", \"INITIAL_ADMIN_PASSWORD=community-scripts.org\"])
  " /opt/compose.yaml

  msg_info "Building and Starting NPMplus (Patience)"
  $STD docker compose up -d
  CONTAINER_ID=""
  for i in {1..60}; do
    CONTAINER_ID=$(docker ps --filter "name=npmplus" --format "{{.ID}}")
    if [[ -n "$CONTAINER_ID" ]]; then
      STATUS=$(docker inspect --format '{{.State.Health.Status}}' "$CONTAINER_ID" 2> /dev/null || echo "starting")
      if [[ "$STATUS" == "healthy" ]]; then
        msg_ok "NPMplus is running and healthy"
        break
      elif [[ "$STATUS" == "unhealthy" ]]; then
        msg_error "NPMplus container is unhealthy! Check logs."
        docker logs "$CONTAINER_ID"
        exit 150
      fi
    fi
    sleep 2
    [[ $i -eq 60 ]] && msg_error "NPMplus container did not become healthy within 120s." && docker logs "$CONTAINER_ID" && exit 150
  done
  msg_ok "Builded and started NPMplus"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}https://${IP}:81${CL}"
}

function update_script() {
  header_info

  msg_info "Updating Alpine OS"
  $STD apk -U upgrade
  msg_ok "System updated"

  msg_info "Pulling latest NPMplus container image"
  cd /opt || exit
  $STD docker compose pull
  msg_info "Recreating container"
  $STD docker compose up -d
  msg_ok "Updated NPMplus container"

  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
