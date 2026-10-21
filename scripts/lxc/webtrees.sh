#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: sudofly
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://webtrees.net/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Webtrees"
var_tags="${var_tags:-genealogy;cms}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  local caddy_preexisting=no
  [[ ! -e /etc/caddy/Caddyfile ]] || caddy_preexisting=yes
  msg_info "Installing Dependencies"
  $STD apt install -y \
    caddy \
    python3 \
    unzip
  msg_ok "Installed Dependencies"

  PHP_VERSION="8.3" PHP_FPM="YES" PHP_MODULES="bcmath,gd,intl,xml,zip,pdo_mysql,mbstring,curl" setup_php
  setup_mariadb
  MARIADB_DB_NAME="webtrees" MARIADB_DB_USER="webtrees" setup_mariadb_db
  $STD mariadb -u root -e "GRANT ALL ON \`webtrees\`.* TO 'webtrees'@'127.0.0.1' IDENTIFIED BY '${MARIADB_DB_PASS}'; FLUSH PRIVILEGES;"

  fetch_and_deploy_gh_release "webtrees" "fisharebest/webtrees" "prebuild" "latest" "/opt/webtrees" "webtrees-*.zip"

  msg_info "Setting up Webtrees"
  chown -R www-data:www-data /opt/webtrees
  msg_ok "Set up Webtrees"

  msg_info "Configuring Caddy"
  PHP_VER=$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;')
  local caddy_stage caddy_original caddy_json caddy_rc
  caddy_stage=$(mktemp /etc/caddy/.webtrees-Caddyfile.XXXXXX) || exit $?
  caddy_original=$(mktemp /etc/caddy/.webtrees-original.XXXXXX) || exit $?
  caddy_json=$(mktemp /etc/caddy/.webtrees-json.XXXXXX) || exit $?
  cp -p -- /etc/caddy/Caddyfile "$caddy_original"
  if [[ "$caddy_preexisting" == yes ]]; then
    cp -p -- "$caddy_original" "$caddy_stage"
  else
    cat << EOF > "$caddy_stage"
