#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: vhsdream
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://sure.am | Github: https://github.com/we-promise/sure

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Sure"
var_tags="${var_tags:-finance}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-6}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    build-essential \
    redis-server \
    pkg-config \
    libpq-dev \
    libvips
  msg_ok "Installed Dependencies"

  fetch_and_deploy_gh_release "Sure" "we-promise/sure" "tarball" "latest" "/opt/sure"

  PG_VERSION=$(sed -n '/postgres:/s/[^[:digit:]]*//p' /opt/sure/compose.example.yml) setup_postgresql
  PG_DB_NAME=sure_production PG_DB_USER=sure_user setup_postgresql_db
  RUBY_VERSION=$(cat /opt/sure/.ruby-version) RUBY_INSTALL_RAILS=false HOME=/root setup_ruby

  msg_info "Building Sure"
  cd /opt/sure || exit
  export RAILS_ENV=production
  export BUNDLE_DEPLOYMENT=1
  export BUNDLE_WITHOUT=development
  $STD ./bin/bundle install
  $STD ./bin/bundle exec bootsnap precompile --gemfile -j 0
  $STD ./bin/bundle exec bootsnap precompile -j 0 app/ lib/
  export SECRET_KEY_BASE_DUMMY=1 && $STD ./bin/rails assets:precompile
  unset SECRET_KEY_BASE_DUMMY
  msg_ok "Built Sure"

  msg_info "Configuring Sure"
  KEY=$(openssl rand -hex 64)
  mkdir -p /etc/sure
  mv /opt/sure/.env.example /etc/sure/.env
  sed -i -e "/^SECRET_KEY_BASE=/s/secret-value/${KEY}/" \
    -e 's/_KEY_BASE=.*$/&\n\nRAILS_FORCE_SSL=false \
\
# Change to true when using a reverse proxy \
RAILS_ASSUME_SSL=false/' \
    -e "/POSTGRES_PASSWORD=/s/postgres/${PG_DB_PASS}/" \
    -e "/POSTGRES_USER=/s/postgres/${PG_DB_USER}\\
POSTGRES_DB=${PG_DB_NAME}/" \
    -e "s|^APP_DOMAIN=|&${LOCAL_IP}|" /etc/sure/.env
  msg_ok "Configured Sure"

  msg_info "Creating Services"
  cat << EOF > /etc/systemd/system/sure.service
[Unit]
Description=Sure Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/sure
Environment=RAILS_ENV=production
Environment=BUNDLE_DEPLOYMENT=1
Environment=BUNDLE_WITHOUT=development
Environment=PATH=/root/.rbenv/shims:/root/.rbenv/bin:/usr/bin:\$PATH
EnvironmentFile=/etc/sure/.env
ExecStartPre=/opt/sure/bin/rails db:prepare
ExecStart=/opt/sure/bin/rails server
Restart=always
RestartSec=5
TimeoutStartSec=300
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

  cat << EOF > /etc/systemd/system/sure-worker.service
[Unit]
Description=Sure Background Worker (Sidekiq)
After=network.target redis-server.service

[Service]
Type=simple
WorkingDirectory=/opt/sure
Environment=RAILS_ENV=production
Environment=BUNDLE_DEPLOYMENT=1
Environment=BUNDLE_WITHOUT=development
Environment=PATH=/root/.rbenv/shims:/root/.rbenv/bin:/usr/bin:/usr/local/bin:/sbin:/bin
EnvironmentFile=/etc/sure/.env
ExecStart=/opt/sure/bin/bundle exec sidekiq -e production
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now sure sure-worker
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

  if [[ ! -d /opt/sure ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "Sure" "we-promise/sure"; then
    if [[ ! -f /etc/systemd/system/sure-worker.service ]]; then
      cat << EOF > /etc/systemd/system/sure-worker.service
[Unit]
Description=Sure Background Worker (Sidekiq)
After=network.target redis-server.service

[Service]
Type=simple
WorkingDirectory=/opt/sure
Environment=RAILS_ENV=production
Environment=BUNDLE_DEPLOYMENT=1
Environment=BUNDLE_WITHOUT=development
Environment=PATH=/root/.rbenv/shims:/root/.rbenv/bin:/usr/bin:/usr/local/bin:/sbin:/bin
EnvironmentFile=/etc/sure/.env
ExecStart=/opt/sure/bin/bundle exec sidekiq -e production
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
      systemctl enable -q sure-worker
      msg_info "Stopping Service"
      $STD systemctl stop sure
      msg_ok "Stopped Service"
    else
      msg_info "Stopping services"
      $STD systemctl stop sure-worker sure
      msg_ok "Stopped services"
    fi

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "Sure" "we-promise/sure" "tarball" "latest" "/opt/sure"
    RUBY_VERSION=$(cat /opt/sure/.ruby-version) RUBY_INSTALL_RAILS=false HOME=/root setup_ruby

    msg_info "Updating Sure"
    # shellcheck disable=SC1090
    # User profile sourced for rbenv PATH - shellcheck cannot follow
    source ~/.profile
    cd /opt/sure || exit
    export RAILS_ENV=production
    export BUNDLE_DEPLOYMENT=1
    export BUNDLE_WITHOUT=development
    $STD ./bin/bundle install
    $STD ./bin/bundle exec bootsnap precompile --gemfile -j 0
    $STD ./bin/bundle exec bootsnap precompile -j 0 app/ lib/
    export SECRET_KEY_BASE_DUMMY=1 && $STD ./bin/rails assets:precompile
    unset SECRET_KEY_BASE_DUMMY
    msg_ok "Updated Sure"

    msg_info "Starting Services"
    systemctl start sure sure-worker
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
