#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://podman.io/

# shellcheck disable=SC2034
APP="Podman"
var_tags="${var_tags:-container;kubernetes}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
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

  read -r -p "Would you like to add Portainer? <y/N> " prompt
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
    read -r -p "Would you like to add the Portainer Agent? <y/N> " prompt
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
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL(s):${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:9443${CL} (Portainer - if installed)"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:9001${CL} (Portainer Agent - if installed)"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /etc/containers/registries.conf ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating ${APP} LXC"
  $STD apt update
  $STD apt upgrade -y
  msg_ok "Updated Successfully!"
  exit
}

# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