:80 {
    root * /opt/webtrees
    php_fastcgi unix//run/php/php${PHP_VER}-fpm.sock
    file_server
    encode gzip
}
EOF
    chmod 0644 "$caddy_stage"
  fi
  function webtrees_caddy_patch() {
    python3 - "$1" << 'PY'
import pathlib,re,sys
p=pathlib.Path(sys.argv[1]);s=p.read_text();root=r'(?m)^[ \t]*root[ \t]+(?:\*[ \t]+)?(?:"/opt/webtrees/?"|/opt/webtrees/?)[ \t]*(?:#[^\n]*)?$';body='    @webtrees_private path /app /app/* /data /data/* /modules_v4 /modules_v4/* /resources /resources/* /vendor /vendor/* /.*\n    respond @webtrees_private 403'
if len(list(re.finditer(root,s)))!=1:print('Cannot identify one unambiguous Webtrees root in custom Caddy configuration; original retained',file=sys.stderr);sys.exit(65)
if body not in s:
 if '@webtrees_private' in s:print('Conflicting custom Webtrees privacy matcher; original retained',file=sys.stderr);sys.exit(65)
 s=re.sub(root,lambda m:m[0]+'\n'+body,s);p.write_text(s)
PY
  }
  function webtrees_caddy_check() {
    python3 - "$1" << 'PY'
import json,sys
paths={'/app','/app/*','/data','/data/*','/modules_v4','/modules_v4/*','/resources','/resources/*','/vendor','/vendor/*','/.*'};found=0
def walk(value):
 global found
 if isinstance(value,dict):
  routes=value.get('routes',[])
  if any(isinstance(h.get('root'),str) and h['root'].rstrip('/')=='/opt/webtrees' for r in routes for h in r.get('handle',[])):
   guards=[i for i,r in enumerate(routes) if any(set(m.get('path',[]))==paths for m in r.get('match',[])) and any(h.get('handler')=='static_response' and str(h.get('status_code'))=='403' for h in r.get('handle',[]))]
   if len(guards)!=1 or any(h.get('handler') not in ('vars','headers','encode') for r in routes[:guards[0]] for h in r.get('handle',[])):raise ValueError('custom routing precedes the privacy guard')
   found+=1
  for child in value.values():walk(child)
 elif isinstance(value,list):
  for child in value:walk(child)
try:
 walk(json.load(open(sys.argv[1])));assert found
except (ValueError,AssertionError) as e:print('Webtrees privacy route is not proven before file/rewrite handlers; original retained: '+str(e),file=sys.stderr);sys.exit(65)
PY
  }
  if webtrees_caddy_patch "$caddy_stage" && caddy validate --config "$caddy_stage" --adapter caddyfile && caddy adapt --config "$caddy_stage" --adapter caddyfile > "$caddy_json" && webtrees_caddy_check "$caddy_json"; then :; else
    caddy_rc=$?
    rm -f -- "$caddy_stage" "$caddy_original" "$caddy_json"
    exit "$caddy_rc"
  fi
  if ! cmp -s -- /etc/caddy/Caddyfile "$caddy_original"; then
    rm -f -- "$caddy_stage" "$caddy_original" "$caddy_json"
    msg_error "Caddy configuration changed concurrently; user changes retained"
    exit 65
  fi
  mv -T -- "$caddy_stage" /etc/caddy/Caddyfile
  rm -f -- "$caddy_original" "$caddy_json"
  usermod -aG www-data caddy
  systemctl enable -q --now php${PHP_VER}-fpm
  systemctl restart caddy
  msg_ok "Configured Caddy"

  msg_info "Automating Webtrees Setup"
  mkdir -p /opt/webtrees/data
  chown -R www-data:www-data /opt/webtrees/data
  WT_ADMIN_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c15)
  su -s /bin/bash www-data -c "php /opt/webtrees/index.php config-ini \
    --dbhost=127.0.0.1 \
    --dbport=3306 \
    --dbuser=webtrees \
    --dbpass=\"${MARIADB_DB_PASS}\" \
    --dbname=webtrees \
    --tblpfx=wt_ \
    --base-url=\"http://${LOCAL_IP}\""
  msg_info "Initializing Webtrees database schema"
  # shellcheck disable=SC2034
  for i in {1..15}; do
    if curl -sf "http://127.0.0.1/" > /dev/null 2>&1; then
      break
    fi
    sleep 2
  done
  mariadb -u webtrees -p"${MARIADB_DB_PASS}" -h 127.0.0.1 webtrees -e "SHOW TABLES LIKE 'wt_user';" | grep -q wt_user
  msg_ok "Initialized Webtrees database schema"
  su -s /bin/bash www-data -c "php /opt/webtrees/index.php user Admin \
    --create \
    --real-name=\"Administrator\" \
    --email=\"admin@example.com\" \
    --password=\"${WT_ADMIN_PASS}\""
  su -s /bin/bash www-data -c "php /opt/webtrees/index.php user-setting Admin canadmin 1"

  cat << EOF > ~/webtrees.creds
