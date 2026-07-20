#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://nodered.org/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Node-RED"
var_tags="${var_tags:-automation}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    git \
    ca-certificates
  msg_ok "Installed Dependencies"

  NODE_VERSION="22" setup_nodejs

  msg_info "Installing Node-RED"
  $STD npm install -g --unsafe-perm node-red
  echo "journalctl -f -n 100 -u nodered -o cat" > /usr/bin/node-red-log
  chmod +x /usr/bin/node-red-log
  echo "systemctl stop nodered" > /usr/bin/node-red-stop
  chmod +x /usr/bin/node-red-stop
  echo "systemctl start nodered" > /usr/bin/node-red-start
  chmod +x /usr/bin/node-red-start
  echo "systemctl restart nodered" > /usr/bin/node-red-restart
  chmod +x /usr/bin/node-red-restart
  msg_ok "Installed Node-RED"

  msg_info "Creating Service"
  cat << 'EOF' > /etc/systemd/system/nodered.service
[Unit]
Description=Node-RED
After=syslog.target network.target

[Service]
ExecStart=/usr/bin/node-red --max-old-space-size=128 -v
Restart=on-failure
KillSignal=SIGINT
SyslogIdentifier=node-red
StandardOutput=syslog
WorkingDirectory=/root/
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now nodered
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:1880${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /root/.node-red ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  UPD=$(msg_menu "Node-RED Update Options" \
    "1" "Update ${APP}" \
    "2" "Install Themes")
  if [ "$UPD" == "1" ]; then
    NODE_VERSION="22" setup_nodejs

    msg_info "Stopping Service"
    systemctl stop nodered
    msg_ok "Stopped Service"

    msg_info "Updating Node-RED"
    $STD npm install -g --unsafe-perm node-red
    msg_ok "Updated Node-RED"

    msg_info "Starting Service"
    systemctl start nodered
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
    exit
  fi
  if [ "$UPD" == "2" ]; then
    THEME=$(msg_menu "Node-RED Themes" \
      "midnight-red" "Midnight Red (default)" \
      "aurora" "Aurora" \
      "cobalt2" "Cobalt2" \
      "dark" "Dark" \
      "dracula" "Dracula" \
      "espresso-libre" "Espresso Libre" \
      "github-dark" "GitHub Dark" \
      "github-dark-default" "GitHub Dark Default" \
      "github-dark-dimmed" "GitHub Dark Dimmed" \
      "monoindustrial" "Monoindustrial" \
      "monokai" "Monokai" \
      "monokai-dimmed" "Monokai Dimmed" \
      "noctis" "Noctis" \
      "oceanic-next" "Oceanic Next" \
      "oled" "OLED" \
      "one-dark-pro" "One Dark Pro" \
      "one-dark-pro-darker" "One Dark Pro Darker" \
      "solarized-dark" "Solarized Dark" \
      "solarized-light" "Solarized Light" \
      "tokyo-night" "Tokyo Night" \
      "tokyo-night-light" "Tokyo Night Light" \
      "tokyo-night-storm" "Tokyo Night Storm" \
      "totallyinformation" "TotallyInformation" \
      "zenburn" "Zenburn")
    header_info
    msg_info "Installing ${THEME} Theme"
    cd /root/.node-red || exit
    sed -i 's|// theme: ".*",|theme: "",|g' /root/.node-red/settings.js
    $STD npm install @node-red-contrib-themes/theme-collection
    sed -i "{s/theme: \".*\"/theme: '${THEME}',/g}" /root/.node-red/settings.js
    systemctl restart nodered
    msg_ok "Installed ${THEME} Theme"
    exit
  fi
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
