#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster) | Co-Author: Slaviša Arežina (tremor021)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://magicmirror.builders/

# shellcheck disable=SC2034
APP="MagicMirror"
var_tags="${var_tags:-smarthome}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-3}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  NODE_VERSION="24" setup_nodejs

  fetch_and_deploy_gh_release "magicmirror" "MagicMirrorOrg/MagicMirror" "tarball"

  msg_info "Configuring MagicMirror"
  cd /opt/magicmirror || exit
  sed -i -E 's/("postinstall": )".*"/\1""/; s/("prepare": )".*"/\1""/' package.json
  $STD npm run install-mm
  cat << EOF > /opt/magicmirror/config/config.js
let config = {
        address: "0.0.0.0",
        port: 8080,
        basePath: "/",
        ipWhitelist: [],
        useHttps: false,
        httpsPrivateKey: "",
        httpsCertificate: "",
        language: "en",
        locale: "en-US",
        logLevel: ["INFO", "LOG", "WARN", "ERROR"],
        timeFormat: 24,
        units: "metric",
        serverOnly:  true,
        modules: [
                {
                        module: "alert",
                },
                {
                        module: "updatenotification",
                        position: "top_bar"
                },
                {
                        module: "clock",
                        position: "top_left"
                },
                {
                        module: "calendar",
                        header: "US Holidays",
                        position: "top_left",
                        config: {
                                calendars: [
                                        {
                                                symbol: "calendar-check",
                                                url: "webcal://www.calendarlabs.com/ical-calendar/ics/76/US_Holidays.ics"
                                        }
                                ]
                        }
                },
                {
                        module: "compliments",
                        position: "lower_third"
                },
                {
                        module: "weather",
                        position: "top_right",
                        config: {
                                weatherProvider: "openweathermap",
                                type: "current",
                                location: "New York",
                                locationID: "5128581",
                                apiKey: "YOUR_OPENWEATHER_API_KEY"
                        }
                },
                {
                        module: "weather",
                        position: "top_right",
                        header: "Weather Forecast",
                        config: {
                                weatherProvider: "openweathermap",
                                type: "forecast",
                                location: "New York",
                                locationID: "5128581",
                                apiKey: "YOUR_OPENWEATHER_API_KEY"
                        }
                },
                {
                        module: "newsfeed",
                        position: "bottom_bar",
                        config: {
                                feeds: [
                                        {
                                                title: "New York Times",
                                                url: "https://rss.nytimes.com/services/xml/rss/nyt/HomePage.xml"
                                        }
                                ],
                                showSourceTitle: true,
                                showPublishDate: true,
                                broadcastNewsFeeds: true,
                                broadcastNewsUpdates: true
                        }
                },
        ]
};

/*************** DO NOT EDIT THE LINE BELOW ***************/
if (typeof module !== "undefined") {module.exports = config;}
EOF
  msg_ok "Configured MagicMirror"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/magicmirror.service
[Unit]
Description=Magic Mirror
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=1
User=root
WorkingDirectory=/opt/magicmirror/
ExecStart=/usr/bin/npm run server

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now magicmirror
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/magicmirror ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "magicmirror" "MagicMirrorOrg/MagicMirror"; then
    msg_info "Stopping Service"
    systemctl stop magicmirror
    msg_ok "Stopped Service"

    NODE_VERSION="24" setup_nodejs

    msg_info "Backing up data"
    rm -rf /opt/magicmirror-backup
    mkdir /opt/magicmirror-backup
    cp /opt/magicmirror/config/config.js /opt/magicmirror-backup
    if [[ -f /opt/magicmirror/css/custom.css ]]; then
      cp /opt/magicmirror/css/custom.css /opt/magicmirror-backup
    fi
    cp -r /opt/magicmirror/modules /opt/magicmirror-backup
    msg_ok "Backed up data"

    fetch_and_deploy_gh_release "magicmirror" "MagicMirrorOrg/MagicMirror" "tarball"

    msg_info "Configuring MagicMirror"
    cd /opt/magicmirror || exit
    sed -i -E 's/("postinstall": )".*"/\1""/; s/("prepare": )".*"/\1""/' package.json
    $STD npm run install-mm
    cp /opt/magicmirror-backup/config.js /opt/magicmirror/config/
    if [[ -f /opt/magicmirror-backup/custom.css ]]; then
      cp /opt/magicmirror-backup/custom.css /opt/magicmirror/css/
    fi
    msg_ok "Configured MagicMirror"

    msg_info "Starting Service"
    systemctl start magicmirror
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
