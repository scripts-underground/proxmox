#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://karakeep.app/ | Github: https://github.com/karakeep-app/karakeep

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="karakeep"
var_tags="${var_tags:-bookmark}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-15}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    build-essential \
    ca-certificates \
    chromium \
    graphicsmagick \
    ghostscript \
    python3-pip \
    ffmpeg
  msg_ok "Installed Dependencies"

  fetch_and_deploy_gh_release "monolith" "Y2Z/monolith" "singlefile" "latest" "/usr/bin" "monolith-gnu-linux-$(uname -m)"
  fetch_and_deploy_gh_release "yt-dlp" "yt-dlp/yt-dlp-nightly-builds" "singlefile" "latest" "/usr/bin" "yt-dlp_linux"
  fetch_and_deploy_gh_release "deno" "denoland/deno" "prebuild" "latest" "/usr/local/bin" "deno-$(uname -m)-unknown-linux-gnu.zip"
  setup_meilisearch

  fetch_and_deploy_gh_release "karakeep" "karakeep-app/karakeep" "tarball"
  cd /opt/karakeep || exit
  MODULE_VERSION="$(jq -r '.packageManager | split("@")[1]' /opt/karakeep/package.json)"
  NODE_VERSION="24" NODE_MODULE="pnpm@${MODULE_VERSION}" setup_nodejs

  msg_info "Installing external JavaScript Extension for yt-dlp"
  $STD pip install -U yt-dlp-ejs --break-system-packages
  mkdir -p ~/.config/pip
  cat << EOF > ~/.config/pip/pip.conf
[global]
break-system-packages = true
EOF
  msg_ok "Installed external JavaScript Extension for yt-dlp"

  msg_info "Installing karakeep"
  export PUPPETEER_SKIP_DOWNLOAD="true"
  export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD="true"
  export NEXT_TELEMETRY_DISABLED=1
  export CI="true"
  cd /opt/karakeep/apps/web || exit
  $STD pnpm install --frozen-lockfile
  $STD pnpm build
  cd /opt/karakeep/apps/workers || exit
  $STD pnpm install --frozen-lockfile
  $STD pnpm build
  cd /opt/karakeep/apps/cli || exit
  $STD pnpm install --frozen-lockfile
  $STD pnpm build
  $STD pnpm store prune
  cat << 'EOF' > /usr/bin/karakeep
#!/usr/bin/env node
import('/opt/karakeep/apps/cli/dist/index.mjs')
EOF
  chmod +x /usr/bin/karakeep

  export DATA_DIR=/opt/karakeep_data
  karakeep_SECRET=$(openssl rand -base64 36 | cut -c1-24)
  mkdir -p /etc/karakeep
  cat << EOF > /etc/karakeep/karakeep.env
SERVER_VERSION="$(sed 's/^v//' ~/.karakeep)"
NEXTAUTH_SECRET="$karakeep_SECRET"
NEXTAUTH_URL="http://localhost:3000"
DATA_DIR=${DATA_DIR}
MEILI_ADDR="http://127.0.0.1:7700"
MEILI_MASTER_KEY="$MEILISEARCH_MASTER_KEY"
BROWSER_WEB_URL="http://127.0.0.1:9222"
DB_WAL_MODE=true

# If you're planning to use OpenAI for tagging. Uncomment the following line:
# OPENAI_API_KEY="<API_KEY>"

# If you're planning to use ollama for tagging, uncomment the following lines:
# OLLAMA_BASE_URL="<OLLAMA_ADDR>"
# OLLAMA_KEEP_ALIVE="5m"

# You can change the models used by uncommenting the following lines, and changing them according to your needs:
# INFERENCE_TEXT_MODEL="gpt-4o-mini"
# INFERENCE_IMAGE_MODEL="gpt-4o-mini" 

# Additional inference defaults
# INFERENCE_CONTEXT_LENGTH="2048"
# INFERENCE_ENABLE_AUTO_TAGGING=true
# INFERENCE_ENABLE_AUTO_SUMMARIZATION=false

# Crawler defaults
# CRAWLER_NUM_WORKERS="1"
# CRAWLER_DOWNLOAD_BANNER_IMAGE=true
# CRAWLER_STORE_SCREENSHOT=true
# CRAWLER_FULL_PAGE_SCREENSHOT=false
# CRAWLER_FULL_PAGE_ARCHIVE=false
# CRAWLER_VIDEO_DOWNLOAD=false
# CRAWLER_VIDEO_DOWNLOAD_MAX_SIZE="50"
# CRAWLER_ENABLE_ADBLOCKER=true
EOF
  msg_ok "Installed karakeep"

  msg_info "Running Database Migration"
  mkdir -p ${DATA_DIR}
  cd /opt/karakeep/packages/db || exit
  $STD pnpm migrate
  msg_ok "Database Migration Completed"

  msg_info "Creating Services"
  cat << EOF > /etc/systemd/system/karakeep-web.service
[Unit]
Description=karakeep Web
Wants=network.target karakeep-workers.service
After=network.target karakeep-workers.service

[Service]
ExecStart=pnpm start
WorkingDirectory=/opt/karakeep/apps/web
EnvironmentFile=/etc/karakeep/karakeep.env
Restart=always

