#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tremor021
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.zerotier.com/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Zerotier-One"
var_tags="${var_tags:-networking}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_warn "WARNING: This script will run an external installer from a third-party source (https://install.zerotier.com)."
  msg_warn "The following code is NOT maintained or audited by our repository."
  msg_warn "If you have any doubts or concerns, please review the installer code before proceeding:"
  msg_custom "${TAB3}${GATEWAY}${BGN}${CL}" "\e[1;34m" "→  https://install.zerotier.com"
  echo
  read -r -p "${TAB3}Do you want to continue? [y/N]: " CONFIRM
  if [[ ! $CONFIRM =~ ^([yY][eE][sS]|[yY])$ ]]; then
    msg_error "Aborted by user. No changes have been made."
    exit 10
  fi

  msg_info "Setting up Zerotier-One"
  curl -fsSL https://raw.githubusercontent.com/zerotier/ZeroTierOne/main/doc/contact%40zerotier.com.gpg | gpg --import > /dev/null 2>&1
  curl -fsSL https://install.zerotier.com -o /tmp/zerotier-install.sh
  if gpg --verify /tmp/zerotier-install.sh > /dev/null 2>&1; then
    $STD bash /tmp/zerotier-install.sh
  else
    msg_warn "Could not verify signature of Zerotier-One install script. Exiting..."
    exit 250
  fi
  msg_ok "Setup Zerotier-One"

  msg_info "Setting up UI"
  if [[ "$(get_system_arch)" == "arm64" ]]; then
    $STD apt install -y build-essential python3 openssl
    NODE_VERSION="20" setup_nodejs
    curl -fsSL "https://github.com/key-networks/ztncui/archive/refs/heads/master.tar.gz" -o /tmp/ztncui.tar.gz
    $STD tar -xzf /tmp/ztncui.tar.gz -C /tmp
    mkdir -p /opt/key-networks
    cp -r /tmp/ztncui-master/src /opt/key-networks/ztncui
    cd /opt/key-networks/ztncui || exit
    $STD npm install --omit=dev
    cp etc/default.passwd etc/passwd
    create_self_signed_cert "ztncui"
    mkdir -p etc/tls
    cp /etc/ssl/ztncui/ztncui.key etc/tls/privkey.pem
    cp /etc/ssl/ztncui/ztncui.crt etc/tls/fullchain.pem
    id -u ztncui &> /dev/null || useradd --system --home-dir /opt/key-networks/ztncui --shell /usr/sbin/nologin ztncui
    chown -R ztncui:ztncui /opt/key-networks/ztncui
    cat << 'EOF' > /lib/systemd/system/ztncui.service
[Unit]
Description=ztncui - ZeroTier network controller user interface
Documentation=https://key-networks.com
After=network.target

[Service]
Type=simple
User=ztncui
WorkingDirectory=/opt/key-networks/ztncui
ExecStart=/usr/bin/node /opt/key-networks/ztncui/bin/www
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable -q ztncui
  else
    curl -fsSL -o /tmp/ztncui.deb https://s3-us-west-1.amazonaws.com/key-networks/deb/ztncui/1/x86_64/ztncui_0.8.14_amd64.deb
    $STD dpkg -i /tmp/ztncui.deb
  fi
  sh -c "echo ZT_TOKEN=$(cat /var/lib/zerotier-one/authtoken.secret) > /opt/key-networks/ztncui/.env"
  echo HTTPS_PORT=3443 >> /opt/key-networks/ztncui/.env
  echo NODE_ENV=production >> /opt/key-networks/ztncui/.env
  chmod 400 /opt/key-networks/ztncui/.env
  chown ztncui:ztncui /opt/key-networks/ztncui/.env
  systemctl restart ztncui
  msg_ok "Setup UI"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}https://${IP}:3443${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /usr/sbin/zerotier-one ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Stopping Service"
  systemctl stop zerotier-one
  msg_ok "Stopping Service"

  msg_info "Updating Zerotier-One"
  $STD apt update
  $STD apt upgrade -y
  msg_ok "Updated Zerotier-One"

  msg_info "Starting Service"
  systemctl start zerotier-one
  msg_ok "Started Service"
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
