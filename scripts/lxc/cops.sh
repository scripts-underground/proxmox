#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2026 scripts-underground.org
# Author: Alex Indigo (alexindigo)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/seblucas/cops

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="COPS"
var_tags="${var_tags:-ebook}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_lxc_git_repo="${var_lxc_git_repo:-seblucas/cops}"
var_lxc_git_tag="${var_lxc_git_tag:-}"
var_lxc_pinned_commit="${var_lxc_pinned_commit:-}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y git php-fpm php-gd php-sqlite3 php-xml php-mbstring php-zip nginx
  msg_ok "Installed Dependencies"

  msg_info "Installing COPS"
  mkdir -p /var/www/html
  clone_and_deploy_gh_commit "cops" "$var_lxc_git_repo" "main" "${var_lxc_git_tag:-}" "${var_lxc_pinned_commit:-}" /var/www/html
  cat << EOF > /var/www/html/config_local.php
<?php
\$config['calibre_directory'] = '/opt/calibre-library/';
\$config['cops_title_default'] = "COPS";
\$config['cops_use_url_rewriting'] = "0";
EOF
  chown -R www-data:www-data /var/www/html
  msg_ok "Installed COPS"

  sed -i 's|root /var/www/html;|root /var/www/html; index index.php;|' /etc/nginx/sites-available/default

  msg_info "Creating Service"
  systemctl enable -q --now php8.4-fpm nginx
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
  echo -e "${INFO}${YW}Place your Calibre database in /opt/calibre-library/ or update config_local.php to point at your library path.${CL}"
}

function update_script() {
  render_header
  check_container_storage
  check_container_resources

  if [[ ! -d /var/www/html ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  cd /var/www/html || exit
  if git fetch origin main && ! git diff --quiet origin/main; then
    msg_info "Updating ${APP}"
    systemctl stop php8.4-fpm nginx
    $STD git pull origin main
    systemctl start php8.4-fpm nginx
    msg_ok "Updated successfully!"
  else
    msg_ok "${APP} is up to date"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