[Install]
WantedBy=multi-user.target
EOF

  cat << EOF > /etc/systemd/system/karakeep-browser.service
[Unit]
Description=karakeep Headless Browser
After=network.target

[Service]
User=root
ExecStart=/usr/bin/chromium --headless --no-sandbox --disable-gpu --disable-dev-shm-usage --remote-debugging-address=127.0.0.1 --remote-debugging-port=9222 --hide-scrollbars
Restart=always

[Install]
WantedBy=multi-user.target
EOF

  cat << EOF > /etc/systemd/system/karakeep-workers.service
[Unit]
Description=karakeep Workers
Wants=network.target karakeep-browser.service meilisearch.service
After=network.target karakeep-browser.service meilisearch.service

[Service]
ExecStart=/usr/bin/node dist/index.js
WorkingDirectory=/opt/karakeep/apps/workers
EnvironmentFile=/etc/karakeep/karakeep.env
Restart=always
TimeoutStopSec=5

[Install]
WantedBy=multi-user.target
EOF

  systemctl enable -q --now karakeep-browser karakeep-workers karakeep-web
  msg_ok "Created Services"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:3000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/karakeep ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "karakeep" "karakeep-app/karakeep"; then
    msg_info "Stopping Services"
    systemctl stop karakeep-web karakeep-workers karakeep-browser
    msg_ok "Stopped Services"

    msg_info "Updating yt-dlp"
    $STD yt-dlp --update-to nightly
    msg_ok "Updated yt-dlp"

    msg_info "Prepare update"
    ensure_dependencies graphicsmagick ghostscript
    if [[ -f /opt/karakeep/.env ]] && [[ ! -f /etc/karakeep/karakeep.env ]]; then
      mkdir -p /etc/karakeep
      mv /opt/karakeep/.env /etc/karakeep/karakeep.env
    fi
    msg_ok "Update prepared"

    if [ ! -f ~/.config/pip/pip.conf ]; then
      mkdir -p ~/.config/pip
      cat << EOF > ~/.config/pip/pip.conf
[global]
break-system-packages = true
EOF
    fi

    if grep -q "start:prod" /etc/systemd/system/karakeep-workers.service; then
      sed -i 's|^ExecStart=.*$|ExecStart=/usr/bin/node dist/index.mjs|' /etc/systemd/system/karakeep-workers.service
      systemctl daemon-reload
    fi

    if grep -q '^ExecStart=/usr/bin/node\s\+dist/index\.mjs$' /etc/systemd/system/karakeep-workers.service; then
      sed -i -E 's#^(ExecStart=/usr/bin/node\s+dist/)index\.mjs$#\1index.js#' /etc/systemd/system/karakeep-workers.service
      systemctl daemon-reload
    fi

    if [ ! -f /usr/bin/karakeep ]; then
      cat << 'EOF' > /usr/bin/karakeep
#!/usr/bin/env node
import('/opt/karakeep/apps/cli/dist/index.mjs')
EOF
      chmod +x /usr/bin/karakeep
    fi

    if ! command -v pip > /dev/null 2>&1 || ! pip show yt-dlp-ejs > /dev/null 2>&1; then
      msg_info "Installing external JavaScript Extension for yt-dlp"
      ensure_dependencies python3-pip
      $STD pip install -U yt-dlp-ejs
      msg_ok "Installed external JavaScript Extension for yt-dlp"
    fi

    if ! command -v deno &> /dev/null; then
      fetch_and_deploy_gh_release "deno" "denoland/deno" "prebuild" "latest" "/usr/local/bin" "deno-$(uname -m)-unknown-linux-gnu.zip"
    fi

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "karakeep" "karakeep-app/karakeep" "tarball"
    if command -v corepack > /dev/null; then
      $STD corepack disable
    fi
    sed -i "s/^SERVER_VERSION=.*$/SERVER_VERSION=${CHECK_UPDATE_RELEASE#v}/" /etc/karakeep/karakeep.env
    MODULE_VERSION="$(jq -r '.packageManager | split("@")[1]' /opt/karakeep/package.json)"
    NODE_VERSION="24" NODE_MODULE="corepack,pnpm@${MODULE_VERSION}" setup_nodejs
    setup_meilisearch

    msg_info "Updating Karakeep"

    export PUPPETEER_SKIP_DOWNLOAD="true"
    export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD="true"
    export NEXT_TELEMETRY_DISABLED=1
    export CI="true"
    cd /opt/karakeep/apps/web || exit
    $STD pnpm install --frozen-lockfile
    $STD pnpm build
    cd /opt/karakeep/apps/workers || exit
    $STD pnpm install --frozen-lockfile
    $STD pnpm build
    cd /opt/karakeep/apps/cli || exit
    $STD pnpm install --frozen-lockfile
    $STD pnpm build
    DATA_DIR="$(sed -n '/^DATA_DIR/p' /etc/karakeep/karakeep.env | awk -F= '{print $2}' | tr -d '="=')"
    export DATA_DIR="${DATA_DIR:-/opt/karakeep_data}"
    cd /opt/karakeep/packages/db || exit
    $STD pnpm migrate
    $STD pnpm store prune
    msg_ok "Updated Karakeep"

    msg_info "Starting Services"
    systemctl start karakeep-browser karakeep-workers karakeep-web
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi

  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
