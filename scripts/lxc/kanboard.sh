#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2026 scripts-underground.org
# Author: Alex Indigo (alexindigo)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/kanboard/kanboard

# shellcheck disable=SC2034
APP="Kanboard"
var_tags="${var_tags:-kanban;productivity}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_lxc_git_repo="${var_lxc_git_repo:-kanboard/kanboard}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y git php-fpm php-sqlite3 php-gd php-mbstring php-xml php-zip nginx
  msg_ok "Installed Dependencies"

  msg_info "Installing Kanboard"
  mkdir -p /var/www/html/kanboard
  clone_and_deploy_gh_commit "kanboard" "$var_lxc_git_repo" "main" "" "" /var/www/html/kanboard
  cp /var/www/html/kanboard/config.default.php /var/www/html/kanboard/config.php
  chown -R www-data:www-data /var/www/html/kanboard/data
  msg_ok "Installed Kanboard"

  msg_info "Configuring Nginx"
  cat << EOF > /etc/nginx/sites-available/default
server {
    listen 80 default_server;
    root /var/www/html/kanboard;
    index index.php;
    location / {
        try_files \$uri \$uri/ =404;
    }
    location ~ \.php\$ {
        fastcgi_pass unix:/var/run/php/php8.4-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }
}
EOF
  systemctl enable -q --now php8.4-fpm nginx
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
  echo -e "${INFO}${YW}Default login: admin / admin${CL}"
}

function update_script() {
  render_header
  check_container_storage
  check_container_resources

  if [[ ! -d /var/www/html/kanboard ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  cd /var/www/html/kanboard || exit
  if $STD git fetch origin main && ! git diff --quiet origin/main; then
    msg_info "Updating ${APP}"
    systemctl stop php8.4-fpm nginx
    $STD git pull origin main
    cp data/ /tmp/kb_data
    systemctl start php8.4-fpm nginx
    cp -r /tmp/kb_data data/
    rm -rf /tmp/kb_data
    msg_ok "Updated successfully!"
  else
    msg_ok "${APP} is up to date"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
