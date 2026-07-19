#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: andrej-kocijan (Andrej Kocijan)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/redlib-org/redlib

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Alpine-Redlib"
var_tags="${var_tags:-alpine;frontend}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-1}"
var_os="${var_os:-alpine}"
var_version="${var_version:-3.23}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  fetch_and_deploy_gh_release "redlib" "redlib-org/redlib" "prebuild" "latest" "/opt/redlib" "redlib-$(uname -m)-unknown-linux-musl.tar.gz"

  msg_info "Configuring Redlib"
  cat << EOF > /opt/redlib/redlib.conf
############################################
# Redlib Instance Configuration File
# Uncomment and edit values as needed
############################################

## Instance settings
ADDRESS=0.0.0.0
PORT=5252                           # Integer (0-65535) - Internal port
#REDLIB_SFW_ONLY=off                # ["on", "off"] - Filter all NSFW content
#REDLIB_BANNER=                     # String - Displayed on instance info page
#REDLIB_ROBOTS_DISABLE_INDEXING=off # ["on", "off"] - Disable search engine indexing
#REDLIB_PUSHSHIFT_FRONTEND=undelete.pullpush.io # Pushshift frontend for removed links
#REDLIB_ENABLE_RSS=off              # ["on", "off"] - Enable RSS feed generation
#REDLIB_FULL_URL=                   # String - Needed for proper RSS URLs

## Default user settings
#REDLIB_DEFAULT_THEME=system        # Theme (system, light, dark, black, dracula, nord, laserwave, violet, gold, rosebox, gruvboxdark, gruvboxlight, tokyoNight, icebergDark, doomone, libredditBlack, libredditDark, libredditLight)
#REDLIB_DEFAULT_FRONT_PAGE=default  # ["default", "popular", "all"]
#REDLIB_DEFAULT_LAYOUT=card         # ["card", "clean", "compact"]
#REDLIB_DEFAULT_WIDE=off            # ["on", "off"]
#REDLIB_DEFAULT_POST_SORT=hot       # ["hot", "new", "top", "rising", "controversial"]
#REDLIB_DEFAULT_COMMENT_SORT=confidence # ["confidence", "top", "new", "controversial", "old"]
#REDLIB_DEFAULT_BLUR_SPOILER=off    # ["on", "off"]
#REDLIB_DEFAULT_SHOW_NSFW=off       # ["on", "off"]
#REDLIB_DEFAULT_BLUR_NSFW=off       # ["on", "off"]
#REDLIB_DEFAULT_USE_HLS=off         # ["on", "off"]
#REDLIB_DEFAULT_HIDE_HLS_NOTIFICATION=off # ["on", "off"]
#REDLIB_DEFAULT_AUTOPLAY_VIDEOS=off # ["on", "off"]
#REDLIB_DEFAULT_SUBSCRIPTIONS=      # Example: sub1+sub2+sub3
#REDLIB_DEFAULT_HIDE_AWARDS=off     # ["on", "off"]
#REDLIB_DEFAULT_DISABLE_VISIT_REDDIT_CONFIRMATION=off # ["on", "off"]
#REDLIB_DEFAULT_HIDE_SCORE=off      # ["on", "off"]
#REDLIB_DEFAULT_HIDE_SIDEBAR_AND_SUMMARY=off # ["on", "off"]
#REDLIB_DEFAULT_FIXED_NAVBAR=on     # ["on", "off"]
#REDLIB_DEFAULT_REMOVE_DEFAULT_FEEDS=off # ["on", "off"]
EOF
  msg_ok "Configured Redlib"

  msg_info "Creating Redlib Service"
  cat << EOF > /etc/init.d/redlib
#!/sbin/openrc-run

name="Redlib"
description="Redlib Service"
command="/opt/redlib/redlib"
pidfile="/run/redlib.pid"
supervisor="supervise-daemon"
command_background="yes"

depend() {
    need net
}

start_pre() {

    set -a
    . /opt/redlib/redlib.conf
    set +a

    : \${ADDRESS:=0.0.0.0}
    : \${PORT:=5252}

    command_args="-a \${ADDRESS} -p \${PORT}"
}
EOF
  $STD chmod +x /etc/init.d/redlib
  $STD rc-update add redlib default
  msg_ok "Created Redlib Service"

  msg_info "Starting Redlib Service"
  $STD rc-service redlib start
  msg_ok "Started Redlib Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:5252${CL}"
}

function update_script() {
  header_info

  if [[ ! -d /opt/redlib ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating Alpine Packages"
  $STD apk -U upgrade
  msg_ok "Updated Alpine Packages"

  msg_info "Stopping Service"
  $STD rc-service redlib stop
  msg_ok "Stopped Service"

  fetch_and_deploy_gh_release "redlib" "redlib-org/redlib" "prebuild" "latest" "/opt/redlib" "redlib-$(uname -m)-unknown-linux-musl.tar.gz"

  msg_info "Starting Service"
  $STD rc-service redlib start
  msg_ok "Started Service"
  msg_ok "Updated successfully!"
  exit 0
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
