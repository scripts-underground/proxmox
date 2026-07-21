#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: wimb0 (wimb0)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/NLnetLabs/unbound

# shellcheck disable=SC2034
APP="Unbound"
var_tags="${var_tags:-dns}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Unbound"
  mkdir -p /etc/unbound/unbound.conf.d
  cat << EOF > /etc/unbound/unbound.conf.d/unbound.conf
server:
  interface: 0.0.0.0
  port: 5335
  do-ip6: no
  hide-identity: yes
  hide-version: yes
  harden-referral-path: yes
  cache-min-ttl: 300
  cache-max-ttl: 14400
  serve-expired: yes
  serve-expired-ttl: 3600
  prefetch: yes
  prefetch-key: yes
  target-fetch-policy: "3 2 1 1 1"
  unwanted-reply-threshold: 10000000
  rrset-cache-size: 256m
  msg-cache-size: 128m
  so-rcvbuf: 1m
  private-address: 192.168.0.0/16
  private-address: 169.254.0.0/16
  private-address: 172.16.0.0/12
  private-address: 10.0.0.0/8
  private-address: fd00::/8
  private-address: fe80::/10
  access-control: 192.168.0.0/16 allow
  access-control: 172.16.0.0/12 allow
  access-control: 10.0.0.0/8 allow
  access-control: 127.0.0.1/32 allow
  chroot: ""
  logfile: /var/log/unbound.log
EOF

  $STD apt install -y \
    unbound \
    unbound-host

  touch /var/log/unbound.log
  chown unbound:unbound /var/log/unbound.log
  sleep 5
  systemctl restart unbound
  msg_ok "Installed Unbound"

  msg_info "Configuring Logrotate"
  cat << EOF > /etc/logrotate.d/unbound
/var/log/unbound.log {
  daily
  rotate 7
  missingok
  notifempty
  compress
  delaycompress
  sharedscripts
  create 644
  postrotate
    /usr/sbin/unbound-control log_reopen
  endscript
}
EOF
  systemctl restart logrotate
  msg_ok "Configured Logrotate"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:5335${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /etc/unbound ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating Unbound"
  $STD apt update
  $STD apt -y upgrade
  msg_ok "Updated Unbound"
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
