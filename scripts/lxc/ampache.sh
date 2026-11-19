#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (Canbiz)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/ampache/ampache

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Ampache"
var_tags="${var_tags:-music}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-5}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  # Follow upstream's recommended Ampache 7 line on PHP 8.4. A 7 -> 8
  # migration (and PHP 8.5) requires a separate explicit decision.
  UPDATE_FORCE=1 check_for_gh_release "Ampache" "ampache/ampache" "latest" "" "7." || return $?
  local release="$CHECK_UPDATE_RELEASE"
  if [[ "$release" != 7.* ]]; then
    msg_error "Ampache requires a 7.x release on PHP 8.4; refusing ${release}"
    return 65
  fi

  msg_info "Installing Dependencies"
  $STD apt install -y \
    flac \
    vorbis-tools \
    lame \
    ffmpeg \
    inotify-tools \
    libavcodec-extra \
    libmp3lame-dev \
    libtheora-dev \
    libvorbis-dev \
    libvpx-dev
  msg_ok "Installed Dependencies"

  PHP_VERSION="8.4" PHP_APACHE="YES" setup_php
  setup_mariadb
  MARIADB_DB_USER="ampache" MARIADB_DB_NAME="ampache" setup_mariadb_db

  # Deploy the selected tag exactly: a missing asset must not select an older release.
  fetch_and_deploy_gh_release "ampache" "ampache/ampache" "prebuild" "$release" "/opt/ampache" "ampache-*_all_php8.4.zip" "7."

  msg_info "Setting Up Ampache"
  rm -rf /var/www/html
  ln -s /opt/ampache/public /var/www/html
  mv /opt/ampache/public/rest/.htaccess.dist /opt/ampache/public/rest/.htaccess
  mv /opt/ampache/public/play/.htaccess.dist /opt/ampache/public/play/.htaccess
  cp /opt/ampache/config/ampache.cfg.php.dist /opt/ampache/config/ampache.cfg.php
  chmod 664 /opt/ampache/public/rest/.htaccess /opt/ampache/public/play/.htaccess
  msg_ok "Set Up Ampache"

  msg_info "Configuring Database Connection"
  sed -i \
    -e 's|^database_hostname = .*|database_hostname = "localhost"|' \
    -e 's|^database_name = .*|database_name = "ampache"|' \
    -e 's|^database_username = .*|database_username = "ampache"|' \
    -e "s|^database_password = .*|database_password = \"${MARIADB_DB_PASS}\"|" \
    /opt/ampache/config/ampache.cfg.php
  chown -R www-data:www-data /opt/ampache
  msg_ok "Configured Database Connection"

  msg_info "Importing Database Schema"
  mariadb -u ampache -p"${MARIADB_DB_PASS}" ampache < /opt/ampache/resources/sql/ampache.sql
  msg_ok "Imported Database Schema"

  msg_info "Configuring PHP"
  sed -i \
    -e 's/upload_max_filesize = .*/upload_max_filesize = 100M/' \
    -e 's/post_max_size = .*/post_max_size = 100M/' \
    -e 's/max_execution_time = .*/max_execution_time = 600/' \
    -e 's/memory_limit = .*/memory_limit = 512M/' \
    /etc/php/8.4/apache2/php.ini
  $STD a2enmod rewrite
  $STD systemctl restart apache2
  msg_ok "Configured PHP"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}/install.php${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/ampache ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  # Keep existing installations on Ampache 7 / PHP 8.4, just like fresh installs.
  # Ampache 8 / PHP 8.5 migration is a separate explicit decision.
  if check_for_gh_release "Ampache" "ampache/ampache" "latest" "" "7."; then
    local release="$CHECK_UPDATE_RELEASE"
    if [[ "$release" != 7.* ]]; then
      msg_error "Ampache requires a 7.x release on PHP 8.4; refusing ${release}"
      return 65
    fi
    # Keep required helpers in a plain strict subshell: a conditional call would
    # suppress their internal errexit. Its EXIT owner cannot replace the runner's
    # pending/cleanup owner and preserves the original failure even if recovery fails.
    (
      local prior before after stop_attempted=0 activation_attempted=0
      function ampache_runtime_state() (
        set -o pipefail
        {
          local path mount row pattern
          local -a prune=(-path /opt/ampache/music)
          [[ -r /proc/self/mountinfo ]] || exit 69
          # Media is persistent data, not deployment-owned code. Mountinfo also
          # identifies same-device bind mounts that find -xdev cannot exclude.
          # Record each mounted boundary without visiting or reading its contents.
          while IFS= read -r row; do
            read -r _ _ _ _ mount _ <<< "$row"
            mount=${mount//\\040/ }
            mount=${mount//\\011/$'\t'}
            mount=${mount//\\012/$'\n'}
            mount=${mount//\\134/$'\\'}
            [[ "$mount" == /opt/ampache/* ]] || continue
            printf 'mount:%s\0' "$row" || exit $?
            stat -c '%f:%u:%g:%d:%i' -- "$mount" || exit $?
            # find -path takes a pattern; preserve literal operator mount names.
            pattern=${mount//\\/\\\\}
            pattern=${pattern//\*/\\*}
            pattern=${pattern//\?/\\?}
            pattern=${pattern//\[/\\[}
            prune+=(-o -path "$pattern")
          done < /proc/self/mountinfo
          {
            printf '%s\0' /opt/ampache "$HOME/.ampache" || exit $?
            find /opt/ampache/ -mindepth 1 \( "${prune[@]}" \) -prune -o -print0 || exit $?
          } | LC_ALL=C sort -zu | while IFS= read -r -d '' path; do
            printf '%s\0' "$path" || exit $?
            if [[ ! -e "$path" && ! -L "$path" && "$path" == "$HOME/.ampache" ]]; then
              printf 'absent\n' || exit $?
              continue
            fi
            stat -c '%f:%u:%g' -- "$path" || exit $?
            if [[ -L "$path" ]]; then
              readlink -- "$path" || exit $?
            elif [[ -f "$path" ]]; then
              sha256sum < "$path" || exit $?
            elif [[ ! -d "$path" ]]; then
              exit 65
            fi
          done
        } | sha256sum
      )
      function ampache_recover() {
        local status=$?
        trap - EXIT
        if [[ "$status" != 0 && "$stop_attempted" == 1 && "$activation_attempted" == 0 && "$prior" == active ]]; then
          after=$(ampache_runtime_state) || after=unverified
          if [[ "$after" == "$before" ]]; then
            systemctl start apache2 || msg_warn "Unable to restart previous Ampache service"
          else
            msg_warn "Previous Ampache runtime is unverified; Apache stays stopped"
          fi
        fi
        exit "$status"
      }
      prior=$(systemctl show apache2 --property=ActiveState --value)
      case "$prior" in active | inactive | failed) ;; *) return 65 ;; esac
      before=$(ampache_runtime_state)
      trap ampache_recover EXIT

      msg_info "Stopping Service"
      stop_attempted=1
      systemctl stop apache2
      msg_ok "Stopped Service"

      msg_info "Creating Backup"
      create_backup \
        /opt/ampache/config/ampache.cfg.php \
        /opt/ampache/public/rest/.htaccess \
        /opt/ampache/public/play/.htaccess \
        /opt/ampache/advanced-config
      msg_ok "Backup Created"

      fetch_and_deploy_gh_release "Ampache" "ampache/ampache" "prebuild" "$release" "/opt/ampache" "ampache-*_all_php8.4.zip" "7."

      restore_backup
      chmod 664 /opt/ampache/public/rest/.htaccess /opt/ampache/public/play/.htaccess
      chown -R www-data:www-data /opt/ampache

      msg_info "Starting Service"
      activation_attempted=1
      systemctl start apache2
      msg_ok "Started Service"
    )
    msg_ok "Updated successfully!"
    get_lxc_ip
    local host="$LOCAL_IP"
    [[ "$host" != *:* ]] || host="[$host]"
    msg_info "Complete database update by visiting: http://${host}/update.php"
  else
    local status=$?
    [[ "$status" == 1 ]] || return "$status"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc") --script-id "ampache" -- "$@"