Webtrees Admin User: Admin
Webtrees Admin Password: ${WT_ADMIN_PASS}
EOF
  msg_ok "Webtrees Setup Automated"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
  echo -e "${INFO}${YW} Admin credentials are stored in ~/webtrees.creds${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/webtrees ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  # Repair privacy independently of application version. Validate an owned
  # candidate, including adapted route ordering, before touching the live file.
  ensure_dependencies python3
  local caddy_stage caddy_original caddy_json caddy_rc
  caddy_stage=$(mktemp /etc/caddy/.webtrees-Caddyfile.XXXXXX) || exit $?
  caddy_original=$(mktemp /etc/caddy/.webtrees-original.XXXXXX) || exit $?
  caddy_json=$(mktemp /etc/caddy/.webtrees-json.XXXXXX) || exit $?
  cp -p -- /etc/caddy/Caddyfile "$caddy_original"
  cp -p -- "$caddy_original" "$caddy_stage"
  function webtrees_caddy_patch() {
    python3 - "$1" << 'PY'
import pathlib,re,sys
p=pathlib.Path(sys.argv[1]);s=p.read_text();root=r'(?m)^[ \t]*root[ \t]+(?:\*[ \t]+)?(?:"/opt/webtrees/?"|/opt/webtrees/?)[ \t]*(?:#[^\n]*)?$';body='    @webtrees_private path /app /app/* /data /data/* /modules_v4 /modules_v4/* /resources /resources/* /vendor /vendor/* /.*\n    respond @webtrees_private 403'
if len(list(re.finditer(root,s)))!=1:print('Cannot identify one unambiguous Webtrees root in custom Caddy configuration; original retained',file=sys.stderr);sys.exit(65)
if body not in s:
 if '@webtrees_private' in s:print('Conflicting custom Webtrees privacy matcher; original retained',file=sys.stderr);sys.exit(65)
 s=re.sub(root,lambda m:m[0]+'\n'+body,s);p.write_text(s)
PY
  }
  function webtrees_caddy_check() {
    python3 - "$1" << 'PY'
import json,sys
paths={'/app','/app/*','/data','/data/*','/modules_v4','/modules_v4/*','/resources','/resources/*','/vendor','/vendor/*','/.*'};found=0
def walk(value):
 global found
 if isinstance(value,dict):
  routes=value.get('routes',[])
  if any(isinstance(h.get('root'),str) and h['root'].rstrip('/')=='/opt/webtrees' for r in routes for h in r.get('handle',[])):
   guards=[i for i,r in enumerate(routes) if any(set(m.get('path',[]))==paths for m in r.get('match',[])) and any(h.get('handler')=='static_response' and str(h.get('status_code'))=='403' for h in r.get('handle',[]))]
   if len(guards)!=1 or any(h.get('handler') not in ('vars','headers','encode') for r in routes[:guards[0]] for h in r.get('handle',[])):raise ValueError('custom routing precedes the privacy guard')
   found+=1
  for child in value.values():walk(child)
 elif isinstance(value,list):
  for child in value:walk(child)
try:
 walk(json.load(open(sys.argv[1])));assert found
except (ValueError,AssertionError) as e:print('Webtrees privacy route is not proven before file/rewrite handlers; original retained: '+str(e),file=sys.stderr);sys.exit(65)
PY
  }
  if webtrees_caddy_patch "$caddy_stage" && caddy validate --config "$caddy_stage" --adapter caddyfile && caddy adapt --config "$caddy_stage" --adapter caddyfile > "$caddy_json" && webtrees_caddy_check "$caddy_json"; then :; else
    caddy_rc=$?
    rm -f -- "$caddy_stage" "$caddy_original" "$caddy_json"
    exit "$caddy_rc"
  fi
  if ! cmp -s -- /etc/caddy/Caddyfile "$caddy_original"; then
    rm -f -- "$caddy_stage" "$caddy_original" "$caddy_json"
    msg_error "Caddy configuration changed concurrently; user changes retained"
    exit 65
  fi
  if cmp -s -- "$caddy_stage" "$caddy_original"; then rm -f -- "$caddy_stage"; else
    mv -T -- "$caddy_stage" /etc/caddy/Caddyfile
    systemctl reload-or-restart caddy
  fi
  rm -f -- "$caddy_original" "$caddy_json"

  if check_for_gh_release "webtrees" "fisharebest/webtrees"; then
    msg_info "Stopping Service"
    PHP_VER=$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;')
    systemctl stop caddy php${PHP_VER}-fpm
    msg_ok "Stopped Service"

    local -a CLEAN_INSTALL_KEEP_PATHS=("${CLEAN_INSTALL_KEEP_PATHS[@]}" data)
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "webtrees" "fisharebest/webtrees" "prebuild" "latest" "/opt/webtrees" "webtrees-*.zip"

    msg_info "Starting Service"
    systemctl start caddy php${PHP_VER}-fpm
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  else
    local checker_rc=$?
    [[ "$checker_rc" == 1 ]] || exit "$checker_rc"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
