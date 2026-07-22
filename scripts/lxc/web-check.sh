#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: CrazyWolf13
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/Lissy93/web-check

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="web-check"
var_tags="${var_tags:-network;analysis}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-12}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  export DEBIAN_FRONTEND=noninteractive
  $STD apt -y install --no-install-recommends \
    git \
    traceroute \
    build-essential \
    xvfb \
    dbus \
    xorg \
    gtk2-engines-pixbuf \
    dbus-x11 \
    xfonts-base \
    xfonts-100dpi \
    xfonts-75dpi \
    xfonts-scalable \
    imagemagick \
    x11-apps
  msg_ok "Installed Dependencies"

  NODE_VERSION="22" NODE_MODULE="yarn" setup_nodejs

  msg_info "Setup Python3"
  $STD apt install -y python3
  rm -rf /usr/lib/python3.*/EXTERNALLY-MANAGED
  msg_ok "Setup Python3"

  msg_info "Installing Chrome"
  setup_deb822_repo \
    "google-chrome" \
    "https://dl.google.com/linux/linux_signing_key.pub" \
    "https://dl.google.com/linux/chrome/deb/" \
    "stable"
  $STD apt update
  $STD apt install -y google-chrome-stable libxss1 lsb-release
  if [ -f /etc/apt/sources.list.d/google-chrome.list ]; then
    rm /etc/apt/sources.list.d/google-chrome.list
  fi
  msg_ok "Installed Chrome"

  msg_info "Setting up Chrome"
  ln -sf /usr/bin/google-chrome-stable /usr/bin/chromium
  /usr/bin/chromium --no-sandbox --version > /etc/chromium-version
  chmod 755 /usr/bin/chromium
  msg_ok "Setup Chrome"

  fetch_and_deploy_gh_release "web-check" "Lissy93/web-check" "tarball"

  msg_info "Installing Web-Check (Patience)"
  cd /opt/web-check || exit
  cat << 'EOF' > /opt/web-check/.env
CHROME_PATH=/usr/bin/chromium
PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium
PUPPETEER_SKIP_DOWNLOAD='true'
HEADLESS=true
GOOGLE_CLOUD_API_KEY=''
REACT_APP_SHODAN_API_KEY=''
REACT_APP_WHO_API_KEY=''
SECURITY_TRAILS_API_KEY=''
CLOUDMERSIVE_API_KEY=''
TRANCO_USERNAME=''
TRANCO_API_KEY=''
URL_SCAN_API_KEY=''
BUILT_WITH_API_KEY=''
TORRENT_IP_API_KEY=''
PORT='3000'
DISABLE_GUI='false'
API_TIMEOUT_LIMIT='10000'
API_CORS_ORIGIN='*'
API_ENABLE_RATE_LIMIT='false'
REACT_APP_API_ENDPOINT='/api'
ENABLE_ANALYTICS='false'
EOF
  $STD yarn install --frozen-lockfile --network-timeout 100000
  msg_ok "Installed Web-Check"

  msg_info "Building Web-Check"
  $STD yarn build --production
  msg_ok "Built Web-Check"

  msg_info "Creating Service"
  cat << 'EOF' > /opt/run_web-check.sh
#!/bin/bash
SCREEN_RESOLUTION="1280x1024x24"
if ! systemctl is-active --quiet dbus; then
  echo "Warning: dbus service is not running. Some features may not work properly."
fi
[[ -z "${DISPLAY}" ]] && export DISPLAY=":99"
Xvfb "${DISPLAY}" -screen 0 "${SCREEN_RESOLUTION}" &
XVFB_PID=$!
sleep 2
cd /opt/web-check
exec yarn start
EOF
  chmod +x /opt/run_web-check.sh
  cat << 'EOF' > /etc/systemd/system/web-check.service
[Unit]
Description=Web Check Service
After=network.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/opt/web-check
EnvironmentFile=/opt/web-check/.env
ExecStartPre=/bin/bash -c "service dbus start || true"
ExecStartPre=/bin/bash -c "if ! pgrep -f 'Xvfb.*:99' > /dev/null; then Xvfb :99 -screen 0 1280x1024x24 & fi"
ExecStart=/opt/run_web-check.sh
Restart=on-failure
Environment=DISPLAY=:99

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now web-check
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:3000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/web-check ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "web-check" "Lissy93/web-check"; then
    msg_info "Stopping Service"
    systemctl stop web-check
    msg_ok "Stopped Service"

    create_backup /opt/web-check/.env

    NODE_VERSION="22" NODE_MODULE="yarn" setup_nodejs
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "web-check" "Lissy93/web-check" "tarball"

    restore_backup

    msg_info "Building Web-Check"
    cd /opt/web-check || exit
    $STD yarn install --frozen-lockfile --network-timeout 100000
    $STD yarn build --production
    $STD npm cache clean --force
    msg_ok "Built Web-Check"

    msg_info "Starting Service"
    systemctl start web-check
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
