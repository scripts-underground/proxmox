#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/dani-garcia/vaultwarden

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Vaultwarden"
var_tags="${var_tags:-password-manager}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-6144}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    build-essential \
    pkgconf \
    libssl-dev \
    libmariadb-dev-compat \
    libpq-dev \
    argon2 \
    ssl-cert
  msg_ok "Installed Dependencies"

  setup_rust
  fetch_and_deploy_gh_release "vaultwarden" "dani-garcia/vaultwarden" "tarball" "latest" "/tmp/vaultwarden-src"

  msg_info "Building Vaultwarden (Patience)"
  cd /tmp/vaultwarden-src || exit
  VW_VERSION=$(get_latest_github_release "dani-garcia/vaultwarden")
  export VW_VERSION
  $STD cargo build --features "sqlite,mysql,postgresql" --release
  msg_ok "Built Vaultwarden"

  msg_info "Setting up Vaultwarden"
  $STD addgroup --system vaultwarden
  $STD adduser --system --home /opt/vaultwarden --shell /usr/sbin/nologin --no-create-home --gecos 'vaultwarden' --ingroup vaultwarden --disabled-login --disabled-password vaultwarden
  mkdir -p /opt/vaultwarden/{bin,data,web-vault}
  cp target/release/vaultwarden /opt/vaultwarden/bin/
  cd ~ || exit && rm -rf /tmp/vaultwarden-src
  msg_ok "Set up Vaultwarden"

  fetch_and_deploy_gh_release "vaultwarden_webvault" "dani-garcia/bw_web_builds" "prebuild" "latest" "/opt/vaultwarden/web-vault" "bw_web_*.tar.gz"

  msg_info "Configuring Vaultwarden"
  cat << EOF > /opt/vaultwarden/.env
ADMIN_TOKEN=''
ROCKET_ADDRESS=0.0.0.0
ROCKET_TLS='{certs="/opt/vaultwarden/ssl-cert-snakeoil.pem",key="/opt/vaultwarden/ssl-cert-snakeoil.key"}'
DATA_FOLDER=/opt/vaultwarden/data
DATABASE_MAX_CONNS=10
WEB_VAULT_FOLDER=/opt/vaultwarden/web-vault
WEB_VAULT_ENABLED=true
EOF
  mv /etc/ssl/certs/ssl-cert-snakeoil.pem /opt/vaultwarden/
  mv /etc/ssl/private/ssl-cert-snakeoil.key /opt/vaultwarden/

  chown -R vaultwarden:vaultwarden /opt/vaultwarden/
  chown root:root /opt/vaultwarden/bin/vaultwarden
  chmod +x /opt/vaultwarden/bin/vaultwarden
  chown -R root:root /opt/vaultwarden/web-vault/
  chmod +r /opt/vaultwarden/.env
  msg_ok "Configured Vaultwarden"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/vaultwarden.service
[Unit]
Description=Bitwarden Server (Powered by Vaultwarden)
Documentation=https://github.com/dani-garcia/vaultwarden
After=network.target

