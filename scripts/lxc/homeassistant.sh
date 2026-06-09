#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"
source <(curl -fsSL "$REPO_BASE/misc/build.func")

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 tteck
# Author: tteck (tteckster)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://www.home-assistant.io/

APP="Home Assistant"
var_tags="${var_tags:-automation;smarthome}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-16}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /var/lib/docker/volumes/hass_config/_data ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  UPD=$(msg_menu "Home Assistant Update Options" \
    "1" "Update ALL Containers" \
    "2" "Remove ALL Unused Images" \
    "3" "Install HACS" \
    "4" "Install FileBrowser")

  if [ "$UPD" == "1" ]; then
    msg_info "Updating All Containers"
    CONTAINER_LIST="${1:-$(docker ps -q)}"
    for container in ${CONTAINER_LIST}; do
      CONTAINER_IMAGE="$(docker inspect --format "{{.Config.Image}}" --type container "${container}")"
      RUNNING_IMAGE="$(docker inspect --format "{{.Image}}" --type container "${container}")"
      docker pull "${CONTAINER_IMAGE}"
      LATEST_IMAGE="$(docker inspect --format "{{.Id}}" --type image "${CONTAINER_IMAGE}")"
      if [[ "${RUNNING_IMAGE}" != "${LATEST_IMAGE}" ]]; then
        pip install -U runlike
        echo "Updating ${container} image ${CONTAINER_IMAGE}"
        DOCKER_COMMAND="$(runlike --use-volume-id "${container}")"
        docker rm --force "${container}"
        eval "${DOCKER_COMMAND}"
      fi
    done
    msg_ok "Updated All Containers"
    exit
  fi
  if [ "$UPD" == "2" ]; then
    msg_info "Removing ALL Unused Images"
    docker image prune -af
    msg_ok "Removed ALL Unused Images"
    exit
  fi
  if [ "$UPD" == "3" ]; then
    msg_info "Installing Home Assistant Community Store (HACS)"
    $STD apt update
    cd /var/lib/docker/volumes/hass_config/_data
    $STD bash <(curl -fsSL https://get.hacs.xyz)
    msg_ok "Installed Home Assistant Community Store (HACS)"
    echo -e "\n Reboot Home Assistant and clear browser cache then Add HACS integration.\n"
    exit
  fi
  if [ "$UPD" == "4" ]; then
    msg_info "Installing FileBrowser"
    RELEASE=$(curl -fsSL https://api.github.com/repos/filebrowser/filebrowser/releases/latest | grep -o '"tag_name": ".*"' | sed 's/"//g' | sed 's/tag_name: //g')
    $STD curl -fsSL https://github.com/filebrowser/filebrowser/releases/download/v2.23.0/linux-amd64-filebrowser.tar.gz | tar -xzv -C /usr/local/bin
    $STD filebrowser config init -a '0.0.0.0'
    $STD filebrowser config set -a '0.0.0.0'
    $STD filebrowser users add admin community-scripts.org --perm.admin
    msg_ok "Installed FileBrowser"

    msg_info "Creating Service"
    service_path="/etc/systemd/system/filebrowser.service"
    echo "[Unit]
Description=Filebrowser
After=network-online.target
[Service]
User=root
WorkingDirectory=/root/
ExecStart=/usr/local/bin/filebrowser -r /
[Install]
WantedBy=default.target" >$service_path

    $STD systemctl enable --now filebrowser
    msg_ok "Created Service"

    msg_ok "Completed successfully!\n"
    echo -e "FileBrowser should be reachable by going to the following URL.
         ${BL}http://$LOCAL_IP:8080${CL}   admin|community-scripts.org\n"
    exit
  fi
}

function install_script() {
  color
  verb_ip6
  catch_errors
  setting_up_container
  network_check
  update_os

  msg_info "Setup Python3"
  $STD apt install -y \
    python3 \
    python3-dev \
    python3-pip \
    python3-venv
  rm -rf /usr/lib/python3.*/EXTERNALLY-MANAGED
  msg_ok "Setup Python3"

  msg_info "Installing runlike"
  $STD pip install runlike
  msg_ok "Installed runlike"

  get_latest_release() {
    curl -fsSL https://api.github.com/repos/$1/releases/latest | grep '"tag_name":' | cut -d'"' -f4
  }

  DOCKER_LATEST_VERSION=$(get_latest_release "moby/moby")
  CORE_LATEST_VERSION=$(get_latest_release "home-assistant/core")
  PORTAINER_LATEST_VERSION=$(get_latest_release "portainer/portainer")

  msg_info "Installing Docker $DOCKER_LATEST_VERSION"
  DOCKER_CONFIG_PATH='/etc/docker/daemon.json'
  mkdir -p $(dirname $DOCKER_CONFIG_PATH)
  echo -e '{\n  "log-driver": "journald"\n}' >/etc/docker/daemon.json
  $STD sh <(curl -fsSL https://get.docker.com)
  msg_ok "Installed Docker $DOCKER_LATEST_VERSION"

  msg_info "Pulling Portainer $PORTAINER_LATEST_VERSION Image"
  $STD docker pull portainer/portainer-ce:latest
  msg_ok "Pulled Portainer $PORTAINER_LATEST_VERSION Image"

  msg_info "Installing Portainer $PORTAINER_LATEST_VERSION"
  $STD docker volume create portainer_data
  $STD docker run -d \
    -p 8000:8000 \
    -p 9443:9443 \
    --name=portainer \
    --restart=always \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v portainer_data:/data \
    portainer/portainer-ce:latest
  msg_ok "Installed Portainer $PORTAINER_LATEST_VERSION"

  msg_info "Pulling Home Assistant $CORE_LATEST_VERSION Image"
  $STD docker pull ghcr.io/home-assistant/home-assistant:stable
  msg_ok "Pulled Home Assistant $CORE_LATEST_VERSION Image"

  msg_info "Installing Home Assistant $CORE_LATEST_VERSION"
  $STD docker volume create hass_config
  $STD docker run -d \
    --name homeassistant \
    --privileged \
    --restart unless-stopped \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v /dev:/dev \
    -v hass_config:/config \
    -v /etc/localtime:/etc/localtime:ro \
    --net=host \
    ghcr.io/home-assistant/home-assistant:stable
  mkdir /root/hass_config
  msg_ok "Installed Home Assistant $CORE_LATEST_VERSION"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}HA: http://${IP}:8123${CL}"
  echo -e "${GATEWAY}${BGN}Portainer: https://${IP}:9443${CL}"
}

source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
