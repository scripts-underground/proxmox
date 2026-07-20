#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Kristian Skov
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://learn.microsoft.com/en-us/aspnet/core/host-and-deploy/linux-nginx?view=aspnetcore-9.0&tabs=linux-ubuntu

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Dotnet ASP Web API"
var_tags="${var_tags:-web}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-8}"
var_os="${var_os:-ubuntu}"
var_version="${var_version:-24.04}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-0}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt-get update
  $STD apt-get install -y \
    ssh \
    software-properties-common
  $STD add-apt-repository -y ppa:dotnet/backports
  $STD apt-get install -y \
    dotnet-sdk-9.0 \
    vsftpd \
    nginx
  msg_ok "Installed Dependencies"

  var_project_name="default"
  read -r -p "${TAB3}Type the assembly name of the project: " var_project_name

  msg_info "Setting up FTP Server"
  useradd ftpuser
  FTP_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
  usermod --password "$(echo ${FTP_PASS} | openssl passwd -1 -stdin)" ftpuser
  mkdir -p /var/www/html
  usermod -d /var/www/html ftp
  usermod -d /var/www/html ftpuser
  chown ftpuser /var/www/html
  sed -i "s|#write_enable=YES|write_enable=YES|g" /etc/vsftpd.conf
  sed -i "s|#chroot_local_user=YES|chroot_local_user=NO|g" /etc/vsftpd.conf
  systemctl restart -q vsftpd.service
  cat << EOF > ~/ftp.creds
FTP-Credentials
Username: ftpuser
Password: $FTP_PASS
EOF
  msg_ok "FTP server setup completed"

  msg_info "Setting up Nginx Server"
  rm -f /var/www/html/index.nginx-debian.html
  sed "s/\$var_project_name/$var_project_name/g" > /etc/nginx/sites-available/default << 'EOF'
map $http_connection $connection_upgrade {
  "~*Upgrade" $http_connection;
  default keep-alive;
}
server {
  listen        80;
  server_name   $var_project_name.com *.$var_project_name.com;
  location / {
      proxy_pass         http://127.0.0.1:5000/;
      proxy_http_version 1.1;
      proxy_set_header   Upgrade $http_upgrade;
      proxy_set_header   Connection $connection_upgrade;
      proxy_set_header   Host $host;
      proxy_cache_bypass $http_upgrade;
      proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header   X-Forwarded-Proto $scheme;
  }
}
EOF
  systemctl reload nginx
  msg_ok "Nginx Server Created"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/kestrel-aspnetapi.service
[Unit]
Description=.NET Web API App running on Linux

[Service]
WorkingDirectory=/var/www/html
ExecStart=/usr/bin/dotnet /var/www/html/$var_project_name.dll
Restart=always
RestartSec=10
KillSignal=SIGINT
SyslogIdentifier=dotnet-${var_project_name}
User=root
Environment=ASPNETCORE_ENVIRONMENT=Production
Environment=DOTNET_NOLOGO=true

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now kestrel-aspnetapi
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:80${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /var/www ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating ${APP} LXC"
  $STD apt-get update
  $STD apt-get -y upgrade
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
