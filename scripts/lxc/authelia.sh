#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: thost96 (thost96)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.authelia.com/ | Github: https://github.com/authelia/authelia

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Authelia"
var_tags="${var_tags:-authenticator}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  fetch_and_deploy_gh_release "authelia" "authelia/authelia" "binary"

  msg_info "Setting Authelia up"

  DOMAIN="${var_domain:-$(hostname -I | awk '{print $1}')}"
  DOMAIN="${DOMAIN:-localhost}"
  mkdir -p /etc/authelia
  touch /etc/authelia/emails.txt
  JWT_SECRET=$(openssl rand -hex 64)
  SESSION_SECRET=$(openssl rand -hex 64)
  STORAGE_KEY=$(openssl rand -hex 64)

  if [[ "$DOMAIN" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    AUTHELIA_URL="https://${DOMAIN}:9091"
  else
    AUTHELIA_URL="https://auth.${DOMAIN}"
  fi
  echo "$AUTHELIA_URL" > /etc/authelia/.authelia_url

  cat << EOF > /etc/authelia/users.yml
users:
  authelia:
    disabled: false
    displayname: "Authelia Admin"
    password: "\$argon2id\$v=19\$m=65536,t=3,p=4\$ZBopMzXrzhHXPEZxRDVT2w\$SxWm96DwhOsZyn34DLocwQEIb4kCDsk632PuiMdZnig"
    groups: []
EOF
  cat << EOF > /etc/authelia/configuration.yml
authentication_backend:
  file:
    path: /etc/authelia/users.yml
access_control:
  default_policy: one_factor
session:
  secret: "${SESSION_SECRET}"
  name: 'authelia_session'
  same_site: 'lax'
  inactivity: '5m'
  expiration: '1h'
  remember_me: '1M'
  cookies:
    - domain: "${DOMAIN}"
      authelia_url: "${AUTHELIA_URL}"
storage:
  encryption_key: "${STORAGE_KEY}"
  local:
    path: /etc/authelia/db.sqlite
identity_validation:
  reset_password:
    jwt_secret: "${JWT_SECRET}"
    jwt_lifespan: '5 minutes'
    jwt_algorithm: 'HS256'
notifier:
  filesystem:
    filename: /etc/authelia/emails.txt
EOF
  touch /etc/authelia/emails.txt
  chown -R authelia:authelia /etc/authelia
  systemctl enable -q --now authelia
  msg_ok "Authelia Setup completed"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:9091 or https://auth.YOURDOMAIN${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /etc/authelia/ ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "authelia" "authelia/authelia"; then
    $STD apt update
    $STD apt -y upgrade
    fetch_and_deploy_gh_release "authelia" "authelia/authelia" "binary"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
