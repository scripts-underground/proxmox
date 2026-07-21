#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck | Co-Author: MickLesk (Canbiz)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.rabbitmq.com/

# shellcheck disable=SC2034
APP="RabbitMQ"
var_tags="${var_tags:-mqtt}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y apt-transport-https
  msg_ok "Installed Dependencies"

  setup_deb822_repo \
    "rabbitmq" \
    "https://keys.openpgp.org/vks/v1/by-fingerprint/0A9AF2115F4687BD29803A206B73A36E6026DFCA" \
    "https://deb1.rabbitmq.com/rabbitmq-server/debian/trixie" \
    "trixie"

  msg_info "Setting up RabbitMQ"
  $STD apt install -y \
    erlang-base erlang-asn1 erlang-crypto erlang-eldap erlang-ftp \
    erlang-inets erlang-mnesia erlang-os-mon erlang-parsetools \
    erlang-public-key erlang-runtime-tools erlang-snmp erlang-ssl \
    erlang-syntax-tools erlang-tftp erlang-tools erlang-xmerl
  $STD apt install -y --fix-missing rabbitmq-server
  msg_ok "Setup RabbitMQ "

  msg_info "Starting Service"
  systemctl enable -q --now rabbitmq-server
  msg_ok "Started Service"

  msg_info "Enabling RabbitMQ Management Plugin"
  $STD rabbitmq-plugins enable rabbitmq_management
  $STD rabbitmqctl enable_feature_flag all
  msg_ok "Enabled RabbitMQ Management Plugin"

  msg_info "Creating User"
  $STD rabbitmqctl add_user proxmox proxmox
  $STD rabbitmqctl set_user_tags proxmox administrator
  $STD rabbitmqctl set_permissions -p / proxmox ".*" ".*" ".*"
  msg_ok "Created User"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:15672${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /etc/rabbitmq ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if grep -q "dl.cloudsmith.io" /etc/apt/sources.list.d/rabbitmq.list; then
    rm -f /etc/apt/sources.list.d/rabbitmq.list
    setup_deb822_repo \
      "rabbitmq" \
      "https://keys.openpgp.org/vks/v1/by-fingerprint/0A9AF2115F4687BD29803A206B73A36E6026DFCA" \
      "https://deb1.rabbitmq.com/rabbitmq-server/debian/trixie" \
      "trixie"
  fi

  msg_info "Stopping Service"
  systemctl stop rabbitmq-server
  msg_ok "Stopped Service"

  msg_info "Updating..."
  $STD apt install --only-upgrade rabbitmq-server
  msg_ok "Updated successfully!"

  msg_info "Starting Service"
  systemctl start rabbitmq-server
  msg_ok "Started Service"
  msg_ok "Updated successfully!"
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
