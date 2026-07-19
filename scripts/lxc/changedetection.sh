#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://changedetection.io/ | Github: https://github.com/dgtlmoon/changedetection.io

# shellcheck disable=SC2034
APP="Change Detection"
var_tags="${var_tags:-monitoring;crawler}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies (Patience)"
  $STD apt install -y \
    git \
    build-essential \
    dumb-init \
    gconf-service \
    libjpeg-dev \
    libatk-bridge2.0-0 \
    libasound2 \
    libatk1.0-0 \
    libcairo2 \
    libcups2 \
    libdbus-1-3 \
    libexpat1 \
    libgbm-dev \
    libgbm1 \
    libgconf-2-4 \
    libgdk-pixbuf2.0-0 \
    libglib2.0-0 \
    libgtk-3-0 \
    libnspr4 \
    libnss3 \
    libpango-1.0-0 \
    libpangocairo-1.0-0 \
    qpdf \
    xdg-utils \
    xvfb \
    ca-certificates
  msg_ok "Installed Dependencies"

  NODE_VERSION="24" setup_nodejs
  PYTHON_VERSION="3.13" setup_uv

  msg_info "Installing Change Detection"
  mkdir -p /opt/changedetection
  $STD uv venv --clear /opt/changedetection/.venv
  $STD /opt/changedetection/.venv/bin/python -m ensurepip --upgrade
  $STD /opt/changedetection/.venv/bin/python -m pip install --upgrade pip
  $STD /opt/changedetection/.venv/bin/python -m pip install changedetection.io
  cat << EOF > /opt/changedetection/.env
WEBDRIVER_URL=http://127.0.0.1:4444/wd/hub
PLAYWRIGHT_DRIVER_URL=ws://localhost:3000/chrome?launch=eyJkZWZhdWx0Vmlld3BvcnQiOnsiaGVpZ2h0Ijo3MjAsIndpZHRoIjoxMjgwfSwiaGVhZGxlc3MiOmZhbHNlLCJzdGVhbHRoIjp0cnVlfQ==&blockAds=true
EOF
  msg_ok "Installed Change Detection"

  msg_info "Installing Browserless & Playwright"
  mkdir /opt/browserless
  $STD /opt/changedetection/.venv/bin/python -m pip install playwright
  $STD git clone https://github.com/browserless/chrome /opt/browserless
  $STD npm ci --include=optional --include=dev --prefix /opt/browserless
  $STD /opt/browserless/node_modules/playwright-core/cli.js install --with-deps &> /dev/null
  $STD /opt/browserless/node_modules/playwright-core/cli.js install --force chrome &> /dev/null
  $STD /opt/browserless/node_modules/playwright-core/cli.js install chromium firefox webkit &> /dev/null
  $STD /opt/browserless/node_modules/playwright-core/cli.js install --force msedge
  $STD npm run build --prefix /opt/browserless
  $STD npm run build:function --prefix /opt/browserless
  $STD npm prune production --prefix /opt/browserless
  msg_ok "Installed Browserless & Playwright"

  msg_info "Installing Font Packages"
  $STD apt install -y \
    fontconfig \
    libfontconfig1 \
    fonts-freefont-ttf \
    fonts-gfs-neohellenic \
    fonts-indic \
    fonts-ipafont-gothic \
    fonts-kacst \
    fonts-liberation \
    fonts-noto-cjk \
    fonts-noto-color-emoji \
    msttcorefonts \
    fonts-roboto \
    fonts-thai-tlwg \
    fonts-wqy-zenhei
  msg_ok "Installed Font Packages"

  msg_info "Installing X11 Packages"
  $STD apt install -y \
    libx11-6 \
    libx11-xcb1 \
    libxcb1 \
    libxcomposite1 \
    libxcursor1 \
    libxdamage1 \
    libxext6 \
    libxfixes3 \
    libxi6 \
    libxrandr2 \
    libxrender1 \
    libxss1 \
    libxtst6
  msg_ok "Installed X11 Packages"

  msg_info "Creating Services"
  cat << EOF > /etc/systemd/system/changedetection.service
[Unit]
Description=Change Detection
After=network-online.target
After=network.target browserless.service
Wants=browserless.service

[Service]
Type=simple
EnvironmentFile=/opt/changedetection/.env
WorkingDirectory=/opt/changedetection
ExecStart=/opt/changedetection/.venv/bin/changedetection.io -d /opt/changedetection -p 5000

[Install]
WantedBy=multi-user.target
EOF

  cat << EOF > /etc/systemd/system/browserless.service
[Unit]
Description=browserless service
After=network.target

[Service]
Environment=CONNECTION_TIMEOUT=60000
WorkingDirectory=/opt/browserless
ExecStart=/opt/browserless/scripts/start.sh
SyslogIdentifier=browserless

[Install]
WantedBy=default.target
EOF
  systemctl enable -q --now browserless
  systemctl enable -q --now changedetection
  msg_ok "Created Services"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:5000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /etc/systemd/system/changedetection.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  ensure_dependencies libjpeg-dev

  NODE_VERSION="24" setup_nodejs

  VENV_PATH="/opt/changedetection/.venv"
  CHANGEDETECTION_BIN="${VENV_PATH}/bin/changedetection.io"

  PYTHON_VERSION="3.13" setup_uv

  if [[ ! -d "$VENV_PATH" || ! -x "$CHANGEDETECTION_BIN" ]]; then
    msg_info "Migrating to uv/venv"
    rm -rf "$VENV_PATH"
    $STD uv venv --clear "$VENV_PATH"
    $STD "$VENV_PATH/bin/python" -m ensurepip --upgrade
    $STD "$VENV_PATH/bin/python" -m pip install --upgrade pip
    $STD "$VENV_PATH/bin/python" -m pip install changedetection.io playwright
    msg_ok "Migrated to uv/venv"
  else
    msg_info "Updating ${APP}"
    $STD "$VENV_PATH/bin/python" -m pip install --upgrade changedetection.io playwright
    msg_ok "Updated ${APP}"
  fi

  SERVICE_FILE="/etc/systemd/system/changedetection.service"
  if ! grep -q "${VENV_PATH}/bin/changedetection.io" "$SERVICE_FILE"; then
    msg_info "Updating systemd service"
    sed -i "s|^ExecStart=.*|ExecStart=${VENV_PATH}/bin/changedetection.io -d /opt/changedetection -p 5000|" "$SERVICE_FILE"
    $STD systemctl daemon-reload
    msg_ok "Updated systemd service"
  fi

  if [[ -f /etc/systemd/system/browserless.service ]]; then
    msg_info "Updating Browserless (Patience)"
    $STD git -C /opt/browserless/ fetch --all
    $STD git -C /opt/browserless/ reset --hard origin/main
    $STD npm update --prefix /opt/browserless
    $STD npm ci --include=optional --include=dev --prefix /opt/browserless
    $STD /opt/browserless/node_modules/playwright-core/cli.js install --with-deps
    $STD /opt/browserless/node_modules/playwright-core/cli.js install --force chrome
    $STD /opt/browserless/node_modules/playwright-core/cli.js install --force msedge
    $STD /opt/browserless/node_modules/playwright-core/cli.js install chromium firefox webkit
    $STD npm install --prefix /opt/browserless esbuild typescript ts-node @types/node --save-dev
    $STD npm run build --prefix /opt/browserless
    $STD npm run build:function --prefix /opt/browserless
    $STD npm prune production --prefix /opt/browserless
    systemctl restart browserless
    msg_ok "Updated Browserless"
  else
    msg_error "No Browserless Installation Found!"
  fi

  systemctl restart changedetection
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
