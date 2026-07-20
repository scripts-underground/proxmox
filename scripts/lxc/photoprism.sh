#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.photoprism.app/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="PhotoPrism"
var_tags="${var_tags:-media;photo}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-3072}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_gpu="${var_gpu:-yes}"

function install_script() {
  msg_info "Installing Dependencies (Patience)"
  $STD apt install -y \
    exiftool \
    ffmpeg \
    libheif1 \
    libpng-dev \
    libjpeg-dev \
    libtiff-dev \
    imagemagick \
    darktable \
    rawtherapee \
    libvips42 \
    lsb-release
  msg_ok "Installed Dependencies"

  echo 'export PATH=/usr/local:$PATH' >> ~/.bashrc
  echo '# Load PhotoPrism environment variables for CLI tools' >> ~/.bashrc
  echo 'export $(grep -v "^#" /opt/photoprism/config/.env | xargs)' >> ~/.bashrc
  export PATH=/usr/local:$PATH

  ARCH=$(get_system_arch)
  ensure_dependencies libvips42

  fetch_and_deploy_gh_release "photoprism" "photoprism/photoprism" "prebuild" "latest" "/opt/photoprism" "*linux-${ARCH}.tar.gz"

  msg_info "Installing PhotoPrism (Patience)"
  mkdir -p /opt/photoprism/{cache,config,photos,storage,temp}
  mkdir -p /opt/photoprism/photos/{originals,import}
  mkdir -p /opt/photoprism_backups
  LIBHEIF_URL=$(curl -fsSL "https://dl.photoprism.app/dist/libheif/" | grep -oP "libheif-bookworm-${ARCH}-v[0-9\.]+\.tar\.gz" | sort -V | tail -n 1)
  curl -fsSL "https://dl.photoprism.app/dist/libheif/$LIBHEIF_URL" -o /tmp/libheif.tar.gz
  tar -xzf /tmp/libheif.tar.gz -C /usr/local
  ldconfig
  echo "${LIBHEIF_URL}" > ~/.photoprism_libheif
  chmod -R 755 /opt/photoprism/photos/originals
  cat << EOF > /opt/photoprism/config/.env
# Authentication
PHOTOPRISM_ADMIN_USER='admin'
PHOTOPRISM_ADMIN_PASSWORD='changeme'
PHOTOPRISM_AUTH_MODE='password'
PHOTOPRISM_PUBLIC='false'

# Network / HTTP
PHOTOPRISM_HTTP_HOST='0.0.0.0'
PHOTOPRISM_HTTP_PORT='2342'
PHOTOPRISM_SITE_URL='http://localhost:2342/'
PHOTOPRISM_DISABLE_TLS='true'
PHOTOPRISM_DEFAULT_TLS='false'
PHOTOPRISM_HTTP_COMPRESSION='gzip'

# Features & AI
PHOTOPRISM_DISABLE_TENSORFLOW='false'
PHOTOPRISM_DISABLE_FACES='false'
PHOTOPRISM_DISABLE_CLASSIFICATION='false'
PHOTOPRISM_DISABLE_VECTORS='false'
PHOTOPRISM_DETECT_NSFW='false'
PHOTOPRISM_UPLOAD_NSFW='true'

# Paths & Storage
PHOTOPRISM_STORAGE_PATH='/opt/photoprism/storage'
PHOTOPRISM_ORIGINALS_PATH='/opt/photoprism/photos/originals'
PHOTOPRISM_IMPORT_PATH='/opt/photoprism/photos/import'
PHOTOPRISM_BACKUP_PATH='/opt/photoprism_backups'

# Database
PHOTOPRISM_DATABASE_DRIVER='sqlite'

# Behavior & Options
PHOTOPRISM_AUTO_INDEX='300'
PHOTOPRISM_AUTO_IMPORT='-1'
PHOTOPRISM_DISABLE_WEBDAV='false'
PHOTOPRISM_READONLY='false'
PHOTOPRISM_DISABLE_SETTINGS='false'
PHOTOPRISM_DISABLE_CHOWN='false'
PHOTOPRISM_EXPERIMENTAL='false'
PHOTOPRISM_INIT='https tensorflow'

# Image Processing
PHOTOPRISM_ORIGINALS_LIMIT='5000'
PHOTOPRISM_JPEG_QUALITY='85'
PHOTOPRISM_RAW_PRESETS='false'
PHOTOPRISM_DISABLE_RAW='false'

# Debug & Logging
PHOTOPRISM_DEBUG='false'
PHOTOPRISM_LOG_LEVEL='info'

# Site Info
PHOTOPRISM_SITE_CAPTION='https://community-scripts.org'
PHOTOPRISM_SITE_DESCRIPTION=''
PHOTOPRISM_SITE_AUTHOR=''
EOF
  ln -sf /opt/photoprism/bin/photoprism /usr/local/bin/photoprism

  mkdir -p /etc/photoprism/
  cat << EOF > /etc/photoprism/defaults.yml
ConfigPath: "~/.config/photoprism"
StoragePath: "/opt/photoprism/storage"
OriginalsPath: "/opt/photoprism/photos/originals"
ImportPath: "/media"
AdminUser: "admin"
AdminPassword: "changeme"
AuthMode: "password"
DatabaseDriver: "sqlite"
HttpHost: "0.0.0.0"
HttpPort: 2342
HttpCompression: "gzip"
DisableTLS: false
DefaultTLS: true
Experimental: false
DisableWebDAV: false
DisableSettings: false
DisableTensorFlow: false
DisableFaces: false
DisableClassification: false
DisableVectors: false
DisableRaw: false
RawPresets: false
JpegQuality: 85
DetectNSFW: false
UploadNSFW: true
EOF
  msg_ok "Installed PhotoPrism"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/photoprism.service
[Unit]
Description=PhotoPrism service
After=network.target

[Service]
Type=forking
User=root
WorkingDirectory=/opt/photoprism
EnvironmentFile=/opt/photoprism/config/.env
ExecStart=/opt/photoprism/bin/photoprism up -d
ExecStop=/opt/photoprism/bin/photoprism down

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now photoprism
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:2342${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/photoprism ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "photoprism" "photoprism/photoprism"; then
    msg_info "Stopping PhotoPrism"
    systemctl stop photoprism
    msg_ok "Stopped PhotoPrism"

    if ! grep -q "photoprism/config/.env" ~/.bashrc 2> /dev/null; then
      msg_info "Adding environment export for CLI tools"
      echo '# Load PhotoPrism environment variables for CLI tools' >> ~/.bashrc
      echo 'set -a' >> ~/.bashrc
      echo 'source /opt/photoprism/config/.env' >> ~/.bashrc
      echo 'set +a' >> ~/.bashrc
      msg_ok "Added environment export"
    fi

    ARCH=$(get_system_arch)
    fetch_and_deploy_gh_release "photoprism" "photoprism/photoprism" "prebuild" "latest" "/opt/photoprism" "*linux-${ARCH}.tar.gz"

    LIBHEIF_URL=$(curl -fsSL "https://dl.photoprism.app/dist/libheif/" | grep -oP "libheif-bookworm-${ARCH}-v[0-9\.]+\.tar\.gz" | sort -V | tail -n 1)
    if [[ "${LIBHEIF_URL}" != "$(cat ~/.photoprism_libheif 2> /dev/null)" ]] || [[ ! -f ~/.photoprism_libheif ]]; then
      msg_info "Updating PhotoPrism LibHeif"
      ensure_dependencies libvips42
      curl -fsSL "https://dl.photoprism.app/dist/libheif/$LIBHEIF_URL" -o /tmp/libheif.tar.gz
      tar -xzf /tmp/libheif.tar.gz -C /usr/local
      ldconfig
      echo "${LIBHEIF_URL}" > ~/.photoprism_libheif
      msg_ok "Updated PhotoPrism LibHeif"
    fi

    msg_info "Starting PhotoPrism"
    systemctl start photoprism
    msg_ok "Started PhotoPrism"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
