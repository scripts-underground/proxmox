#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.phpmyadmin.net/ | Github: https://github.com/phpmyadmin/phpmyadmin

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="phpMyAdmin"

# Bundle-consumed configuration (var_addon_* is baked into update/uninstall
# bundles at install time — hooks may reference these directly)
var_addon_install_dir_debian="${var_addon_install_dir_debian:-/var/www/html/phpMyAdmin}"
var_addon_install_dir_alpine="${var_addon_install_dir_alpine:-/usr/share/phpmyadmin}"
var_addon_backup_dir="${var_addon_backup_dir:-/opt/phpmyadmin_backup}"
var_addon_fallback_version="${var_addon_fallback_version:-5.2.2}"

function header_info() {
  clear
  cat << "EOF"
        __                    ___  ____    ___
  ____ / /_  ____  ____ ___  /   |/ __ \  /   |
 / __ `/ __ \/ __ \/ __ `__ \/ /| / / / / / /| |
/ /_/ / / / / /_/ / / / / / / ___ / /_/ / / ___ |
\____/_/ /_/ .___/_/ /_/ /_/_/  |_\____/_/_/  |_|
          /_/
EOF
}

function install_script() {
  if [[ "$OS_FAMILY" != "debian" && "$OS_FAMILY" != "alpine" ]]; then
    msg_error "Unsupported OS: ${OS_TYPE} (Debian/Ubuntu and Alpine only)"
    exit 1
  fi

  if [[ "$OS_FAMILY" == "debian" ]]; then
    PMA_INSTALL_DIR="$var_addon_install_dir_debian"
  else
    PMA_INSTALL_DIR="$var_addon_install_dir_alpine"
  fi

  msg_info "Installing PHP and required modules"
  if command -v php > /dev/null 2>&1; then
    msg_ok "Found PHP version $(php -r 'echo PHP_VERSION;')"
  else
    msg_info "PHP not found, installing PHP core"
  fi
  if [[ "$OS_FAMILY" == "debian" ]]; then
    # Upstream expects the target container to already run Apache (Debian
    # path only adds the PHP modules phpMyAdmin needs)
    $STD apt update
    $STD apt install -y php php-mysqli php-mbstring php-zip php-gd php-json php-curl
  else
    $STD apk add --no-cache \
      lighttpd \
      php \
      php-fpm \
      php-session \
      php-json \
      php-mysqli \
      curl \
      tar \
      openssl
  fi
  msg_ok "Installed PHP and required modules"

  msg_info "Fetching latest phpMyAdmin release from GitHub"
  local PMA_VERSION_RAW PMA_VERSION
  PMA_VERSION_RAW=$(get_latest_github_release "phpmyadmin/phpmyadmin" false) || true
  PMA_VERSION=$(echo "$PMA_VERSION_RAW" | sed -e 's/^RELEASE_//' -e 's/_/./g')
  if [[ -z "$PMA_VERSION" ]]; then
    msg_warn "Could not determine latest phpMyAdmin version - falling back to ${var_addon_fallback_version}"
    PMA_VERSION="$var_addon_fallback_version"
  fi
  msg_ok "Latest version: ${PMA_VERSION}"

  msg_info "Downloading phpMyAdmin ${PMA_VERSION}"
  local PMA_TARBALL
  PMA_TARBALL=$(mktemp)
  if ! curl -fsSL "https://files.phpmyadmin.net/phpMyAdmin/${PMA_VERSION}/phpMyAdmin-${PMA_VERSION}-all-languages.tar.gz" -o "$PMA_TARBALL"; then
    msg_error "Download failed for phpMyAdmin ${PMA_VERSION}"
    exit 1
  fi
  mkdir -p "$PMA_INSTALL_DIR"
  tar xf "$PMA_TARBALL" --strip-components=1 -C "$PMA_INSTALL_DIR"
  rm -f "$PMA_TARBALL"
  msg_ok "Extracted phpMyAdmin to ${PMA_INSTALL_DIR}"

  msg_info "Configuring phpMyAdmin"
  if [[ "$OS_FAMILY" == "debian" ]]; then
    cp "$PMA_INSTALL_DIR/config.sample.inc.php" "$PMA_INSTALL_DIR/config.inc.php"
    local PMA_SECRET
    PMA_SECRET=$(openssl rand -base64 24)
    sed -i "s#\$cfg\['blowfish_secret'\] = '';#\$cfg['blowfish_secret'] = '${PMA_SECRET}';#" "$PMA_INSTALL_DIR/config.inc.php"
    chmod 660 "$PMA_INSTALL_DIR/config.inc.php"
    chown -R www-data:www-data "$PMA_INSTALL_DIR"
    systemctl restart apache2
    msg_ok "Configured phpMyAdmin with Apache"
  else
    mkdir -p /etc/lighttpd
    cat << EOF > /etc/lighttpd/lighttpd.conf
server.modules = (
    "mod_access",
    "mod_alias",
    "mod_accesslog",
    "mod_fastcgi"
)

server.document-root = "${PMA_INSTALL_DIR}"
server.port = 80

index-file.names = ( "index.php", "index.html" )

fastcgi.server = ( ".php" =>
  ((
    "host" => "127.0.0.1",
    "port" => 9000,
    "check-local" => "disable"
  ))
)

alias.url = ( "/phpMyAdmin/" => "${PMA_INSTALL_DIR}/" )

accesslog.filename = "/var/log/lighttpd/access.log"
server.errorlog = "/var/log/lighttpd/error.log"
EOF

    local PMA_PHP_FPM_SERVICE
    PMA_PHP_FPM_SERVICE="php-fpm$(php -r 'echo PHP_MAJOR_VERSION . PHP_MINOR_VERSION;')"
    if $STD rc-service "$PMA_PHP_FPM_SERVICE" start && $STD rc-update add "$PMA_PHP_FPM_SERVICE" default; then
      msg_ok "Started PHP-FPM service: ${PMA_PHP_FPM_SERVICE}"
    else
      msg_error "Failed to start PHP-FPM service: ${PMA_PHP_FPM_SERVICE}"
      exit 1
    fi
    $STD rc-service lighttpd start
    $STD rc-update add lighttpd default
    msg_ok "Configured and started Lighttpd"
  fi
}

