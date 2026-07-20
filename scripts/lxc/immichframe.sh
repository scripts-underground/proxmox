#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Thiago Canozzo Lahr (tclahr)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/immichFrame/ImmichFrame

APP="ImmichFrame"
var_tags="${var_tags:-photos;slideshow}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y libicu-dev libssl-dev gettext-base
  if [[ "$(get_system_arch)" == "arm64" ]]; then
    curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
    $STD bash /tmp/dotnet-install.sh --channel 8.0 --install-dir /usr/lib/dotnet8
    ln -sf /usr/lib/dotnet8/dotnet /usr/bin/dotnet
    rm -f /tmp/dotnet-install.sh
  else
    setup_deb822_repo \
      "microsoft" \
      "https://packages.microsoft.com/keys/microsoft-2025.asc" \
      "https://packages.microsoft.com/debian/13/prod/" \
      "trixie" \
      "main"
    $STD apt install -y dotnet-sdk-8.0 aspnetcore-runtime-8.0
  fi
  msg_ok "Installed Dependencies"

  NODE_VERSION="22" setup_nodejs

  fetch_and_deploy_gh_release "immichframe" "immichFrame/ImmichFrame" "tarball" "latest" "/tmp/immichframe"

  msg_info "Setting up ImmichFrame"
  ARCH=$(get_system_arch)
  DOTNET_RUNTIME="linux-x64"
  [[ "$ARCH" == "arm64" ]] && DOTNET_RUNTIME="linux-arm64"
  mkdir -p /opt/immichframe
  cd /tmp/immichframe || exit
  $STD dotnet publish ImmichFrame.WebApi/ImmichFrame.WebApi.csproj \
    --configuration Release \
    --runtime "$DOTNET_RUNTIME" \
    --self-contained false \
    --output /opt/immichframe
  cd /tmp/immichframe/immichFrame.Web || exit
  $STD npm ci
  $STD npm run build
  cp -r build/* /opt/immichframe/wwwroot
  rm -rf /tmp/immichframe
  mkdir -p /opt/immichframe/Config
  curl -fsSL "https://raw.githubusercontent.com/immichFrame/ImmichFrame/main/docker/Settings.example.yml" -o /opt/immichframe/Config/Settings.yml
  useradd -r -s /sbin/nologin -d /opt/immichframe -M immichframe
  chown -R immichframe:immichframe /opt/immichframe
  msg_ok "Setup ImmichFrame"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/immichframe.service
[Unit]
Description=ImmichFrame Digital Photo Frame
After=network.target

[Service]
Type=simple
User=immichframe
Group=immichframe
WorkingDirectory=/opt/immichframe
ExecStart=/usr/bin/dotnet /opt/immichframe/ImmichFrame.WebApi.dll
Environment=ASPNETCORE_URLS=http://0.0.0.0:8080
Environment=ASPNETCORE_ENVIRONMENT=Production
Environment=DOTNET_CONTENTROOT=/opt/immichframe
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=immichframe

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now immichframe
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8080${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/immichframe ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "immichframe" "immichFrame/ImmichFrame"; then
    msg_info "Stopping Service"
    systemctl stop immichframe
    msg_ok "Stopped Service"

    msg_info "Backing up Configuration"
    cp -r /opt/immichframe/Config /tmp/immichframe_config.bak
    msg_ok "Backed up Configuration"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "immichframe" "immichFrame/ImmichFrame" "tarball" "latest" "/tmp/immichframe"

    msg_info "Setting up ImmichFrame"
    ARCH=$(get_system_arch)
    DOTNET_RUNTIME="linux-x64"
    [[ "$ARCH" == "arm64" ]] && DOTNET_RUNTIME="linux-arm64"
    cd /tmp/immichframe || exit
    $STD dotnet publish ImmichFrame.WebApi/ImmichFrame.WebApi.csproj \
      --configuration Release \
      --runtime "$DOTNET_RUNTIME" \
      --self-contained false \
      --output /opt/immichframe

    cd /tmp/immichframe/immichFrame.Web || exit
    $STD npm ci --silent
    $STD npm run build
    rm -rf /opt/immichframe/wwwroot/*
    cp -r build/* /opt/immichframe/wwwroot
    rm -rf /tmp/immichframe
    msg_ok "Setup ImmichFrame"

    msg_info "Restoring Configuration"
    cp -r /tmp/immichframe_config.bak/* /opt/immichframe/Config/
    rm -rf /tmp/immichframe_config.bak
    chown -R immichframe:immichframe /opt/immichframe
    msg_ok "Restored Configuration"

    msg_info "Starting Service"
    systemctl start immichframe
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
