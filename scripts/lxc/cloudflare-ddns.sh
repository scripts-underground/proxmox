#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: edoardop13
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/favonia/cloudflare-ddns

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Cloudflare-DDNS"
var_tags="${var_tags:-network}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-3}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  setup_go
  msg_ok "Installed Dependencies"

  msg_info "Configuring Application"
  var_cf_api_token="default"
  read -r -p "${TAB3}Enter the Cloudflare API token: " var_cf_api_token

  var_cf_domains="default"
  read -r -p "${TAB3}Enter the domains separated with a comma (*.example.org,www.example.org): " var_cf_domains

  var_cf_proxied="false"
  while true; do
    read -r -p "${TAB3}Proxied? (y/n): " answer
    case "$answer" in
      [Yy]*)
        var_cf_proxied="true"
        break
        ;;
      [Nn]*)
        var_cf_proxied="false"
        break
        ;;
      *) echo "Please answer y or n." ;;
    esac
  done

  var_cf_ip6_provider="none"
  while true; do
    read -r -p "${TAB3}Enable IPv6 support? (y/n): " answer
    case "$answer" in
      [Yy]*)
        var_cf_ip6_provider="cloudflare.trace"
        break
        ;;
      [Nn]*)
        var_cf_ip6_provider="none"
        break
        ;;
      *) echo "Please answer y or n." ;;
    esac
  done
  msg_ok "Configured Application"

  msg_info "Setting up Service"
  mkdir -p /root/go
  cat << EOF > /etc/systemd/system/cloudflare-ddns.service
[Unit]
Description=Cloudflare DDNS Service
After=network.target

[Service]
Environment="CLOUDFLARE_API_TOKEN=${var_cf_api_token}"
Environment="DOMAINS=${var_cf_domains}"
Environment="PROXIED=${var_cf_proxied}"
Environment="IP6_PROVIDER=${var_cf_ip6_provider}"
Environment="GOPATH=/root/go"
Environment="GOCACHE=/tmp/go-build"
ExecStart=/usr/local/go/bin/go run github.com/favonia/cloudflare-ddns/cmd/ddns@latest
Restart=always
RestartSec=300

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now cloudflare-ddns
  msg_ok "Setup Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}Cloudflare DDNS is running as a service and will update your DNS records periodically.${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /etc/systemd/system/cloudflare-ddns.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_error "There is no update function for ${APP}."
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