function post_install_script() {
  echo ""
  if [[ "$OS_FAMILY" == "debian" ]]; then
    msg_ok "${APP} is reachable at: ${BL}http://${LOCAL_IP}/phpMyAdmin${CL}"
  else
    msg_ok "${APP} is reachable at: ${BL}http://${LOCAL_IP}/${CL}"
  fi
  echo -e "${INFO}${YW}Update:${CL} update-${APP_SLUG}   ${YW}Uninstall:${CL} uninstall-${APP_SLUG}"
}

function update_script() {
  local PMA_INSTALL_DIR
  if [[ "$OS_FAMILY" == "debian" ]]; then
    PMA_INSTALL_DIR="$var_addon_install_dir_debian"
  else
    PMA_INSTALL_DIR="$var_addon_install_dir_alpine"
  fi

  if [[ ! -d "$PMA_INSTALL_DIR" ]]; then
    msg_error "No ${APP} installation found at ${PMA_INSTALL_DIR}"
    exit 1
  fi

  msg_info "Fetching latest phpMyAdmin release from GitHub"
  local PMA_VERSION_RAW PMA_VERSION
  PMA_VERSION_RAW=$(get_latest_github_release "phpmyadmin/phpmyadmin" false) || true
  PMA_VERSION=$(echo "$PMA_VERSION_RAW" | sed -e 's/^RELEASE_//' -e 's/_/./g')
  if [[ -z "$PMA_VERSION" ]]; then
    msg_warn "Could not determine latest phpMyAdmin version - falling back to ${var_addon_fallback_version}"
    PMA_VERSION="$var_addon_fallback_version"
  fi
  msg_ok "Latest version: ${PMA_VERSION}"

  msg_info "Downloading phpMyAdmin ${PMA_VERSION}"
  local PMA_TARBALL
  PMA_TARBALL=$(mktemp)
  if ! curl -fsSL "https://files.phpmyadmin.net/phpMyAdmin/${PMA_VERSION}/phpMyAdmin-${PMA_VERSION}-all-languages.tar.gz" -o "$PMA_TARBALL"; then
    msg_error "Download failed for phpMyAdmin ${PMA_VERSION}"
    exit 1
  fi

  msg_info "Backing up configuration"
  rm -rf "$var_addon_backup_dir"
  mkdir -p "$var_addon_backup_dir"
  for pma_item in config.inc.php upload save tmp themes; do
    if [[ -e "${PMA_INSTALL_DIR}/${pma_item}" ]]; then
      cp -a "${PMA_INSTALL_DIR}/${pma_item}" "$var_addon_backup_dir/"
    fi
  done
  msg_ok "Backed up configuration"

  tar xf "$PMA_TARBALL" --strip-components=1 -C "$PMA_INSTALL_DIR"
  rm -f "$PMA_TARBALL"
  msg_ok "Extracted phpMyAdmin ${PMA_VERSION}"

  msg_info "Restoring configuration"
  for pma_item in config.inc.php upload save tmp themes; do
    if [[ -e "${var_addon_backup_dir}/${pma_item}" ]]; then
      rm -rf "${PMA_INSTALL_DIR:?}/${pma_item}"
      cp -a "${var_addon_backup_dir}/${pma_item}" "$PMA_INSTALL_DIR/"
    fi
  done
  rm -rf "$var_addon_backup_dir"
  msg_ok "Restored configuration"

  if [[ "$OS_FAMILY" == "debian" ]]; then
    chown -R www-data:www-data "$PMA_INSTALL_DIR"
    systemctl restart apache2
  else
    $STD rc-service lighttpd restart
  fi
  msg_ok "Updated successfully!"
  exit
}

