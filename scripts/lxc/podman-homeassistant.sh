#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.home-assistant.io/

# shellcheck disable=SC2034
APP="Podman Home Assistant"
var_tags="${var_tags:-podman;smarthome}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-16}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  PORTAINER_LATEST_VERSION=$(get_latest_github_release "portainer/portainer")
  PORTAINER_AGENT_LATEST_VERSION=$(get_latest_github_release "portainer/agent")

  if $STD mount | grep 'on / type zfs' > /dev/null && echo "ZFS"; then
    msg_info "Enabling ZFS support."
    mkdir -p /etc/containers
    cat << 'EOF' > /usr/local/bin/overlayzfsmount
#!/bin/sh
exec /bin/mount -t overlay overlay "$@"
EOF
    chmod +x /usr/local/bin/overlayzfsmount
    cat << 'EOF' > /etc/containers/storage.conf
[storage]
driver = "overlay"
runroot = "/run/containers/storage"
graphroot = "/var/lib/containers/storage"

[storage.options]
pull_options = {enable_partial_images = "false", use_hard_links = "false", ostree_repos=""}
mount_program = "/usr/local/bin/overlayzfsmount"

[storage.options.overlay]
mountopt = "nodev"
EOF
  fi

  msg_info "Installing Podman"
  $STD apt install -y podman
  systemctl enable -q --now podman.socket
  echo -e 'unqualified-search-registries=["docker.io"]' >> /etc/containers/registries.conf
  msg_ok "Installed Podman"

  mkdir -p /etc/containers/systemd

  read -r -p "${TAB3}Would you like to add Portainer? <y/N> " prompt
  if [[ ${prompt,,} =~ ^(y|yes)$ ]]; then
    msg_info "Installing Portainer $PORTAINER_LATEST_VERSION"
    podman volume create portainer_data > /dev/null
    cat << EOF > /etc/containers/systemd/portainer.container
[Unit]
Description=Portainer Container
After=network-online.target

[Container]
Image=docker.io/portainer/portainer-ce:latest
ContainerName=portainer
PublishPort=8000:8000
PublishPort=9443:9443
Volume=/run/podman/podman.sock:/var/run/docker.sock
Volume=portainer_data:/data

[Service]
Restart=always

[Install]
WantedBy=default.target multi-user.target
EOF
    systemctl daemon-reload
    $STD systemctl start portainer
    msg_ok "Installed Portainer $PORTAINER_LATEST_VERSION"
  else
    read -r -p "${TAB3}Would you like to add the Portainer Agent? <y/N> " prompt
    if [[ ${prompt,,} =~ ^(y|yes)$ ]]; then
      msg_info "Installing Portainer agent $PORTAINER_AGENT_LATEST_VERSION"
      cat << EOF > /etc/containers/systemd/portainer-agent.container
[Unit]
Description=Portainer Agent Container
After=network-online.target

[Container]
Image=docker.io/portainer/agent:latest
ContainerName=portainer_agent
PublishPort=9001:9001
Volume=/run/podman/podman.sock:/var/run/docker.sock
Volume=/var/lib/containers/storage/volumes:/var/lib/docker/volumes

[Service]
Restart=always

[Install]
WantedBy=default.target multi-user.target
EOF
      systemctl daemon-reload
      $STD systemctl start portainer-agent
      msg_ok "Installed Portainer Agent $PORTAINER_AGENT_LATEST_VERSION"
    fi
  fi

  msg_info "Pulling Home Assistant Image"
  $STD podman pull docker.io/homeassistant/home-assistant:stable
  msg_ok "Pulled Home Assistant Image"

  msg_info "Installing Home Assistant"
  $STD podman volume create hass_config
  cat << EOF > /etc/containers/systemd/homeassistant.container
[Unit]
Description=Home Assistant Container
After=network-online.target

[Container]
Image=docker.io/homeassistant/home-assistant:stable
ContainerName=homeassistant
Volume=/dev:/dev
Volume=hass_config:/config
Volume=/etc/localtime:/etc/localtime:ro
Volume=/etc/timezone:/etc/timezone:ro
Network=host

[Service]
Restart=always
TimeoutStartSec=300

[Install]
WantedBy=default.target multi-user.target
EOF
  systemctl daemon-reload
  $STD systemctl start homeassistant
  msg_ok "Installed Home Assistant"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8123${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /etc/containers/systemd/homeassistant.container ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  UPD=$(msg_menu "Home Assistant Update Options" \
    "1" "Update system and containers" \
    "2" "Install HACS" \
    "3" "Install FileBrowser" \
    "4" "Remove ALL Unused Images")

  if [ "$UPD" == "1" ]; then
    msg_info "Updating ${APP} LXC"
    $STD apt update
    $STD apt upgrade -y
    msg_ok "Updated successfully!"

    msg_info "Updating All Containers\n"
    CONTAINER_LIST="${1:-$(podman ps -q)}"
    for container in ${CONTAINER_LIST}; do
      CONTAINER_IMAGE="$(podman inspect --format "{{.Config.Image}}" --type container ${container})"
      RUNNING_IMAGE="$(podman inspect --format "{{.Image}}" --type container "${container}")"
      podman pull "${CONTAINER_IMAGE}"
      LATEST_IMAGE="$(podman inspect --format "{{.Id}}" --type image "${CONTAINER_IMAGE}")"
      if [[ "${RUNNING_IMAGE}" != "${LATEST_IMAGE}" ]]; then
        echo "Updating ${container} image ${CONTAINER_IMAGE}"
        systemctl restart homeassistant
      fi
    done
    msg_ok "All containers updated."
    exit
  fi
  if [ "$UPD" == "2" ]; then
    msg_info "Installing Home Assistant Community Store (HACS)"
    $STD apt update
    cd /var/lib/containers/storage/volumes/hass_config/_data || exit
    $STD bash <(curl -fsSL https://get.hacs.xyz)
    msg_ok "Installed Home Assistant Community Store (HACS)"
    echo -e "\n Reboot Home Assistant and clear browser cache then Add HACS integration.\n"
    exit
  fi
  if [ "$UPD" == "3" ]; then
    msg_info "Installing FileBrowser"
    $STD curl -fsSL https://raw.githubusercontent.com/filebrowser/get/master/get.sh | bash
    $STD filebrowser config init -a '0.0.0.0'
    $STD filebrowser config set -a '0.0.0.0'
    $STD filebrowser users add admin community-scripts.org --perm.admin
    msg_ok "Installed FileBrowser"

    msg_info "Creating Service"
    cat << EOF > /etc/systemd/system/filebrowser.service
[Unit]
Description=Filebrowser
After=network-online.target

[Service]
User=root
WorkingDirectory=/root/
ExecStart=/usr/local/bin/filebrowser -r /

[Install]
WantedBy=default.target
EOF
    systemctl enable -q --now filebrowser
    msg_ok "Created Service"

    msg_ok "Completed successfully!\n"
    echo -e "FileBrowser should be reachable by going to the following URL.
         ${BL}http://$LOCAL_IP:8080${CL}   admin|community-scripts.org\n"
    exit
  fi
  if [ "$UPD" == "4" ]; then
    msg_info "Removing ALL Unused Images"
    podman image prune -a -f
    msg_ok "Removed ALL Unused Images"
    exit
  fi
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
