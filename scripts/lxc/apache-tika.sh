#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Andy Grunwald (andygrunwald)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/apache/tika/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Apache-Tika"
var_tags="${var_tags:-document}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    software-properties-common \
    gdal-bin \
    tesseract-ocr \
    tesseract-ocr-eng \
    tesseract-ocr-ita \
    tesseract-ocr-fra \
    tesseract-ocr-spa \
    tesseract-ocr-deu
  $STD echo ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true | debconf-set-selections
  $STD apt install -y \
    xfonts-utils \
    fonts-freefont-ttf \
    fonts-liberation \
    ttf-mscorefonts-installer \
    cabextract
  msg_ok "Installed Dependencies"

  msg_info "Setup OpenJDK"
  $STD apt install -y \
    openjdk-17-jre-headless
  msg_ok "Setup OpenJDK"

  msg_info "Installing Apache Tika"
  mkdir -p /opt/apache-tika
  cd /opt/apache-tika || exit
  RELEASE="$(curl -fsSL https://dlcdn.apache.org/tika/ | grep -oP '(?<=href=")[0-9]+\.[0-9]+\.[0-9]+(?=/")' | sort -V | tail -n1)"
  curl -fsSL "https://dlcdn.apache.org/tika/${RELEASE}/tika-server-standard-${RELEASE}.jar" -o tika-server-standard.jar
  echo "${RELEASE}" > /opt/${APP}_version.txt
  msg_ok "Installed Apache Tika"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/apache-tika.service
[Unit]
Description=Apache Tika
Documentation=https://tika.apache.org/
After=syslog.target network.target

[Service]
User=root
Restart=always
Type=simple
ExecStart=java -jar /opt/apache-tika/tika-server-standard.jar --host 0.0.0.0 --port 9998
ExecReload=/bin/kill -HUP \$MAINPID

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now apache-tika
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:9998${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /etc/systemd/system/apache-tika.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  RELEASE="$(curl -fsSL https://dlcdn.apache.org/tika/ | grep -oP '(?<=href=")[0-9]+\.[0-9]+\.[0-9]+(?=/")' | sort -V | tail -n1)"
  if [[ ! -f /opt/${APP}_version.txt ]] || [[ "${RELEASE}" != "$(cat /opt/${APP}_version.txt)" ]]; then
    msg_info "Stopping Service"
    systemctl stop apache-tika
    msg_ok "Stopped Service"

    msg_info "Updating ${APP} to v${RELEASE}"
    cd /opt/apache-tika || exit
    curl -fsSL -o "tika-server-standard-${RELEASE}.jar" "https://dlcdn.apache.org/tika/${RELEASE}/tika-server-standard-${RELEASE}.jar"
    mv --force tika-server-standard.jar tika-server-standard-prev-version.jar
    mv tika-server-standard-${RELEASE}.jar tika-server-standard.jar
    rm -rf /opt/apache-tika/tika-server-standard-prev-version.jar
    echo "${RELEASE}" > /opt/${APP}_version.txt
    msg_ok "Updated ${APP} to v${RELEASE}"

    msg_info "Starting Service"
    systemctl start apache-tika
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  else
    msg_ok "No update required. ${APP} is already at v${RELEASE}"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