function uninstall_script() {
  local PMA_INSTALL_DIR
  if [[ "$OS_FAMILY" == "debian" ]]; then
    PMA_INSTALL_DIR="$var_addon_install_dir_debian"
  else
    PMA_INSTALL_DIR="$var_addon_install_dir_alpine"
  fi

  msg_info "Stopping web server"
  if [[ "$OS_FAMILY" == "debian" ]]; then
    systemctl stop apache2 2> /dev/null || true
  else
    $STD rc-service lighttpd stop 2> /dev/null || true
  fi
  msg_ok "Stopped web server"

  msg_info "Removing phpMyAdmin directory"
  rm -rf "$PMA_INSTALL_DIR"

  if [[ "$OS_FAMILY" == "alpine" ]]; then
    msg_info "Removing Lighttpd config"
    rm -f /etc/lighttpd/lighttpd.conf
    $STD rc-service php-fpm restart 2> /dev/null || true
    $STD rc-service lighttpd restart 2> /dev/null || true
  else
    $STD systemctl restart apache2
  fi
  msg_ok "${APP} has been uninstalled"
}

# Addons run inside arbitrary containers that may lack curl — ensure the
# transport before sourcing the framework (everything else is bootstrapped
# by install.func from this point on)
if ! command -v curl > /dev/null 2>&1; then
  if [[ -f /etc/alpine-release ]]; then
    apk update &> /dev/null && apk add --no-cache curl &> /dev/null
  else
    apt-get update &> /dev/null && apt-get install -y curl &> /dev/null
  fi
fi
command -v curl > /dev/null 2>&1 || {
  echo "FATAL: curl is required and could not be installed" >&2
  exit 1
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/addon")
