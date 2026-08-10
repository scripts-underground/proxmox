#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: vhsdream
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://codeberg.org/gelbphoenix/autocaliweb

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Autocaliweb"
var_tags="${var_tags:-ebooks}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-6}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing dependencies"
  $STD apt install -y --no-install-recommends \
    python3-dev \
    sqlite3 \
    build-essential \
    libldap2-dev \
    libssl-dev \
    libsasl2-dev \
    imagemagick \
    ghostscript \
    libmagic1 \
    libxi6 \
    libxslt1.1 \
    libxtst6 \
    libxrandr2 \
    libxkbfile1 \
    libxcomposite1 \
    libopengl0 \
    libnss3 \
    libxkbcommon0 \
    libegl1 \
    libxdamage1 \
    libgl1 \
    libglx-mesa0 \
    xz-utils \
    xdg-utils \
    inotify-tools \
    binutils \
    unrar-free \
    zip
  msg_ok "Installed dependencies"

  fetch_and_deploy_gh_release "kepubify" "pgaskin/kepubify" "singlefile" "latest" "/usr/bin" "kepubify-linux-64bit"
  KEPUB_VERSION="$(/usr/bin/kepubify --version | awk '{print $2}')"
  fetch_and_deploy_gh_release "calibre" "kovidgoyal/calibre" "prebuild" "latest" "/opt/calibre" "calibre-*-x86_64.txz"

  msg_info "Installing Calibre"
  $STD /opt/calibre/calibre_postinstall
  CALIBRE_VERSION=$(cat ~/.calibre)
  msg_ok "Installed Calibre"

  setup_uv

  fetch_and_deploy_codeberg_release "autocaliweb" "gelbphoenix/autocaliweb" "tarball" "latest" "/opt/autocaliweb"

  msg_info "Configuring Autocaliweb"
  INSTALL_DIR="/opt/autocaliweb"
  CONFIG_DIR="/etc/autocaliweb"
  CALIBRE_LIB_DIR="/opt/calibre-library"
  INGEST_DIR="/opt/acw-book-ingest"
  SERVICE_USER="acw"
  SERVICE_GROUP="acw"
  SCRIPTS_DIR="${INSTALL_DIR}/scripts"
  export VIRTUAL_ENV="${INSTALL_DIR}/venv"

  mkdir -p "$CONFIG_DIR"/{.config/calibre/plugins,log_archive,.acw_conversion_tmp}
  mkdir -p "$CONFIG_DIR"/processed_books/{converted,imported,failed,fixed_originals}
  mkdir -p "$INSTALL_DIR"/{metadata_change_logs,metadata_temp}
  mkdir -p {"$CALIBRE_LIB_DIR","$INGEST_DIR"}
  echo "$CALIBRE_VERSION" > "$INSTALL_DIR"/CALIBRE_RELEASE
  echo "${KEPUB_VERSION#v}" > "$INSTALL_DIR"/KEPUBIFY_RELEASE
  sed 's/^/v/' ~/.autocaliweb > "$INSTALL_DIR"/ACW_RELEASE

  cd "$INSTALL_DIR" || exit
  $STD uv venv --clear "$VIRTUAL_ENV"
  $STD uv sync --all-extras --active
  cat << EOF > ./dirs.json
{
  "ingest_folder": "$INGEST_DIR",
  "calibre_library_dir": "$CALIBRE_LIB_DIR",
  "tmp_conversion_dir": "$CONFIG_DIR/.acw_conversion_tmp"
}
EOF
  useradd -s /usr/sbin/nologin -d "$CONFIG_DIR" -M "$SERVICE_USER"
  ln -sf "$CONFIG_DIR"/.config/calibre/plugins "$CONFIG_DIR"/calibre_plugins
  cat << EOF > "$INSTALL_DIR"/.env
