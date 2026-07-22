#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://shinobi.video/
# shellcheck disable=SC2034
APP="Shinobi"
var_tags="${var_tags:-nvr}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-ubuntu}"
var_version="${var_version:-24.04}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-0}"
var_gpu="${var_gpu:-yes}"
function install_script() {
  setup_hwaccel
  msg_info "Installing Dependencies"
  $STD apt install -y make zip net-tools git
  $STD apt install -y gcc g++ cmake
  $STD apt install -y ca-certificates
  msg_ok "Installed Dependencies"
  NODE_VERSION="22" setup_nodejs
  setup_mariadb
  msg_info "Installing FFMPEG"
  $STD apt install -y ffmpeg
  msg_ok "Installed FFMPEG"
  msg_info "Cloning Shinobi"
  cd /opt || exit
  $STD git clone https://gitlab.com/Shinobi-Systems/Shinobi.git -b master Shinobi
  cd Shinobi || exit
  gitVersionNumber=$(git rev-parse HEAD)
  theDateRightNow=$(date)
  touch version.json
  chmod 644 version.json
  echo '{"Product" : "'"Shinobi"'" , "Branch" : "'"master"'" , "Version" : "'"$gitVersionNumber"'" , "Date" : "'"$theDateRightNow"'" , "Repository" : "'"https://gitlab.com/Shinobi-Systems/Shinobi.git"'"}' > version.json
  msg_ok "Cloned Shinobi"
  msg_info "Installing Database"
  sqluser="root"
  sqlpass="root"
  echo "mariadb-server mariadb-server/root_password password $sqlpass" | debconf-set-selections
  echo "mariadb-server mariadb-server/root_password_again password $sqlpass" | debconf-set-selections
  service mysql start
  $STD mariadb -u "$sqluser" -p"$sqlpass" -e "source sql/user.sql" || true
  msg_ok "Installed Database"
  msg_info "Installing Shinobi"
  cp conf.sample.json conf.json
  cronKey=$(head -c 1024 < /dev/urandom | sha256sum | awk '{print substr($1,1,29)}')
  sed -i -e 's/Shinobi/'"$cronKey"'/g' conf.json
  cp super.sample.json super.json
  $STD npm i npm -g
  $STD npm install
  $STD npm install pm2@latest -g
  chmod -R 755 .
  touch INSTALL/installed.txt
  ln -s /opt/Shinobi/INSTALL/shinobi /usr/bin/shinobi
  node /opt/Shinobi/tools/modifyConfiguration.js addToConfig="{\"cron\":{\"key\":\"$(head -c 64 < /dev/urandom | sha256sum | awk '{print substr($1,1,60)}')\"}}" &> /dev/null
  $STD pm2 start camera.js
  $STD pm2 start cron.js
  $STD pm2 startup
  $STD pm2 save
  $STD pm2 list
  msg_ok "Installed Shinobi"
}
function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080/super${CL}"
}
function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/Shinobi ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  setup_mariadb
  msg_info "Updating Shinobi"
  cd /opt/Shinobi || exit
  $STD sh UPDATE.sh
  $STD pm2 flush
  $STD pm2 restart camera
  $STD pm2 restart cron
  msg_ok "Updated Shinobi"
  msg_ok "Updated successfully!"
  exit
}
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
