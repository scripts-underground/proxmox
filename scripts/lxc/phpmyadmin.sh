#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2026 scripts-underground.org
# Author: Alex Indigo (alexindigo)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/phpmyadmin/phpmyadmin

# shellcheck disable=SC2034
APP="phpMyAdmin"
var_tags="${var_tags:-database;admin}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_lxc_git_repo="${var_lxc_git_repo:-phpmyadmin/phpmyadmin}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y php-fpm php-xml php-mbstring php-zip nginx
  msg_ok "Installed Dependencies"

  msg_info "Installing phpMyAdmin"
  fetch_and_deploy_gh_release "phpmyadmin" "$var_lxc_git_repo" "tarball" "latest" "/opt/phpmyadmin"
  mkdir -p /opt/phpmyadmin/tmp
  cp /opt/phpmyadmin/config.sample.inc.php /opt/phpmyadmin/config.inc.php
  chown -R www-data:www-data /opt/phpmyadmin
  msg_ok "Installed phpMyAdmin"

  msg_info "Configuring Nginx"
  cat << EOF > /etc/nginx/sites-available/default
server {
    listen 80 default_server;
    root /opt/phpmyadmin;
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
}

function update_script() {
  render_header
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/phpmyadmin ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "phpmyadmin" "$var_lxc_git_repo"; then
    msg_info "Updating ${APP}"
    systemctl stop php8.4-fpm nginx
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "phpmyadmin" "$var_lxc_git_repo" "tarball" "latest" "/opt/phpmyadmin"
    cp /opt/phpmyadmin/config.sample.inc.php /opt/phpmyadmin/config.inc.php
    chown -R www-data:www-data /opt/phpmyadmin
    systemctl start php8.4-fpm nginx
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
