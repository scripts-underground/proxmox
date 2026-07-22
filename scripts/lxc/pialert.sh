#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/leiweibau/Pi.Alert/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="PiAlert"
var_tags="${var_tags:-network}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-3}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt -y install \
    apt-utils \
    avahi-utils \
    lighttpd \
    sqlite3 \
    mmdb-bin \
    arp-scan \
    dnsutils \
    net-tools \
    nbtscan \
    libwww-perl \
    nmap \
    aria2 \
    wakeonlan \
    fping \
    zip \
    libtext-csv-perl \
    cron
  msg_ok "Installed Dependencies"

  msg_info "Installing PHP Dependencies"
  $STD apt -y install \
    php \
    php-cgi \
    php-fpm \
    php-curl \
    php-xml \
    php-sqlite3
  $STD lighttpd-enable-mod fastcgi-php
  service lighttpd force-reload
  msg_ok "Installed PHP Dependencies"

  msg_info "Installing Python Dependencies"
  $STD apt -y install \
    python3-pip \
    python3-requests \
    python3-tz \
    python3-tzlocal \
    python3-aiohttp \
    python3-cryptography
  rm -rf /usr/lib/python3.*/EXTERNALLY-MANAGED
  $STD pip3 install mac-vendor-lookup
  $STD pip3 install fritzconnection
  $STD pip3 install cryptography
  $STD pip3 install pyunifi
  $STD pip3 install openwrt-luci-rpc
  $STD pip3 install asusrouter
  $STD pip3 install paho-mqtt
  msg_ok "Installed Python Dependencies"

  msg_info "Installing Pi.Alert"
  curl -fsSL https://github.com/leiweibau/Pi.Alert/raw/main/tar/pialert_latest.tar | tar xvf - -C /opt > /dev/null 2>&1
  rm -rf /var/lib/ieee-data /var/www/html/index.html
  sed -i -e 's#^sudo cp -n /usr/share/ieee-data/.* /var/lib/ieee-data/#\# &#' -e '/^sudo mkdir -p 2_backup$/s/^/# /' -e '/^sudo cp \*.txt 2_backup$/s/^/# /' -e '/^sudo cp \*.csv 2_backup$/s/^/# /' /opt/pialert/back/update_vendors.sh
  mv /var/www/html/index.lighttpd.html /var/www/html/index.lighttpd.html.old
  ln -s /usr/share/ieee-data/ /var/lib/
  ln -s /opt/pialert/install/index.html /var/www/html/index.html
  ln -s /opt/pialert/front /var/www/html/pialert
  chmod go+x /opt/pialert /opt/pialert/back/shoutrrr/x86/shoutrrr
  chgrp -R www-data /opt/pialert/db /opt/pialert/front/reports /opt/pialert/config /opt/pialert/config/pialert.conf
  chmod -R 775 /opt/pialert/db /opt/pialert/db/temp /opt/pialert/config /opt/pialert/front/reports
  touch /opt/pialert/log/pialert.vendors.log /opt/pialert/log/pialert.IP.log /opt/pialert/log/pialert.1.log /opt/pialert/log/pialert.cleanup.log /opt/pialert/log/pialert.webservices.log
  src_dir="/opt/pialert/log"
  dest_dir="/opt/pialert/front/php/server"
  for file in pialert.vendors.log pialert.IP.log pialert.1.log pialert.cleanup.log pialert.webservices.log; do
    ln -s "$src_dir/$file" "$dest_dir/$file"
  done
  sed -i 's#PIALERT_PATH\s*=\s*'\''/home/pi/pialert'\''#PIALERT_PATH           = '\''/opt/pialert'\''#' /opt/pialert/config/pialert.conf
  sed -i 's/$HOME/\/opt/g' /opt/pialert/install/pialert.cron
  crontab /opt/pialert/install/pialert.cron
  echo "python3 /opt/pialert/back/pialert.py 1" > /usr/bin/scan
  chmod +x /usr/bin/scan
  echo "/opt/pialert/back/pialert-cli set_permissions --lxc" > /usr/bin/permissions
  chmod +x /usr/bin/permissions
  echo "/opt/pialert/back/pialert-cli set_sudoers --lxc" > /usr/bin/sudoers
  chmod +x /usr/bin/sudoers
  msg_ok "Installed Pi.Alert"

  msg_info "Start Pi.Alert Scan (Patience)"
  $STD python3 /opt/pialert/back/pialert.py update_vendors
  $STD python3 /opt/pialert/back/pialert.py internet_IP
  $STD python3 /opt/pialert/back/pialert.py 1
  msg_ok "Finished Pi.Alert Scan"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}/pialert${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/pialert ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating PiAlert"
  bash -c "$(curl -fsSL https://github.com/leiweibau/Pi.Alert/raw/main/install/pialert_update.sh)" -s --lxc
  msg_ok "Updated PiAlert"
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
