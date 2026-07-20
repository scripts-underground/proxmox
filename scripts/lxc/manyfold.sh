#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: bvdberg01 | Co-Author: SunFlowerOwl
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/manyfold3d/manyfold

# shellcheck disable=SC2034
APP="Manyfold"
var_tags="${var_tags:-3d}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-15}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    f3d \
    git \
    libarchive-dev \
    libassimp-dev \
    libmariadb-dev \
    nginx \
    redis-server
  msg_ok "Installed Dependencies"

  setup_imagemagick
  PG_VERSION="16" setup_postgresql
  PG_DB_NAME="manyfold" PG_DB_USER="manyfold" setup_postgresql_db
  NODE_VERSION="24" NODE_MODULE="corepack,yarn" setup_nodejs

  fetch_and_deploy_gh_release "manyfold" "manyfold3d/manyfold" "tarball" "latest" "/opt/manyfold/app"

  useradd -m -s /usr/bin/bash manyfold

  RUBY_INSTALL_VERSION=$(cat /opt/manyfold/app/.ruby-version)
  RUBY_VERSION=${RUBY_INSTALL_VERSION} RUBY_INSTALL_RAILS="true" HOME=/home/manyfold setup_ruby

  msg_info "Configuring Manyfold"
  YARN_VERSION=$(grep '"packageManager":' /opt/manyfold/app/package.json | sed -E 's/.*"(yarn@[0-9\.]+)".*/\1/')
  RELEASE=$(get_latest_github_release "manyfold3d/manyfold")
  cat << EOF > /opt/manyfold/.env
export APP_VERSION=${RELEASE}
export GUID=1002
export PUID=1001
export PUBLIC_PORT=5000
export REDIS_URL=redis://127.0.0.1:6379/1
export DATABASE_ADAPTER=postgresql
export DATABASE_HOST=127.0.0.1
export DATABASE_USER=${PG_DB_USER}
export DATABASE_PASSWORD=${PG_DB_PASS}
export DATABASE_NAME=${PG_DB_NAME}
export DATABASE_CONNECTION_POOL=16
export MULTIUSER=enabled
export HTTPS_ONLY=false
export RAILS_ENV=production
EOF
  cat << 'SETUPEOF' > /opt/manyfold/user_setup.sh
#!/bin/bash

source /opt/manyfold/.env
export PATH="/home/manyfold/.rbenv/bin:$PATH"
eval "$(/home/manyfold/.rbenv/bin/rbenv init - bash)"
cd /opt/manyfold/app
rbenv global $RUBY_INSTALL_VERSION
gem install bundler
bundle install
gem install sidekiq
gem install foreman

rm -f /opt/manyfold/app/config/credentials.yml.enc
corepack prepare $YARN_VERSION --activate
corepack use $YARN_VERSION
export VISUAL="code --wait"
bin/rails credentials:edit
bin/rails db:migrate
bin/rails assets:precompile
SETUPEOF
  $STD mkdir -p /opt/manyfold_data
  msg_ok "Configured Manyfold"

  msg_info "Installing Manyfold"
  chown -R manyfold:manyfold {/home/manyfold,/opt/manyfold}
  chmod +x /opt/manyfold/user_setup.sh

  $STD sudo -u manyfold bash /opt/manyfold/user_setup.sh
  rm -f /opt/manyfold/user_setup.sh
  msg_ok "Installed Manyfold"

  msg_info "Creating Services"
  source /opt/manyfold/.env
  export PATH="/home/manyfold/.rbenv/shims:/home/manyfold/.rbenv/bin:$PATH"
  $STD foreman export systemd /etc/systemd/system -a manyfold -u manyfold -f /opt/manyfold/app/Procfile
  for f in /etc/systemd/system/manyfold-*.service; do
    sed -i "s|/bin/bash -lc '|/bin/bash -lc 'source /opt/manyfold/.env \&\& |" "$f"
  done
  systemctl enable -q --now manyfold.target manyfold-rails.1 manyfold-default_worker.1 manyfold-performance_worker.1
  cat << 'NGINXEOF' > /etc/nginx/sites-available/manyfold.conf