ACW_INSTALL_DIR=$INSTALL_DIR
ACW_CONFIG_DIR=$CONFIG_DIR
ACW_USER=$SERVICE_USER
ACW_GROUP=$SERVICE_GROUP
LIBRARY_DIR=$CALIBRE_LIB_DIR
EOF
  msg_ok "Configured Autocaliweb"

  msg_info "Creating ACWSync Plugin for KOReader"
  cd "$INSTALL_DIR/koreader/plugins" || exit
  PLUGIN_DIGEST="$(find acwsync.koplugin -type f -name "*.lua" -o -name "*.json" | sort | xargs sha256sum | sha256sum | cut -d' ' -f1)"
  echo "Plugin files digest: $PLUGIN_DIGEST" > acwsync.koplugin/${PLUGIN_DIGEST}.digest
  echo "Build date: $(date)" >> acwsync.koplugin/${PLUGIN_DIGEST}.digest
  echo "Files included:" >> acwsync.koplugin/${PLUGIN_DIGEST}.digest
  $STD zip -r koplugin.zip acwsync.koplugin/
  cp -r koplugin.zip "$INSTALL_DIR"/cps/static
  msg_ok "Created ACWSync Plugin"

  msg_info "Initializing databases"
  KEPUBIFY_PATH=$(command -v kepubify 2> /dev/null || echo "/usr/bin/kepubify")
  EBOOK_CONVERT_PATH=$(command -v ebook-convert 2> /dev/null || echo "/usr/bin/ebook-convert")
  CALIBRE_BIN_DIR=$(dirname "$EBOOK_CONVERT_PATH")
  curl -fsSL https://codeberg.org/gelbphoenix/autocaliweb/raw/branch/main/library/metadata.db -o "$CALIBRE_LIB_DIR"/metadata.db
  curl -fsSL https://codeberg.org/gelbphoenix/autocaliweb/raw/branch/main/library/app.db -o "$CONFIG_DIR"/app.db
  sqlite3 "$CONFIG_DIR/app.db" << EOS
UPDATE settings SET
    config_kepubifypath='$KEPUBIFY_PATH',
    config_converterpath='$EBOOK_CONVERT_PATH',
    config_binariesdir='$CALIBRE_BIN_DIR',
    config_calibre_dir='$CALIBRE_LIB_DIR',
    config_logfile='$CONFIG_DIR/autocaliweb.log',
    config_access_logfile='$CONFIG_DIR/access.log'
WHERE 1=1;
EOS
  msg_ok "Initialized databases"

  msg_info "Creating scripts and service files"

  cat << EOF > "$SCRIPTS_DIR"/ingest_watcher.sh
#!/bin/bash

INSTALL_PATH="$INSTALL_DIR"
WATCH_FOLDER=\$(grep -o '"ingest_folder": "[^"]*' \${INSTALL_PATH}/dirs.json | grep -o '[^"]*\$')
echo "[acw-ingest-service] Watching folder: \$WATCH_FOLDER"

/usr/bin/inotifywait -m -r --format="%e %w%f" -e close_write -e moved_to "\$WATCH_FOLDER" |
while read -r events filepath ; do
    echo "[acw-ingest-service] New files detected - \$filepath - Starting Ingest Processor..."
    \${INSTALL_PATH}/venv/bin/python \${INSTALL_PATH}/scripts/ingest_processor.py "\$filepath"
done
EOF

  cat << EOF > "$SCRIPTS_DIR"/auto_zipper_wrapper.sh
#!/bin/bash

source ${INSTALL_DIR}/venv/bin/activate

WAKEUP="23:59"

while true; do
    SECS=\$(( \$(date -d "\$WAKEUP" +%s) - \$(date -d "now" +%s) ))
    if [[ \$SECS -lt 0 ]]; then
        SECS=\$(( \$(date -d "tomorrow \$WAKEUP" +%s) - \$(date -d "now" +%s) ))
    fi
    echo "[acw-auto-zipper] Next run in \$SECS seconds."
    sleep \$SECS &
    wait \$!

    python ${SCRIPTS_DIR}/auto_zip.py

    if [[ \$? == 1 ]]; then
    echo "[acw-auto-zipper] Error occurred during script initialisation."
    elif [[ \$? == 2 ]]; then
    echo "[acw-auto-zipper] Error occurred while zipping today's files."
    elif [[ \$? == 3 ]]; then
    echo "[acw-auto-zipper] Error occurred while trying to remove zipped files."
    fi

    sleep 60
