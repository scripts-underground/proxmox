#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: CanbiZ (MickLesk)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/NagiosEnterprises/nagioscore

# shellcheck disable=SC2034
APP="Nagios"
var_tags="${var_tags:-monitoring;alerts;infrastructure}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    autoconf \
    automake \
    build-essential \
    bc \
    dc \
    gawk \
    gettext \
    gperf \
    libgd-dev \
    libmcrypt-dev \
    libnet-snmp-perl \
    libssl-dev \
    snmp \
    apache2 \
    apache2-utils
  msg_ok "Installed Dependencies"

  PHP_APACHE="YES" setup_php

  fetch_and_deploy_gh_release "nagios" "NagiosEnterprises/nagioscore" "tarball"

  msg_info "Building Nagios Core"
  cd /opt/nagios || exit
  $STD ./configure --with-httpd-conf=/etc/apache2/sites-enabled
  $STD make all
  $STD make install-groups-users
  usermod -a -G nagios www-data
  $STD make install
  $STD make install-daemoninit
  $STD make install-commandmode
  $STD make install-config
  $STD make install-webconf
  $STD a2enmod rewrite
  $STD a2enmod cgi
  msg_ok "Built Nagios Core"

  fetch_and_deploy_gh_release "nagios-plugins" "nagios-plugins/nagios-plugins" "tarball"

  msg_info "Building Nagios Plugins"
  cd /opt/nagios-plugins || exit
  $STD ./tools/setup
  $STD ./configure
  $STD make
  $STD make install
  setcap cap_net_raw+p /bin/ping
  msg_ok "Built Nagios Plugins"

  msg_info "Configuring Web Authentication"
  $STD htpasswd -bc /usr/local/nagios/etc/htpasswd.users nagiosadmin nagiosadmin
  chown root:www-data /usr/local/nagios/etc/htpasswd.users
  chmod 640 /usr/local/nagios/etc/htpasswd.users
  msg_ok "Configured Web Authentication"

  msg_info "Starting Services"
  systemctl enable -q apache2
  systemctl restart apache2
  systemctl enable -q --now nagios
  msg_ok "Started Services"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}/nagios${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /usr/local/nagios/etc/nagios.cfg ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Backing up Configuration"
  cp -a /usr/local/nagios/etc /opt/nagios-etc-backup
  msg_ok "Backed up Configuration"

  if check_for_gh_release "nagios" "NagiosEnterprises/nagioscore"; then
    msg_info "Stopping Nagios"
    systemctl stop nagios
    msg_ok "Stopped Nagios"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "nagios" "NagiosEnterprises/nagioscore" "tarball"

    msg_info "Building Nagios Core"
    cd /opt/nagios || exit
    $STD ./configure --with-httpd-conf=/etc/apache2/sites-enabled
    $STD make all
    $STD make install-groups-users
    usermod -a -G nagios www-data
    $STD make install
    $STD make install-daemoninit
    $STD make install-commandmode
    $STD make install-webconf
    $STD a2enmod rewrite
    $STD a2enmod cgi
    setcap cap_net_raw+p /bin/ping
    msg_ok "Built Nagios Core"

    msg_info "Starting Nagios"
    systemctl restart apache2
    systemctl start nagios
    msg_ok "Started Nagios"
  fi

  if check_for_gh_release "nagios-plugins" "nagios-plugins/nagios-plugins"; then
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "nagios-plugins" "nagios-plugins/nagios-plugins" "tarball"
    msg_info "Building Nagios Plugins"
    cd /opt/nagios-plugins || exit
    $STD ./tools/setup
    $STD ./configure
    $STD make
    $STD make install
    msg_ok "Built Nagios Plugins"
  fi

  msg_info "Restoring Configuration"
  rm -rf /usr/local/nagios/etc
  cp -a /opt/nagios-etc-backup /usr/local/nagios/etc
  rm -rf /opt/nagios-etc-backup
  msg_ok "Restored Configuration"
  msg_ok "Updated successfully!"
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
