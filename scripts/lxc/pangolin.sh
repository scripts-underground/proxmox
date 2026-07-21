#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://pangolin.net/ | Github: https://github.com/fosrl/pangolin

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Pangolin"
var_tags="${var_tags:-proxy}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_tun="${var_tun:-1}"

function install_script() {
  PANGOLIN_VERSION="${PANGOLIN_VERSION:-1.20.0}"

  msg_info "Installing Dependencies"
  $STD apt install -y build-essential iptables
  msg_ok "Installed Dependencies"

  NODE_VERSION="24" setup_nodejs
  PG_VERSION="17" setup_postgresql
  PG_DB_NAME="pangolin" PG_DB_USER="pangolin" setup_postgresql_db
  fetch_and_deploy_gh_release "pangolin" "fosrl/pangolin" "tarball" "$PANGOLIN_VERSION"
  fetch_and_deploy_gh_release "gerbil" "fosrl/gerbil" "singlefile" "latest" "/usr/bin" "gerbil_linux_$(get_system_arch)"
  fetch_and_deploy_gh_release "traefik" "traefik/traefik" "prebuild" "latest" "/usr/bin" "traefik_v*_linux_$(get_system_arch).tar.gz"

  read -rp "Enter your Pangolin URL (ex: https://pangolin.example.com): " pango_url
  [[ "$pango_url" != https://* && "$pango_url" != http://* ]] && pango_url="https://${pango_url}"
  read -rp "Enter your email address: " pango_email

  msg_info "Setup Pangolin"
  SECRET_KEY=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 32)
  BADGER_VERSION=$(get_latest_github_release "fosrl/badger" "false")
  cd /opt/pangolin || exit
  mkdir -p /opt/pangolin/config/{traefik,db,letsencrypt,logs}
  $STD npm ci
  $STD npm run set:pg
  $STD npm run set:oss
  rm -rf server/private
  DATABASE_URL="postgresql://pangolin:${PG_DB_PASS}@localhost:5432/pangolin" $STD npm run db:generate
  $STD npm run build
  $STD npm run build:cli
  cp -R .next/standalone ./
  cp -r server/migrations ./dist/init

  cat << EOF > /usr/local/bin/pangctl
#!/bin/sh
cd /opt/pangolin
./dist/cli.mjs "\$@"
EOF
  chmod +x /usr/local/bin/pangctl ./dist/cli.mjs
  cp server/db/names.json ./dist/names.json
  cp server/db/ios_models.json ./dist/ios_models.json
  cp server/db/mac_models.json ./dist/mac_models.json
  mkdir -p /var/config

  cat << EOF > /opt/pangolin/config/config.yml
app:
  dashboard_url: "$pango_url"

domains:
  domain1:
    base_domain: "$pango_url"
    cert_resolver: "letsencrypt"

server:
  secret: "$SECRET_KEY"

gerbil:
  base_endpoint: "${pango_url#https://}"

flags:
  require_email_verification: false
  disable_signup_without_invite: false
  disable_user_create_org: false

postgres:
  connection_string: "postgresql://pangolin:${PG_DB_PASS}@localhost:5432/pangolin"
EOF

  cat << EOF > /opt/pangolin/config/traefik/traefik_config.yml
api:
  insecure: true
  dashboard: true

providers:
  http:
    endpoint: "http://$LOCAL_IP:3001/api/v1/traefik-config"
    pollInterval: "5s"
  file:
    filename: "/opt/pangolin/config/traefik/dynamic_config.yml"

experimental:
  plugins:
    badger:
      moduleName: "github.com/fosrl/badger"
      version: "$BADGER_VERSION"

log:
  level: "INFO"
  format: "common"

certificatesResolvers:
  letsencrypt:
    acme:
      httpChallenge:
        entryPoint: web
      email: $pango_email
      storage: "/opt/pangolin/config/letsencrypt/acme.json"
      caServer: "https://acme-v02.api.letsencrypt.org/directory"

entryPoints:
  web:
    address: ":80"
  websecure:
    address: ":443"
    transport:
      respondingTimeouts:
        readTimeout: "30m"
    http:
      tls:
        certResolver: "letsencrypt"

serversTransport:
  insecureSkipVerify: true

ping:
    entryPoint: "web"
EOF

  cat << EOF > /opt/pangolin/config/traefik/dynamic_config.yml
http:
  middlewares:
    redirect-to-https:
      redirectScheme:
        scheme: https

  routers:
    # HTTP to HTTPS redirect router
    main-app-router-redirect:
      rule: "Host(\`${pango_url#https://}\`)"
      service: next-service
      entryPoints:
        - web
      middlewares:
        - redirect-to-https

    # Next.js router (handles everything except API and WebSocket paths)
    next-router:
      rule: "Host(\`${pango_url#https://}\`) && !PathPrefix(\`/api/v1\`)"
      service: next-service
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt

    # API router (handles /api/v1 paths)
    api-router:
      rule: "Host(\`${pango_url#https://}\`) && PathPrefix(\`/api/v1\`)"
      service: api-service
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt

    # WebSocket router
    ws-router:
      rule: "Host(\`${pango_url#https://}\`)"
      service: api-service
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt

  services:
    next-service:
      loadBalancer:
        servers:
          - url: "http://$LOCAL_IP:3002"

    api-service:
      loadBalancer:
        servers:
          - url: "http://$LOCAL_IP:3000"
EOF
  export ENVIRONMENT=prod
  $STD node dist/migrations.mjs

  . /etc/os-release
  if [ "$VERSION_CODENAME" = "trixie" ]; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.d/sysctl.conf
    $STD sysctl -p /etc/sysctl.d/sysctl.conf
  else
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    $STD sysctl -p /etc/sysctl.conf
  fi
  msg_ok "Setup Pangolin"

  msg_info "Creating Services"
  cat << EOF > /etc/systemd/system/pangolin.service
[Unit]
Description=Pangolin Service
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
User=root
Environment=NODE_ENV=production
Environment=ENVIRONMENT=prod
WorkingDirectory=/opt/pangolin
ExecStartPre=/usr/bin/node dist/migrations.mjs
ExecStart=/usr/bin/node --enable-source-maps dist/server.mjs
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now pangolin

  cat << EOF > /etc/systemd/system/gerbil.service
[Unit]
Description=Gerbil Service
After=network.target
Requires=pangolin.service

[Service]
Type=simple
User=root
ExecStart=/usr/bin/gerbil --reachableAt=http://$LOCAL_IP:3004 --generateAndSaveKeyTo=/var/config/key --remoteConfig=http://$LOCAL_IP:3001/api/v1/
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now gerbil

  cat << 'EOF' > /etc/systemd/system/traefik.service
[Unit]
Description=Traefik is an open-source Edge Router that makes publishing your services a fun and easy experience
Wants=network-online.target
After=network-online.target

[Service]
Type=notify
ExecStart=/usr/bin/traefik --configFile=/opt/pangolin/config/traefik/traefik_config.yml
Restart=on-failure
ExecReload=/bin/kill -USR1 \$MAINPID

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now traefik
  msg_ok "Created Services"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}https://<YOUR_PANGOLIN_URL> or http://${IP}:3002${CL}"
  echo -e "${INFO}${YW}Type 'journalctl -u pangolin | grep -oP Token:\\\\s*\\\\K\\\\w+' to get the admin token.${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/pangolin ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  ensure_dependencies build-essential python3

  if ! command -v psql &> /dev/null; then
    msg_error "This installation uses SQLite and cannot be upgraded to Pangolin ${PANGOLIN_VERSION}."
    echo -e "${INFO}${YW}Starting with Pangolin 1.20.0, PostgreSQL is required as the database backend.${CL}"
    echo -e "${INFO}${YW}An automatic migration of your existing SQLite data is not supported.${CL}"
    echo -e "${INFO}${YW}Please create a new LXC with the Pangolin install script, which sets up PostgreSQL automatically.${CL}"
    echo -e "${INFO}${YW}Your current data is preserved in this container and can be manually migrated if needed.${CL}"
    exit 1
  fi

  NODE_VERSION="24" setup_nodejs

  if check_for_gh_release "pangolin" "fosrl/pangolin" "$PANGOLIN_VERSION" "Pinned to a tested release because Pangolin's schema changes have repeatedly broken unattended updates. To try a newer version at your own risk, run: 'export PANGOLIN_VERSION=<tag>' and re-run update. If it breaks, please open an issue at https://github.com/community-scripts/ProxmoxVE/issues with the error log."; then
    msg_info "Stopping Service"
    systemctl stop pangolin
    systemctl stop gerbil
    msg_info "Service stopped"

    DB_URL=$(sed -n 's/.*connection_string: "\(.*\)".*/\1/p' /opt/pangolin/config/config.yml)
    create_backup /opt/pangolin/config

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "pangolin" "fosrl/pangolin" "tarball" "$PANGOLIN_VERSION"
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "gerbil" "fosrl/gerbil" "singlefile" "latest" "/usr/bin" "gerbil_linux_$(get_system_arch)"

    msg_info "Updating Pangolin"
    cd /opt/pangolin || exit
    $STD npm ci
    $STD npm run set:pg
    $STD npm run set:oss
    rm -rf server/private
    DATABASE_URL="$DB_URL" $STD npm run db:generate
    $STD npm run build
    $STD npm run build:cli
    cp -R .next/standalone ./
    cp -r server/migrations ./dist/init
    chmod +x ./dist/cli.mjs
    cp server/db/names.json ./dist/names.json
    cp server/db/ios_models.json ./dist/ios_models.json
    cp server/db/mac_models.json ./dist/mac_models.json
    msg_ok "Updated Pangolin"

    restore_backup

    if ! grep -q '^ExecStartPre=/usr/bin/node dist/migrations.mjs' /etc/systemd/system/pangolin.service 2> /dev/null; then
      msg_info "Adding migration step to pangolin.service"
      sed -i '/^ExecStart=\/usr\/bin\/node --enable-source-maps dist\/server.mjs/i ExecStartPre=/usr/bin/node dist/migrations.mjs' /etc/systemd/system/pangolin.service
      systemctl daemon-reload
      msg_ok "Updated pangolin.service"
    fi

    msg_info "Running database migrations"
    cd /opt/pangolin || exit
    ENVIRONMENT=prod $STD node dist/migrations.mjs

    msg_ok "Ran database migrations"

    msg_info "Updating Badger plugin version"
    BADGER_VERSION=$(get_latest_github_release "fosrl/badger" "false")
    sed -i "s/version: \"v[0-9.]*\"/version: \"$BADGER_VERSION\"/g" /opt/pangolin/config/traefik/traefik_config.yml
    msg_ok "Updated Badger plugin version"

    msg_info "Starting Services"
    systemctl start pangolin
    systemctl start gerbil
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