server {
    listen 80;
    server_name manyfold;
    root /opt/manyfold/app/public;

    location /cable {
        proxy_pass http://127.0.0.1:5000;

        proxy_set_header Host $http_host;
        proxy_set_header X-Forwarded-Host $http_host;
        proxy_set_header X-Forwarded-Port $server_port;

        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location / {
        try_files $uri/index.html $uri @rails;
    }

    location @rails {
        proxy_pass http://127.0.0.1:5000;

        proxy_set_header Host $http_host;
        proxy_set_header X-Forwarded-Host $http_host;
        proxy_set_header X-Forwarded-Port $server_port;

        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
NGINXEOF
  ln -s /etc/nginx/sites-available/manyfold.conf /etc/nginx/sites-enabled/
  rm -f /etc/nginx/sites-enabled/default
  $STD systemctl reload nginx
  msg_ok "Created Services"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:80${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/manyfold ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  NODE_VERSION="24" NODE_MODULE="corepack,yarn" setup_nodejs
  ensure_dependencies f3d

  if check_for_gh_release "manyfold" "manyfold3d/manyfold"; then
    msg_info "Stopping Services"
    systemctl stop manyfold.target manyfold-rails.1 manyfold-default_worker.1 manyfold-performance_worker.1
    msg_ok "Stopped Services"

    msg_info "Backing up Data"
    CURRENT_VERSION=$(grep -oP 'APP_VERSION=\K[^ ]+' /opt/manyfold/.env || echo "unknown")
    cp -r /opt/manyfold/app/storage /opt/manyfold_storage_backup 2> /dev/null || true
    cp -r /opt/manyfold/app/tmp /opt/manyfold_tmp_backup 2> /dev/null || true
    $STD tar -czf "/opt/manyfold_${CURRENT_VERSION}_backup.tar.gz" -C /opt/manyfold app
    msg_ok "Backed up Data"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "manyfold" "manyfold3d/manyfold" "tarball" "latest" "/opt/manyfold/app"

    msg_info "Configuring Manyfold"
    RUBY_INSTALL_VERSION=$(cat /opt/manyfold/app/.ruby-version)
    YARN_VERSION=$(grep '"packageManager":' /opt/manyfold/app/package.json | sed -E 's/.*"(yarn@[0-9\.]+)".*/\1/')
    RELEASE=$(get_latest_github_release "manyfold3d/manyfold")
    sed -i "s/^export APP_VERSION=.*/export APP_VERSION=$RELEASE/" "/opt/manyfold/.env"
    msg_ok "Configured Manyfold"

    RUBY_VERSION=${RUBY_INSTALL_VERSION} RUBY_INSTALL_RAILS="true" HOME=/home/manyfold setup_ruby

    msg_info "Restoring Data"
    rm -rf /opt/manyfold/app/{storage,tmp}
    cp -r /opt/manyfold_storage_backup /opt/manyfold/app/storage 2> /dev/null || true
    cp -r /opt/manyfold_tmp_backup /opt/manyfold/app/tmp 2> /dev/null || true
    chown -R manyfold:manyfold {/home/manyfold,/opt/manyfold}
    chown -R manyfold:manyfold /opt/manyfold/app/storage /opt/manyfold/app/tmp /opt/manyfold/app/config
    rm -rf /opt/manyfold_storage_backup /opt/manyfold_tmp_backup
    msg_ok "Restored Data"

    msg_info "Installing Manyfold"
    sudo -u manyfold bash -c '
      source /opt/manyfold/.env
      export PATH="/home/manyfold/.rbenv/bin:$PATH"
      eval "$(/home/manyfold/.rbenv/bin/rbenv init - bash)"
      cd /opt/manyfold/app
      gem install bundler sidekiq foreman
      bundle install
      corepack prepare '"$YARN_VERSION"' --activate
      corepack use '"$YARN_VERSION"'
      rm -f config/credentials.yml.enc config/master.key
      EDITOR=/bin/true bin/rails credentials:edit
      bin/rails db:migrate
      bin/rails assets:precompile
    '
    msg_ok "Installed Manyfold"

    msg_info "Restarting Services"
    source /opt/manyfold/.env
    export PATH="/home/manyfold/.rbenv/shims:/home/manyfold/.rbenv/bin:$PATH"
    $STD foreman export systemd /etc/systemd/system -a manyfold -u manyfold -f /opt/manyfold/app/Procfile
    for f in /etc/systemd/system/manyfold-*.service; do
      sed -i "s|/bin/bash -lc '|/bin/bash -lc 'source /opt/manyfold/.env \&\& |" "$f"
    done
    systemctl daemon-reload
    systemctl enable -q --now manyfold.target manyfold-rails.1 manyfold-default_worker.1 manyfold-performance_worker.1
    msg_ok "Restarted Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
