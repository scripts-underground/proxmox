#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: bvdberg01
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://netboxlabs.com/ | Github: https://github.com/netbox-community/netbox

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="NetBox"
var_tags="${var_tags:-network}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    apache2 \
    redis-server \
    build-essential \
    libxml2-dev \
    libxslt1-dev \
    libffi-dev \
    libpq-dev \
    libssl-dev \
    zlib1g-dev
  msg_ok "Installed Dependencies"

  PG_VERSION="16" setup_postgresql
  PG_DB_NAME="netbox" PG_DB_USER="netbox" setup_postgresql_db

  msg_info "Installing Python"
  $STD apt install -y \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev
  msg_ok "Installed Python"

  fetch_and_deploy_gh_release "netbox" "netbox-community/netbox" "tarball"

  msg_info "Configuring NetBox (Patience)"
  cd /opt/netbox || exit
  mkdir -p /opt/netbox/netbox/media

  $STD adduser --system --group netbox
  chown -R netbox /opt/netbox/netbox

  mv /opt/netbox/netbox/netbox/configuration_example.py /opt/netbox/netbox/netbox/configuration.py

  SECRET_KEY=$(python3 /opt/netbox/netbox/generate_secret_key.py)
  ESCAPED_SECRET_KEY=$(printf '%s\n' "$SECRET_KEY" | sed 's/[&/\]/\\&/g')

  sed -i -e 's/ALLOWED_HOSTS = \[\]/ALLOWED_HOSTS = ["*"]/' \
    -e "s|SECRET_KEY = ''|SECRET_KEY = '${ESCAPED_SECRET_KEY}'|" \
    -e "/DATABASES = {/,/}/s/'USER': '[^']*'/'USER': '$PG_DB_USER'/" \
    -e "/DATABASES = {/,/}/s/'PASSWORD': '[^']*'/'PASSWORD': '$PG_DB_PASS'/" /opt/netbox/netbox/netbox/configuration.py

  $STD /opt/netbox/upgrade.sh
  ln -s /opt/netbox/contrib/netbox-housekeeping.sh /etc/cron.daily/netbox-housekeeping

  mv /opt/netbox/contrib/apache.conf /etc/apache2/sites-available/netbox.conf
  $STD openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/netbox.key -out /etc/ssl/certs/netbox.crt -subj "/C=US/O=NetBox/OU=Certificate/CN=localhost"
  $STD a2enmod ssl proxy proxy_http headers rewrite
  $STD a2ensite netbox
  systemctl restart apache2

  mv /opt/netbox/contrib/gunicorn.py /opt/netbox/gunicorn.py
  mv /opt/netbox/contrib/*.service /etc/systemd/system/
  systemctl daemon-reload
  systemctl enable -q --now netbox netbox-rq
  echo -e "Netbox Secret: \e[32m$SECRET_KEY\e[0m" >> ~/netbox.creds
  msg_ok "Configured NetBox"

  msg_info "Setting up Django Admin"
  DJANGO_USER=Admin
  DJANGO_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | cut -c1-13)

  source /opt/netbox/venv/bin/activate
  $STD python3 /opt/netbox/netbox/manage.py shell << EOF
from django.contrib.auth import get_user_model
UserModel = get_user_model()
user = UserModel.objects.create_user('$DJANGO_USER', password='$DJANGO_PASS')
user.is_superuser = True
user.is_staff = True
user.save()
EOF
  cat << EOF >> ~/netbox.creds

Netbox-Django-Credentials
Django User: $DJANGO_USER
Django Password: $DJANGO_PASS
EOF
  msg_ok "Setup Django Admin"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}https://${IP}${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /etc/systemd/system/netbox.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "netbox" "netbox-community/netbox"; then
    msg_info "Stopping Services"
    systemctl stop netbox netbox-rq
    msg_ok "Stopped Services"

    msg_info "Backing up NetBox configurations"
    mv /opt/netbox/ /opt/netbox-backup
    msg_ok "Backed up NetBox configurations"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "netbox" "netbox-community/netbox" "tarball"

    cp -r /opt/netbox-backup/netbox/netbox/configuration.py /opt/netbox/netbox/netbox/
    cp -r /opt/netbox-backup/netbox/{media,scripts,reports}/ /opt/netbox/netbox/
    cp -r /opt/netbox-backup/gunicorn.py /opt/netbox/
    [[ -f /opt/netbox-backup/local_requirements.txt ]] && cp -r /opt/netbox-backup/local_requirements.txt /opt/netbox/
    [[ -f /opt/netbox-backup/netbox/netbox/ldap_config.py ]] && cp -r /opt/netbox-backup/netbox/netbox/ldap_config.py /opt/netbox/netbox/netbox/

    $STD /opt/netbox/upgrade.sh
    rm -r /opt/netbox-backup

    msg_info "Starting Services"
    systemctl start netbox netbox-rq
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