[Service]
User=vaultwarden
Group=vaultwarden
EnvironmentFile=-/opt/vaultwarden/.env
ExecStart=/opt/vaultwarden/bin/vaultwarden
LimitNOFILE=65535
LimitNPROC=4096
PrivateTmp=true
PrivateDevices=true
ProtectHome=true
ProtectSystem=strict
DevicePolicy=closed
ProtectControlGroups=yes
ProtectKernelModules=yes
ProtectKernelTunables=yes
RestrictNamespaces=yes
RestrictRealtime=yes
MemoryDenyWriteExecute=yes
LockPersonality=yes
WorkingDirectory=/opt/vaultwarden
ReadWriteDirectories=/opt/vaultwarden/data
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now vaultwarden
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}https://${IP}:8000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /etc/systemd/system/vaultwarden.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  VAULT=$(get_latest_github_release "dani-garcia/vaultwarden")
  WVRELEASE=$(get_latest_github_release "dani-garcia/bw_web_builds")

  UPD=$(msg_menu "Vaultwarden Update Options" \
    "1" "Update VaultWarden + Web-Vault" \
    "2" "Set Admin Token")

  if [ "$UPD" == "1" ]; then
    INSTALLED_VERSION="$(/opt/vaultwarden/bin/vaultwarden --version 2> /dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)"
    if [[ -n "$INSTALLED_VERSION" ]] &&
      ! grep -qxF "$INSTALLED_VERSION" "$HOME/.vaultwarden" 2> /dev/null; then
      printf '%s\n' "$INSTALLED_VERSION" > "$HOME/.vaultwarden"
    fi
    if check_for_gh_release "vaultwarden" "dani-garcia/vaultwarden"; then
      msg_info "Stopping Service"
      systemctl stop vaultwarden
      msg_ok "Stopped Service"

      fetch_and_deploy_gh_release "vaultwarden" "dani-garcia/vaultwarden" "tarball" "latest" "/tmp/vaultwarden-src"

      msg_info "Updating VaultWarden to $VAULT (Patience)"
      cd /tmp/vaultwarden-src || exit
      VW_VERSION="$VAULT"
      export VW_VERSION
      $STD cargo build --features "sqlite,mysql,postgresql" --release
      if [[ -f /usr/bin/vaultwarden ]]; then
        cp target/release/vaultwarden /usr/bin/
      else
        cp target/release/vaultwarden /opt/vaultwarden/bin/
      fi
      cd ~ || exit && rm -rf /tmp/vaultwarden-src
      msg_ok "Updated VaultWarden to ${VAULT}"

      msg_info "Starting Service"
      systemctl start vaultwarden
      msg_ok "Started Service"
    else
      msg_ok "VaultWarden is already up-to-date"
    fi

    if check_for_gh_release "vaultwarden_webvault" "dani-garcia/bw_web_builds"; then
      msg_info "Stopping Service"
      systemctl stop vaultwarden
      msg_ok "Stopped Service"

      msg_info "Updating Web-Vault to $WVRELEASE"
      rm -rf /opt/vaultwarden/web-vault
      mkdir -p /opt/vaultwarden/web-vault

      fetch_and_deploy_gh_release "vaultwarden_webvault" "dani-garcia/bw_web_builds" "prebuild" "latest" "/opt/vaultwarden/web-vault" "bw_web_*.tar.gz"

      chown -R root:root /opt/vaultwarden/web-vault/
      msg_ok "Updated Web-Vault to ${WVRELEASE}"

      msg_info "Starting Service"
      systemctl start vaultwarden
      msg_ok "Started Service"
    else
      msg_ok "Web-Vault is already up-to-date"
    fi

    msg_ok "Updated successfully!"
    exit
  fi

  if [ "$UPD" == "2" ]; then
    if [[ "${PHS_SILENT:-0}" == "1" ]]; then
      msg_warn "Set Admin Token requires interactive mode, skipping."
      exit
    fi
    read -r -s -p "Set the ADMIN_TOKEN: " NEWTOKEN
    echo ""
    if [[ -n "$NEWTOKEN" ]]; then
      ensure_dependencies argon2
      TOKEN=$(echo -n "${NEWTOKEN}" | argon2 "$(openssl rand -base64 32)" -t 2 -m 16 -p 4 -l 64 -e)
      sed -i "s|ADMIN_TOKEN=.*|ADMIN_TOKEN='${TOKEN}'|" /opt/vaultwarden/.env
      if [[ -f /opt/vaultwarden/data/config.json ]]; then
        sed -i "s|\"admin_token\":.*|\"admin_token\": \"${TOKEN}\"|" /opt/vaultwarden/data/config.json
      fi
      systemctl restart vaultwarden
      msg_ok "Admin token updated"
    fi
    exit
  fi
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
