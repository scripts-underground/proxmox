#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Adrian-RDA
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/maziggy/bambuddy

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Bambuddy"
var_tags="${var_tags:-media;3d-printing}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y libglib2.0-0 ffmpeg
  msg_ok "Installed Dependencies"

  PYTHON_VERSION="3.13" setup_uv
  NODE_VERSION="22" setup_nodejs
  fetch_and_deploy_gh_release "bambuddy" "maziggy/bambuddy" "tarball" "latest" "/opt/bambuddy"

  msg_info "Setting up Python Environment"
  cd /opt/bambuddy || exit
  $STD uv venv
  $STD uv pip install -r requirements.txt
  msg_ok "Set up Python Environment"

  msg_info "Building Frontend"
  cd /opt/bambuddy/frontend || exit
  $STD npm install
  $STD npm run build
  msg_ok "Built Frontend"

  msg_info "Configuring Bambuddy"
  mkdir -p /opt/bambuddy/data /opt/bambuddy/logs
  cat << EOF > /opt/bambuddy/.env
DEBUG=false
LOG_LEVEL=INFO
LOG_TO_FILE=true
EOF
  msg_ok "Configured Bambuddy"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/bambuddy.service
[Unit]
Description=Bambuddy - Bambu Lab Print Management
Documentation=https://github.com/maziggy/bambuddy
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/bambuddy
ExecStart=/opt/bambuddy/.venv/bin/uvicorn backend.app.main:app --host 0.0.0.0 --port 8000
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now bambuddy
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/bambuddy ]]; then
    msg_error "No ${APP} Installation Found!"
    exit 1
  fi

  ensure_dependencies ffmpeg

  if check_for_gh_release "bambuddy" "maziggy/bambuddy"; then
    # Keep application state at its live paths even if deployment/build fails.
    # Read configured paths with the installed application's own parsers before
    # replacing its source. An active service's environment takes precedence.
    local keep_file service_pid reader=/opt/bambuddy/.venv/bin/python reader_temp=''
    keep_file=$(mktemp) || return $?
    service_pid=$(systemctl show bambuddy --property=MainPID --value) || {
      local status=$?
      rm -f -- "$keep_file"
      return "$status"
    }
    # A previous updater may have emptied .venv before a failed install. Repair
    # the reader in a disposable environment, never the live application's env.
    if ! "$reader" -c 'import pydantic, pydantic_settings, sqlalchemy' > /dev/null 2>&1; then
      reader_temp=$(mktemp -d) || {
        local status=$?
        rm -f -- "$keep_file"
        return "$status"
      }
      if (
        cd /opt/bambuddy &&
          $STD uv venv --python 3.13 "$reader_temp" &&
          $STD uv pip install --python "$reader_temp/bin/python" -r requirements.txt
      ); then
        reader="$reader_temp/bin/python"
      else
        local status=$?
        rm -f -- "$keep_file"
        rm -rf -- "$reader_temp"
        return "$status"
      fi
    fi
    (
      cd /opt/bambuddy || exit
      "$reader" - "$service_pid" > "$keep_file" << 'PY'
import os, pathlib, shlex, subprocess, sys
from urllib.parse import urlsplit, unquote_to_bytes
root = pathlib.Path('/opt/bambuddy')
pid = int(sys.argv[1])
if pid:
    # No environment/credential values are emitted, only protected path names.
    for entry in pathlib.Path(f'/proc/{pid}/environ').read_bytes().split(b'\0'):
        if entry:
            key, value = os.fsdecode(entry).split('=', 1)
            if key != 'TMPDIR':
                os.environ[key] = value
else:
    files = subprocess.check_output(['systemctl', 'show', 'bambuddy', '--property=EnvironmentFiles', '--value'], text=True)
    if files.strip():
        raise ValueError('Cannot discover a stopped service with EnvironmentFile entries; start Bambuddy and retry')
    environment = subprocess.check_output(['systemctl', 'show', 'bambuddy', '--property=Environment', '--value'], text=True)
    for entry in shlex.split(environment):
        key, value = entry.split('=', 1)
        if key != 'TMPDIR':
            os.environ[key] = value
from backend.app.core.config import settings
from sqlalchemy.engine import make_url
from sqlalchemy.util import asbool
paths = [settings.archive_dir, settings.plate_calibration_dir, settings.log_dir]
base = pathlib.Path(settings.base_dir)
if base.absolute() != root:
    paths.append(base)
url = make_url(settings.database_url)
if url.get_backend_name() == 'sqlite' and url.database and url.database != ':memory:':
    filename = url.database
    if asbool(url.query.get('uri', False)) and filename.startswith('file:'):
        uri = urlsplit(filename)
        if uri.netloc not in ('', 'localhost') or uri.fragment or uri.query or not uri.path:
            raise ValueError('Cannot resolve configured SQLite file URI safely')
        filename = os.fsdecode(unquote_to_bytes(uri.path))
    database = pathlib.Path(filename)
    paths.extend(pathlib.Path(str(database) + suffix) for suffix in ('', '-wal', '-shm', '-journal'))
for path in paths:
    path = pathlib.Path(os.path.abspath(path))
    if path == root:
        raise ValueError('Configured data path overlaps the application source root')
    if root in path.parents:
        relative = str(path.relative_to(root))
        if any(char in relative for char in '*?[]\0'):
            raise ValueError('Configured data path is incompatible with deployment keep paths')
        sys.stdout.buffer.write(os.fsencode(relative) + b'\0')
PY
    ) || {
      local status=$?
      rm -f -- "$keep_file"
      [[ -z "$reader_temp" ]] || rm -rf -- "$reader_temp"
      return "$status"
    }
    [[ -z "$reader_temp" ]] || rm -rf -- "$reader_temp"
    local -a configured_paths=()
    mapfile -d '' -t configured_paths < "$keep_file"
    rm -f -- "$keep_file"
    local -a CLEAN_INSTALL_KEEP_PATHS=("${CLEAN_INSTALL_KEEP_PATHS[@]}" "${configured_paths[@]}"
      .env .venv data bambuddy.db bambuddy.db-wal bambuddy.db-shm bambuddy.db-journal
      bambutrack.db bambutrack.db-wal bambutrack.db-shm bambutrack.db-journal
      archive virtual_printer firmware icons projects overlay-branding photos
      notification_photos spoolbuddy/ssh timelapse_frames backups logs)

    msg_info "Stopping Service"
    systemctl stop bambuddy
    msg_ok "Stopped Service"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "bambuddy" "maziggy/bambuddy" "tarball" "$CHECK_UPDATE_RELEASE" "/opt/bambuddy"

    msg_info "Updating Python Dependencies"
    cd /opt/bambuddy || exit
    $STD uv venv --allow-existing
    $STD uv pip install -r requirements.txt
    msg_ok "Updated Python Dependencies"

    msg_info "Rebuilding Frontend"
    cd /opt/bambuddy/frontend || exit
    $STD npm install
    $STD npm run build
    msg_ok "Rebuilt Frontend"

    msg_info "Starting Service"
    systemctl start bambuddy
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  else
    local status=$?
    [[ "$status" == 1 ]] || return "$status"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc") --script-id "bambuddy" -- "$@"
