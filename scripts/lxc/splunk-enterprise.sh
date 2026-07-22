#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: rcastley
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.splunk.com/en_us/download.html

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Splunk-Enterprise"
var_tags="${var_tags:-monitoring}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-40}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  echo -e "\n┌─────────────────────────────────────────────────────────────────────────┐"
  echo -e "│                          SPLUNK GENERAL TERMS                           │"
  echo -e "└─────────────────────────────────────────────────────────────────────────┘\n"
  echo -e "Before proceeding with the Splunk Enterprise installation, you must"
  echo -e "review and accept the Splunk General Terms."
  echo -e "\nPlease review the terms at:"
  echo -e "https://www.splunk.com/en_us/legal/splunk-general-terms.html"
  echo ""
  while true; do
    echo -e "Do you accept the Splunk General Terms? (y/N): \c"
    read -r response
    case $response in
      [Yy] | [Yy][Ee][Ss])
        msg_ok "Terms accepted. Proceeding with installation..."
        break
        ;;
      [Nn] | [Nn][Oo] | "")
        msg_error "Terms not accepted. Installation cannot proceed."
        msg_error "Please review the terms and run the script again if you wish to proceed."
        exit 254
        ;;
      *)
        msg_error "Invalid response. Please enter 'y' for yes or 'n' for no."
        ;;
    esac
  done

  msg_info "Installing Dependencies"
  $STD apt install -y curl
  msg_ok "Installed Dependencies"

  msg_info "Setup Splunk Enterprise"
  DOWNLOAD_URL=$(curl -s "https://www.splunk.com/en_us/download/splunk-enterprise.html" | grep -o 'data-link="[^"]*' | sed 's/data-link="//' | grep "https.*products/splunk/releases" | grep "linux-amd64\.tgz$")
  RELEASE=$(echo "$DOWNLOAD_URL" | sed 's|.*/releases/\([^/]*\)/.*|\1|')
  $STD curl -fsSL -o "splunk-enterprise.tgz" "$DOWNLOAD_URL" || {
    msg_error "Failed to download Splunk Enterprise from the provided link."
    exit 250
  }
  $STD tar -xzf "splunk-enterprise.tgz" -C /opt
  rm -f "splunk-enterprise.tgz"
  addgroup --system splunk
  adduser --system --home /opt/splunk --shell /bin/bash --ingroup splunk --no-create-home splunk
  chown -R splunk:splunk /opt/splunk
  msg_ok "Setup Splunk Enterprise v${RELEASE}"

  msg_info "Creating Splunk admin user"
  ADMIN_USER="admin"
  ADMIN_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
  cat << EOF > ~/splunk.creds
Splunk-Credentials
Username: $ADMIN_USER
Password: $ADMIN_PASS
EOF

  cat << EOF > "/opt/splunk/etc/system/local/user-seed.conf"
[user_info]
USERNAME = $ADMIN_USER
PASSWORD = $ADMIN_PASS
EOF
  msg_ok "Created Splunk admin user"

  msg_info "Starting Service"
  $STD su - splunk -c '/opt/splunk/bin/splunk start --accept-license --answer-yes --no-prompt'
  $STD /opt/splunk/bin/splunk enable boot-start -user splunk
  msg_ok "Started Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access the Splunk Enterprise Web interface using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8000${CL}"
  echo -e "${INFO}${YW}Admin credentials saved in ~/splunk.creds on the container${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/splunk ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_error "Currently we don't provide an update function for this ${APP}."
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