done
EOF

  cat << EOF > "$SCRIPTS_DIR"/metadata_change_detector_wrapper.sh
#!/bin/bash

source ${INSTALL_DIR}/venv/bin/activate

CHECK_INTERVAL=300
METADATA_LOGS_DIR="${INSTALL_DIR}/metadata_change_logs"

echo "[metadata-change-detector] Starting metadata change detector service..."
echo "[metadata-change-detector] Checking for changes every \$CHECK_INTERVAL seconds"

while true; do
    if [ -d "\$METADATA_LOGS_DIR" ] && [ "\$(ls -A \$METADATA_LOGS_DIR 2>/dev/null)" ]; then
        echo "[metadata-change-detector] Found metadata change logs, processing..."

        for log_file in "\$METADATA_LOGS_DIR"/*.json; do
            if [ -f "\$log_file" ]; then
                log_name=\$(basename "\$log_file")
                echo "[metadata-change-detector] Processing log: \$log_name"

                 ${INSTALL_DIR}/venv/bin/python  ${SCRIPTS_DIR}/cover_enforcer.py --log "\$log_name"

                if [ \$? -eq 0 ]; then
                    echo "[metadata-change-detector] Successfully processed \$log_name"
                else
                    echo "[metadata-change-detector] Error processing \$log_name"
                fi
            fi
        done
    else
        echo "[metadata-change-detector] No metadata changes detected"
    fi

    echo "[metadata-change-detector] Sleeping for \$CHECK_INTERVAL seconds..."
    sleep \$CHECK_INTERVAL
done
EOF
  chmod +x "$SCRIPTS_DIR"/{ingest_watcher.sh,auto_zipper_wrapper.sh,metadata_change_detector_wrapper.sh}
  chown -R "$SERVICE_USER":"$SERVICE_GROUP" {"$INSTALL_DIR","$CONFIG_DIR","$INGEST_DIR","$CALIBRE_LIB_DIR"}

  cat << EOF > /etc/systemd/system/autocaliweb.service
[Unit]
Description=Autocaliweb
After=network.target
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_GROUP
WorkingDirectory=$INSTALL_DIR
Environment=PATH=$INSTALL_DIR/venv/bin:/usr/bin:/bin
Environment=PYTHONPATH=$SCRIPTS_DIR:$INSTALL_DIR
Environment=PYTHONDONTWRITEBYTECODE=1
Environment=PYTHONUNBUFFERED=1
Environment=CALIBRE_DBPATH=$CONFIG_DIR
EnvironmentFile=$INSTALL_DIR/.env
ExecStart=$INSTALL_DIR/venv/bin/python $INSTALL_DIR/cps.py -p $CONFIG_DIR/app.db

Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

  cat << EOF > /etc/systemd/system/acw-ingest-service.service
[Unit]
Description=Autocaliweb Ingest Processor Service
After=autocaliweb.service
Requires=autocaliweb.service

[Service]
User=${SERVICE_USER}
Group=${SERVICE_GROUP}
WorkingDirectory=${INSTALL_DIR}
Environment=CALIBRE_DBPATH=${CONFIG_DIR}
Environment=HOME=${CONFIG_DIR}
ExecStart=/bin/bash ${SCRIPTS_DIR}/ingest_watcher.sh
Restart=always
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

  cat << EOF > /etc/systemd/system/acw-auto-zipper.service
[Unit]
Description=Autocaliweb Auto Zipper Service
After=network.target

[Service]
User=${SERVICE_USER}
Group=${SERVICE_GROUP}
WorkingDirectory=${INSTALL_DIR}
Environment=CALIBRE_DBPATH=${CONFIG_DIR}
ExecStart=${SCRIPTS_DIR}/auto_zipper_wrapper.sh
Restart=always
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

  cat << EOF > /etc/systemd/system/metadata-change-detector.service
[Unit]
Description=Autocaliweb Metadata Change Detector
After=network.target

[Service]
User=${SERVICE_USER}
Group=${SERVICE_GROUP}
WorkingDirectory=${INSTALL_DIR}
ExecStart=/bin/bash ${SCRIPTS_DIR}/metadata_change_detector_wrapper.sh
Restart=always
StandardOutput=journal
StandardError=journal
Environment=CALIBRE_DBPATH=${CONFIG_DIR}
Environment=HOME=${CONFIG_DIR}
[Install]
WantedBy=multi-user.target
EOF

  systemctl -q enable --now autocaliweb acw-ingest-service acw-auto-zipper metadata-change-detector
  msg_ok "Created scripts and service files"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8083${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/autocaliweb ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  setup_uv

  # shellcheck disable=SC2034
  RELEASE=$(get_latest_codeberg_release "gelbphoenix/autocaliweb")
  if check_for_codeberg_release "autocaliweb" "gelbphoenix/autocaliweb"; then
    msg_info "Stopping Services"
    systemctl stop autocaliweb metadata-change-detector acw-ingest-service acw-auto-zipper
    msg_ok "Stopped Services"

    INSTALL_DIR="/opt/autocaliweb"
    export VIRTUAL_ENV="${INSTALL_DIR}/venv"
    $STD tar -cf ~/autocaliweb_bkp.tar "$INSTALL_DIR"/{metadata_change_logs,dirs.json,.env,scripts/ingest_watcher.sh,scripts/auto_zipper_wrapper.sh,scripts/metadata_change_detector_wrapper.sh}
    fetch_and_deploy_codeberg_release "autocaliweb" "gelbphoenix/autocaliweb" "tarball" "latest" "/opt/autocaliweb"

    msg_info "Updating Autocaliweb"
    cd "$INSTALL_DIR" || exit
    if [[ ! -d "$VIRTUAL_ENV" ]]; then
      $STD uv venv --clear "$VIRTUAL_ENV"
    fi
    $STD uv sync --all-extras --active
    cd "$INSTALL_DIR/koreader/plugins" || exit
    PLUGIN_DIGEST="$(find acwsync.koplugin -type f -name "*.lua" -o -name "*.json" | sort | xargs sha256sum | sha256sum | cut -d' ' -f1)"
    echo "Plugin files digest: $PLUGIN_DIGEST" > acwsync.koplugin/"${PLUGIN_DIGEST}".digest
    echo "Build date: $(date)" >> acwsync.koplugin/"${PLUGIN_DIGEST}".digest
    echo "Files included:" >> acwsync.koplugin/"${PLUGIN_DIGEST}".digest
    $STD zip -r koplugin.zip acwsync.koplugin/
    cp -r koplugin.zip "$INSTALL_DIR"/cps/static
    mkdir -p "$INSTALL_DIR"/metadata_temp
    $STD tar -xf ~/autocaliweb_bkp.tar --directory /
    KEPUB_VERSION="$(/usr/bin/kepubify --version)"
    CALIBRE_RELEASE="$(curl -s https://api.github.com/repos/kovidgoyal/calibre/releases/latest | grep -o '"tag_name": "[^"]*' | cut -d'"' -f4)"
    echo "${KEPUB_VERSION#v}" > "$INSTALL_DIR"/KEPUBIFY_RELEASE
    echo "${CALIBRE_RELEASE#v}" > /"$INSTALL_DIR"/CALIBRE_RELEASE
    sed 's/^/v/' ~/.autocaliweb > "$INSTALL_DIR"/ACW_RELEASE
    chown -R acw:acw "$INSTALL_DIR"
    rm ~/autocaliweb_bkp.tar
    msg_ok "Updated Autocaliweb"

    msg_info "Starting Services"
    systemctl start autocaliweb metadata-change-detector acw-ingest-service acw-auto-zipper
    msg_ok "Started Services"

    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
