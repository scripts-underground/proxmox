#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: 007hacky007
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.squid-cache.org/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Squid"
var_tags="${var_tags:-proxy}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Configuring Squid"
  mkdir -p /etc/squid
  cat << EOF > /etc/squid/squid.conf
acl localnet src 0.0.0.1-0.255.255.255
acl localnet src 10.0.0.0/8
acl localnet src 100.64.0.0/10
acl localnet src 169.254.0.0/16
acl localnet src 172.16.0.0/12
acl localnet src 192.168.0.0/16
acl localnet src fc00::/7
acl localnet src fe80::/10

acl SSL_ports port 443
acl Safe_ports port 80
acl Safe_ports port 21
acl Safe_ports port 443
acl Safe_ports port 70
acl Safe_ports port 210
acl Safe_ports port 1025-65535
acl Safe_ports port 280
acl Safe_ports port 488
acl Safe_ports port 591
acl Safe_ports port 777
acl CONNECT method CONNECT

http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports
http_access allow localhost manager
http_access deny manager

auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwords
auth_param basic realm proxy
acl authenticated proxy_auth REQUIRED
http_access allow authenticated
http_access deny all

http_port 3128

coredump_dir /var/spool/squid

refresh_pattern ^ftp:        1440    20%    10080
refresh_pattern ^gopher:     1440    0%     1440
refresh_pattern -i (/cgi-bin/|\\?) 0  0%     0
refresh_pattern .            0       20%    4320

# Privacy / hardening
httpd_suppress_version_string on
visible_hostname $(hostname)
forwarded_for delete
request_header_access X-Forwarded-For deny all
EOF
  msg_ok "Configured Squid"

  msg_info "Installing Dependencies"
  $STD apt install -y \
    squid \
    apache2-utils
  msg_ok "Installed Dependencies"

  msg_info "Configuring Squid Authentication"
  touch /etc/squid/passwords
  chown proxy:proxy /etc/squid/passwords
  chmod 640 /etc/squid/passwords
  $STD squid -k parse
  msg_ok "Configured Squid Authentication"

  msg_info "Starting Service"
  systemctl enable -q --now squid
  msg_ok "Started Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Proxy endpoint:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}${IP}:3128${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /etc/squid/squid.conf ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating Squid"
  $STD apt update
  $STD apt upgrade -y
  msg_ok "Updated Squid"

  msg_info "Validating Squid Configuration"
  $STD squid -k parse
  msg_ok "Validated Squid Configuration"

  msg_info "Restarting Squid"
  systemctl restart squid
  msg_ok "Restarted Squid"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
