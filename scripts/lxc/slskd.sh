#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: vhsdream
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/slskd/slskd/, https://github.com/mrusse/soularr

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="slskd"
var_tags="${var_tags:-arr;p2p}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y libicu-dev
  msg_ok "Installed Dependencies"

  ARCH=$(get_system_arch)
  [[ "$ARCH" == "amd64" ]] && ARCH="x64"
  fetch_and_deploy_gh_release "Slskd" "slskd/slskd" "prebuild" "latest" "/opt/slskd" "slskd-*-linux-${ARCH}.zip"

  msg_info "Configuring Slskd"
  JWT_KEY=$(openssl rand -base64 44)
  SLSKD_API_KEY=$(openssl rand -base64 44)
  cp /opt/slskd/config/slskd.example.yml /opt/slskd/config/slskd.yml
  sed -i \
    -e '/web:/,/cidr/s/^# //' \
    -e '/https:/,/port: 5031/s/false/true/' \
    -e '/port: 5030/,/socket/s/,.*$//' \
    -e '/content_path:/,/authentication/s/false/true/' \
    -e "\|api_keys|,\|cidr|s|<some.*$|$SLSKD_API_KEY|; \
      s|role: readonly|role: readwrite|; \
      s|0.0.0.0/0,::/0|& # Replace this with your subnet|" \
    -e "\|jwt:|,\|ttl|s|key: ~|key: $JWT_KEY|" \
    -e '/soulseek/,/write_queue/s/^# //' \
    -e 's/^.*picture/#&/' /opt/slskd/config/slskd.yml
  msg_ok "Configured Slskd"

  read -rp "${TAB3}Do you want to install Soularr? y/N " soularr
  if [[ ${soularr,,} =~ ^(y|yes)$ ]]; then
    PYTHON_VERSION="3.11" setup_uv
    fetch_and_deploy_gh_release "Soularr" "mrusse/soularr" "tarball" "latest" "/opt/soularr"
    cd /opt/soularr || exit
    $STD uv venv venv
    $STD source venv/bin/activate
    $STD uv pip install -r requirements.txt
    sed -i \
      -e "\|[Slskd]|,\|host_url|s|yourslskdapikeygoeshere|$SLSKD_API_KEY|" \
      -e "/host_url/s/slskd/localhost/" \
      /opt/soularr/config.ini
    cat << EOF > /opt/soularr/run.sh
#!/usr/bin/env bash

if ps aux | grep "[s]oularr.py" >/dev/null; then
  echo "Soularr is already running. Exiting..." >&2
  exit 1
fi

# Remove stale lock file from previous ungraceful exit
rm -f "/opt/soularr/.soularr.lock"

source /opt/soularr/venv/bin/activate
uv run python3 -u /opt/soularr/soularr.py --config-dir /opt/soularr 2>&1
EOF
    chmod +x /opt/soularr/run.sh
    deactivate
    msg_ok "Installed Soularr"
  fi

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/slskd.service
[Unit]
Description=Slskd Service
After=network.target
Wants=network.target

[Service]
WorkingDirectory=/opt/slskd
ExecStart=/opt/slskd/slskd --config /opt/slskd/config/slskd.yml
Restart=always

[Install]
WantedBy=multi-user.target
EOF

  if [[ -d /opt/soularr ]]; then
    cat << EOF > /etc/systemd/system/soularr.timer
[Unit]
Description=Soularr service timer
RefuseManualStart=no
RefuseManualStop=no

[Timer]
Persistent=true
# run every 10 minutes
OnCalendar=*-*-* *:0/10:00
Unit=soularr.service

[Install]
WantedBy=timers.target
EOF

    cat << EOF > /etc/systemd/system/soularr.service
[Unit]
Description=Soularr service
After=network.target slskd.service

[Service]
Type=simple
WorkingDirectory=/opt/soularr
ExecStart=/bin/bash -c /opt/soularr/run.sh

[Install]
WantedBy=multi-user.target
EOF
    msg_warn "Add your Lidarr API key to Soularr in '/opt/soularr/config.ini', then run 'systemctl enable --now soularr.timer'"
  fi
  systemctl enable -q --now slskd
  msg_ok "Created Services"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:5030${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/slskd ]]; then
    msg_error "No Slskd Installation Found!"
    exit
  fi

  if check_for_gh_release "Slskd" "slskd/slskd"; then
    msg_info "Stopping Service(s)"
    systemctl stop slskd
    [[ -f /etc/systemd/system/soularr.service ]] && systemctl stop soularr.timer soularr.service
    msg_ok "Stopped Service(s)"

    msg_info "Backing up config"
    cp /opt/slskd/config/slskd.yml /opt/slskd.yml.bak
    msg_ok "Backed up config"

    ARCH=$(get_system_arch)
    [[ "$ARCH" == "amd64" ]] && ARCH="x64"
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "Slskd" "slskd/slskd" "prebuild" "latest" "/opt/slskd" "slskd-*-linux-${ARCH}.zip"

    msg_info "Restoring config"
    mv /opt/slskd.yml.bak /opt/slskd/config/slskd.yml

    # Migrate 0.25.0 breaking config key renames
    sed -i 's/^global:/transfers:/' /opt/slskd/config/slskd.yml
    sed -i 's/^integration:/integrations:/' /opt/slskd/config/slskd.yml
    msg_ok "Restored config"

    msg_info "Starting Service(s)"
    systemctl start slskd
    [[ -f /etc/systemd/system/soularr.service ]] && systemctl start soularr.timer
    msg_ok "Started Service(s)"
    msg_ok "Updated Slskd successfully!"
  fi
  [[ -d /opt/soularr ]] && if check_for_gh_release "Soularr" "mrusse/soularr"; then
    if systemctl is-active soularr.timer > /dev/null; then
      msg_info "Stopping Timer and Service"
      systemctl stop soularr.timer soularr.service
      msg_ok "Stopped Timer and Service"
    fi

    msg_info "Backing up Soularr config"
    cp /opt/soularr/config.ini /opt/soularr_config.ini.bak
    cp /opt/soularr/run.sh /opt/soularr_run.sh.bak
    msg_ok "Backed up Soularr config"

    PYTHON_VERSION="3.11" setup_uv
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "Soularr" "mrusse/soularr" "tarball" "latest" "/opt/soularr"
    msg_info "Updating Soularr"
    cd /opt/soularr || exit
    $STD uv venv -c venv
    $STD source venv/bin/activate
    $STD uv pip install -r requirements.txt
    deactivate
    msg_ok "Updated Soularr"

    msg_info "Restoring Soularr config"
    mv /opt/soularr_config.ini.bak /opt/soularr/config.ini
    mv /opt/soularr_run.sh.bak /opt/soularr/run.sh
    msg_ok "Restored Soularr config"

    msg_info "Starting Soularr Timer"
    systemctl restart soularr.timer
    msg_ok "Started Soularr Timer"
    msg_ok "Updated Soularr successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
