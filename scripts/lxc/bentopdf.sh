#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: vhsdream
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/alam00000/bentopdf

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="BentoPDF"
var_tags="${var_tags:-pdf-editor}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    nginx \
    openssl
  msg_ok "Installed Dependencies"

  NODE_VERSION="24" setup_nodejs
  fetch_and_deploy_gh_release "bentopdf" "alam00000/bentopdf" "tarball" "latest" "/opt/bentopdf"

  msg_info "Setup BentoPDF"
  cd /opt/bentopdf || exit
  $STD npm ci --no-audit --no-fund
  cp ./.env.example ./.env.production
  export NODE_OPTIONS="--max-old-space-size=3072"
  export SIMPLE_MODE=true
  export VITE_USE_CDN=true
  $STD npm run build:all
  cat << 'EOF' > /opt/bentopdf/dist/config.json
{}
EOF
  msg_ok "Setup BentoPDF"

  msg_info "Creating Service"
  CERT_CN="$(hostname -I | awk '{print $1}')"
  $STD openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
    -keyout /etc/ssl/private/bentopdf-selfsigned.key \
    -out /etc/ssl/certs/bentopdf-selfsigned.crt \
    -subj "/CN=${CERT_CN}"

  cat << 'EOF' > /etc/nginx/sites-available/bentopdf
server {
    listen 8080;
    server_name _;
    return 301 https://$host:8443$request_uri;
}

server {
    listen 8443 ssl;
    server_name _;
    ssl_certificate /etc/ssl/certs/bentopdf-selfsigned.crt;
    ssl_certificate_key /etc/ssl/private/bentopdf-selfsigned.key;
    root /opt/bentopdf/dist;
    index index.html;

    # Required for LibreOffice WASM (Word/Excel/PowerPoint to PDF via SharedArrayBuffer)
    add_header Cross-Origin-Opener-Policy "same-origin" always;
    add_header Cross-Origin-Embedder-Policy "require-corp" always;
    add_header Cross-Origin-Resource-Policy "cross-origin" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;

    gzip_static on;

    location ~* /libreoffice-wasm/soffice\.wasm\.gz$ {
        gzip off;
        types {} default_type application/wasm;
        add_header Content-Encoding gzip;
        add_header Vary "Accept-Encoding";
        add_header Cache-Control "public, immutable";
    }

    location ~* /libreoffice-wasm/soffice\.data\.gz$ {
        gzip off;
        types {} default_type application/octet-stream;
        add_header Content-Encoding gzip;
        add_header Vary "Accept-Encoding";
        add_header Cache-Control "public, immutable";
    }

    location ~* \.wasm$ {
        types {} default_type application/wasm;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    location ~* \.(wasm\.gz|data\.gz|data)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    location / {
        try_files $uri $uri/ $uri.html =404;
    }

    error_page 404 /404.html;
}
EOF
  rm -f /etc/nginx/sites-enabled/default
  ln -sf /etc/nginx/sites-available/bentopdf /etc/nginx/sites-enabled/bentopdf
  systemctl stop nginx
  systemctl disable -q nginx
  sed -i '/application\/rss+xml/a\    application\/javascript                           mjs;' /etc/nginx/mime.types

  cat << 'EOF' > /etc/systemd/system/bentopdf.service
[Unit]
Description=BentoPDF Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/sbin/nginx -g "daemon off;"
ExecReload=/bin/kill -HUP $MAINPID
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now bentopdf
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}https://${IP}:8443${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/bentopdf ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  NODE_VERSION="24" setup_nodejs

  if check_for_gh_release "bentopdf" "alam00000/bentopdf"; then
    msg_info "Stopping Service"
    systemctl stop bentopdf
    msg_ok "Stopped Service"

    create_backup /opt/bentopdf/.env.production
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "bentopdf" "alam00000/bentopdf" "tarball" "latest" "/opt/bentopdf"
    restore_backup

    msg_info "Configuring BentoPDF"
    cd /opt/bentopdf || exit
    $STD npm ci --no-audit --no-fund
    export NODE_OPTIONS="--max-old-space-size=3072"
    export SIMPLE_MODE=true
    export VITE_USE_CDN=true
    $STD npm run build:all
    if [[ ! -f /opt/bentopdf/dist/config.json ]]; then
      cat << 'EOF' > /opt/bentopdf/dist/config.json
{}
EOF
    fi
    msg_ok "Updated BentoPDF"

    msg_info "Starting Service"
    ensure_dependencies nginx openssl
    if [[ ! -f /etc/ssl/private/bentopdf-selfsigned.key || ! -f /etc/ssl/certs/bentopdf-selfsigned.crt ]]; then
      CERT_CN="$(hostname -I | awk '{print $1}')"
      $STD openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
        -keyout /etc/ssl/private/bentopdf-selfsigned.key \
        -out /etc/ssl/certs/bentopdf-selfsigned.crt \
        -subj "/CN=${CERT_CN}"
    fi
    cat << 'EOF' > /etc/nginx/sites-available/bentopdf
server {
    listen 8080;
    server_name _;
    return 301 https://$host:8443$request_uri;
  }

  server {
    listen 8443 ssl;
    server_name _;
    ssl_certificate /etc/ssl/certs/bentopdf-selfsigned.crt;
    ssl_certificate_key /etc/ssl/private/bentopdf-selfsigned.key;
    root /opt/bentopdf/dist;
    index index.html;

    # Required for LibreOffice WASM (Word/Excel/PowerPoint to PDF via SharedArrayBuffer)
    add_header Cross-Origin-Opener-Policy "same-origin" always;
    add_header Cross-Origin-Embedder-Policy "require-corp" always;
    add_header Cross-Origin-Resource-Policy "cross-origin" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;

    gzip_static on;

    location ~* /libreoffice-wasm/soffice\.wasm\.gz$ {
      gzip off;
      types {} default_type application/wasm;
      add_header Content-Encoding gzip;
      add_header Vary "Accept-Encoding";
      add_header Cache-Control "public, immutable";
    }

    location ~* /libreoffice-wasm/soffice\.data\.gz$ {
      gzip off;
      types {} default_type application/octet-stream;
      add_header Content-Encoding gzip;
      add_header Vary "Accept-Encoding";
      add_header Cache-Control "public, immutable";
    }

    location ~* \.wasm$ {
      types {} default_type application/wasm;
      expires 1y;
      add_header Cache-Control "public, immutable";
    }

    location ~* \.(wasm\.gz|data\.gz|data)$ {
      expires 1y;
      add_header Cache-Control "public, immutable";
    }

    location / {
        try_files $uri $uri/ $uri.html =404;
    }

    error_page 404 /404.html;
}
EOF
    rm -f /etc/nginx/sites-enabled/default
    ln -sf /etc/nginx/sites-available/bentopdf /etc/nginx/sites-enabled/bentopdf
    cat << 'EOF' > /etc/systemd/system/bentopdf.service
[Unit]
Description=BentoPDF Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/sbin/nginx -g "daemon off;"
ExecReload=/bin/kill -HUP $MAINPID
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl start bentopdf
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
