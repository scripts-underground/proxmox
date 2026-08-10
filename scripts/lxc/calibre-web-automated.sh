#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2026 scripts-underground.org
# Author: Alex Indigo (alexindigo)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/crocodilestick/Calibre-Web-Automated

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Calibre-Web-Automated"
var_tags="${var_tags:-media;books}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_lxc_git_repo="${var_lxc_git_repo:-crocodilestick/Calibre-Web-Automated}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y --no-install-recommends \
    build-essential \
    python3-dev \
    libldap2-dev \
    libssl-dev \
    libsasl2-dev \
    gettext \
    imagemagick \
    ghostscript \
    libmagic1 \
    libxi6 \
    libxslt1.1 \
    libxtst6 \
    libxrandr2 \
    libxkbfile1 \
    libxcomposite1 \
    libxcursor1 \
    libxfixes3 \
    libxrender1 \
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
    sqlite3 \
    unrar-free \
    zip
  msg_ok "Installed Dependencies"

  kepubify_arch=$(uname -m)
  [[ "$kepubify_arch" == "x86_64" ]] && kepubify_arch="64bit"
  [[ "$kepubify_arch" == "aarch64" ]] && kepubify_arch="arm64"
  fetch_and_deploy_gh_release "kepubify" "pgaskin/kepubify" "singlefile" "latest" "/usr/bin" "kepubify-linux-${kepubify_arch}"
  KEPUB_VERSION="$(/usr/bin/kepubify --version | awk '{print $2}')"

  CALIBRE_ARCH=$(uname -m)
  [[ "$CALIBRE_ARCH" == "aarch64" ]] && CALIBRE_ARCH="arm64"
  fetch_and_deploy_gh_release "calibre" "kovidgoyal/calibre" "prebuild" "latest" "/opt/calibre" "calibre-*-${CALIBRE_ARCH}.txz"

  msg_info "Installing Calibre"
  $STD /opt/calibre/calibre_postinstall
  CALIBRE_VERSION=$(cat ~/.calibre 2> /dev/null || echo "unknown")
  msg_ok "Installed Calibre"

  PYTHON_VERSION="3.13" setup_uv

  fetch_and_deploy_gh_release "calibre-web-automated" "$var_lxc_git_repo" "tarball" "latest" "/app/calibre-web-automated"

  msg_info "Configuring Calibre-Web-Automated"
  INSTALL_DIR="/app/calibre-web-automated"
  CONFIG_DIR="/config"
  CALIBRE_LIB_DIR="/calibre-library"
  INGEST_DIR="/cwa-book-ingest"
  SCRIPTS_DIR="${INSTALL_DIR}/scripts"
  export VIRTUAL_ENV="${INSTALL_DIR}/.venv"

  mkdir -p "$CONFIG_DIR"/{.config/calibre/plugins,log_archive,.cwa_conversion_tmp}
  mkdir -p "$CONFIG_DIR"/processed_books/{converted,imported,failed,fixed_originals}
  mkdir -p "$INSTALL_DIR"/{metadata_change_logs,metadata_temp}
  mkdir -p "$CALIBRE_LIB_DIR" "$INGEST_DIR"

  # CWA's ingest processor chowns files to the Docker uid:gid (abc:abc).
  useradd -r abc 2> /dev/null || true

  echo "$CALIBRE_VERSION" > "$INSTALL_DIR"/CALIBRE_RELEASE
  echo "${KEPUB_VERSION#v}" > "$INSTALL_DIR"/KEPUBIFY_RELEASE
  sed 's/^/v/' ~/.calibre-web-automated > "$INSTALL_DIR"/CWA_RELEASE 2> /dev/null || true

  cd "$INSTALL_DIR" || exit
  $STD uv venv --clear "$VIRTUAL_ENV"
  $STD uv pip install --python "$VIRTUAL_ENV"/bin/python --no-cache-dir --upgrade pip setuptools wheel
  $STD uv pip install --python "$VIRTUAL_ENV"/bin/python --no-cache-dir -r requirements.txt -r optional-requirements.txt
  # Force a compatible cryptography + pyOpenSSL pair — the requirements.txt
  # range `cryptography>=39.0.0,<45.0.0` can resolve to a version whose FFI
  # bindings lack X509_V_FLAG_NOTIFY_POLICY, which the resolved pyOpenSSL needs.
  $STD uv pip install --python "$VIRTUAL_ENV"/bin/python --no-cache-dir --upgrade cryptography pyOpenSSL

  # Fix: secure_filename() strips the dot from non-ASCII filenames (e.g. 资本论.epub → 'epub').
  # Restore the original file extension so the ingest processor can detect the format.
  sed -i '/base_name = secure_filename(uploaded_file.filename)/a\
    # Preserve file extension for non-ASCII filenames\
    if "." in uploaded_file.filename:\
        ext = uploaded_file.filename.rsplit(".", 1)[-1].lower()\
        if not base_name.endswith("." + ext):\
            base_name = base_name.rsplit(".", 1)[0] + "." + ext' \
    "$INSTALL_DIR"/cps/editbooks.py

  cat << EOF > "$INSTALL_DIR"/dirs.json
{
  "ingest_folder": "$INGEST_DIR",
  "calibre_library_dir": "$CALIBRE_LIB_DIR",
  "tmp_conversion_dir": "$CONFIG_DIR/.cwa_conversion_tmp"
}
EOF

  ln -sf "$CONFIG_DIR"/.config/calibre/plugins "$CONFIG_DIR"/calibre_plugins
  cat << EOF > "$INSTALL_DIR"/.env
CWA_INSTALL_DIR=$INSTALL_DIR
CWA_CONFIG_DIR=$CONFIG_DIR
LIBRARY_DIR=$CALIBRE_LIB_DIR
CALIBRE_DBPATH=$CONFIG_DIR
HOME=$CONFIG_DIR
EOF
  msg_ok "Configured Calibre-Web-Automated"

  msg_info "Creating CWASync Plugin for KOReader"
  if [[ -d "$INSTALL_DIR"/koreader/plugins/cwasync.koplugin ]]; then
    cd "$INSTALL_DIR"/koreader/plugins || exit
    PLUGIN_DIGEST="$(find cwasync.koplugin -type f \( -name "*.lua" -o -name "*.json" \) | sort | xargs sha256sum | sha256sum | cut -d' ' -f1)"
    {
      echo "Plugin files digest: $PLUGIN_DIGEST"
      echo "Build date: $(date)"
      echo "Files included:"
      find cwasync.koplugin -type f \( -name "*.lua" -o -name "*.json" \) | sort
    } > "cwasync.koplugin/${PLUGIN_DIGEST}.digest"
    $STD zip -r koplugin.zip cwasync.koplugin/
    mkdir -p "$INSTALL_DIR"/cps/static
    cp koplugin.zip "$INSTALL_DIR"/cps/static/
    msg_ok "Created CWASync Plugin"
  else
    msg_ok "CWASync Plugin folder not present — skipped"
  fi

  msg_info "Initializing database"
  if [[ -f "$INSTALL_DIR"/empty_library/metadata.db && ! -f "$CALIBRE_LIB_DIR"/metadata.db ]]; then
    cp "$INSTALL_DIR"/empty_library/metadata.db "$CALIBRE_LIB_DIR"/metadata.db
  fi
  KEPUBIFY_PATH=$(command -v kepubify 2> /dev/null || echo "/usr/bin/kepubify")
  EBOOK_CONVERT_PATH=$(command -v ebook-convert 2> /dev/null || echo "/usr/bin/ebook-convert")
  CALIBRE_BIN_DIR=$(dirname "$EBOOK_CONVERT_PATH")
  # app.db is created by cps.py on first run; binary paths are enforced at startup
  # from CWA_CONFIG_DIR/dirs.json and the calibre binaries symlinked above.
  export EBOOK_CONVERT_PATH KEPUBIFY_PATH CALIBRE_BIN_DIR
  msg_ok "Initialized database"

  msg_info "Creating scripts and service files"

  cat << EOF > "$SCRIPTS_DIR"/ingest_watcher.sh
#!/bin/bash

INSTALL_PATH="$INSTALL_DIR"
WATCH_FOLDER=\$(grep -o '"ingest_folder": "[^"]*' \${INSTALL_PATH}/dirs.json | grep -o '[^"]*\$')
echo "[cwa-ingest-service] Watching folder: \$WATCH_FOLDER"

/usr/bin/inotifywait -m -r --format="%e %w%f" -e close_write -e moved_to "\$WATCH_FOLDER" \\
  | while read -r events filepath; do
    echo "[cwa-ingest-service] New files detected - \$filepath - Starting Ingest Processor..."
    \${INSTALL_PATH}/.venv/bin/python \${INSTALL_PATH}/scripts/ingest_processor.py "\$filepath"
  done
EOF

  cat << EOF > "$SCRIPTS_DIR"/auto_zipper_wrapper.sh
#!/bin/bash

source ${INSTALL_DIR}/.venv/bin/activate

WAKEUP="23:59"

while true; do
  SECS=\$((\$(date -d "\$WAKEUP" +%s) - \$(date -d "now" +%s)))
  if [[ \$SECS -lt 0 ]]; then
    SECS=\$((\$(date -d "tomorrow \$WAKEUP" +%s) - \$(date -d "now" +%s)))
  fi
  echo "[cwa-auto-zipper] Next run in \$SECS seconds."
  sleep \$SECS &
  wait \$!

  python ${SCRIPTS_DIR}/auto_zip.py
  rc=\$?

  if [[ \$rc == 1 ]]; then
    echo "[cwa-auto-zipper] Error occurred during script initialisation."
  elif [[ \$rc == 2 ]]; then
    echo "[cwa-auto-zipper] Error occurred while zipping today's files."
  elif [[ \$rc == 3 ]]; then
    echo "[cwa-auto-zipper] Error occurred while trying to remove zipped files."
  fi

  sleep 60
done
EOF

  cat << EOF > "$SCRIPTS_DIR"/metadata_change_detector_wrapper.sh
#!/bin/bash

source ${INSTALL_DIR}/.venv/bin/activate

CHECK_INTERVAL=300
METADATA_LOGS_DIR="${INSTALL_DIR}/metadata_change_logs"

echo "[metadata-change-detector] Starting metadata change detector service..."
echo "[metadata-change-detector] Checking for changes every \$CHECK_INTERVAL seconds"

while true; do
  if [ -d "\$METADATA_LOGS_DIR" ] && [ "\$(ls -A \$METADATA_LOGS_DIR 2> /dev/null)" ]; then
    echo "[metadata-change-detector] Found metadata change logs, processing..."

    for log_file in "\$METADATA_LOGS_DIR"/*.json; do
      if [ -f "\$log_file" ]; then
        log_name=\$(basename "\$log_file")
        echo "[metadata-change-detector] Processing log: \$log_name"

        ${INSTALL_DIR}/.venv/bin/python ${SCRIPTS_DIR}/cover_enforcer.py --log "\$log_name"

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

  cat << EOF > /etc/systemd/system/calibre-web-automated.service
[Unit]
Description=Calibre-Web-Automated
After=network.target
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
Environment=PATH=$VIRTUAL_ENV/bin:/usr/bin:/bin
Environment=PYTHONPATH=$SCRIPTS_DIR:$INSTALL_DIR
Environment=PYTHONDONTWRITEBYTECODE=1
Environment=PYTHONUNBUFFERED=1
Environment=CALIBRE_DBPATH=$CONFIG_DIR
Environment=QTWEBENGINE_CHROMIUM_FLAGS=--no-sandbox
Environment=CWA_PORT_OVERRIDE=80
EnvironmentFile=$INSTALL_DIR/.env
ExecStart=$VIRTUAL_ENV/bin/python $INSTALL_DIR/cps.py -p $CONFIG_DIR/app.db
AmbientCapabilities=CAP_NET_BIND_SERVICE
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

  cat << EOF > /etc/systemd/system/cwa-ingest.service
[Unit]
Description=Calibre-Web-Automated Ingest Processor Service
After=calibre-web-automated.service
Requires=calibre-web-automated.service

[Service]
User=root
WorkingDirectory=$INSTALL_DIR
Environment=CALIBRE_DBPATH=$CONFIG_DIR
Environment=HOME=$CONFIG_DIR
Environment=CWA_PORT_OVERRIDE=80
ExecStart=/bin/bash $SCRIPTS_DIR/ingest_watcher.sh
Restart=always
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

  cat << EOF > /etc/systemd/system/cwa-auto-zipper.service
[Unit]
Description=Calibre-Web-Automated Auto Zipper Service
After=network.target

[Service]
User=root
WorkingDirectory=$INSTALL_DIR
Environment=CALIBRE_DBPATH=$CONFIG_DIR
ExecStart=$SCRIPTS_DIR/auto_zipper_wrapper.sh
Restart=always
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

  cat << EOF > /etc/systemd/system/cwa-metadata-detector.service
[Unit]
Description=Calibre-Web-Automated Metadata Change Detector
After=network.target

[Service]
User=root
WorkingDirectory=$INSTALL_DIR
Environment=CALIBRE_DBPATH=$CONFIG_DIR
Environment=HOME=$CONFIG_DIR
ExecStart=/bin/bash $SCRIPTS_DIR/metadata_change_detector_wrapper.sh
Restart=always
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

  systemctl -q enable --now calibre-web-automated cwa-ingest cwa-auto-zipper cwa-metadata-detector
  msg_ok "Created scripts and service files"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /app/calibre-web-automated ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  PYTHON_VERSION="3.13" setup_uv

  if check_for_gh_release "calibre-web-automated" "$var_lxc_git_repo"; then
    msg_info "Stopping Services"
    systemctl stop calibre-web-automated cwa-metadata-detector cwa-ingest cwa-auto-zipper
    msg_ok "Stopped Services"

    INSTALL_DIR="/app/calibre-web-automated"
    SCRIPTS_DIR="${INSTALL_DIR}/scripts"
    export VIRTUAL_ENV="${INSTALL_DIR}/.venv"

    $STD tar -cf ~/calibre-web-automated_bkp.tar \
      "$INSTALL_DIR"/metadata_change_logs \
      "$INSTALL_DIR"/dirs.json \
      "$INSTALL_DIR"/.env \
      "$INSTALL_DIR"/scripts/ingest_watcher.sh \
      "$INSTALL_DIR"/scripts/auto_zipper_wrapper.sh \
      "$INSTALL_DIR"/scripts/metadata_change_detector_wrapper.sh

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "calibre-web-automated" "$var_lxc_git_repo" "tarball" "latest" "/app/calibre-web-automated"

    # Re-apply non-ASCII filename fix (CLEAN_INSTALL wipes the source).
    sed -i '/base_name = secure_filename(uploaded_file.filename)/a\
    # Preserve file extension for non-ASCII filenames\
    if "." in uploaded_file.filename:\
        ext = uploaded_file.filename.rsplit(".", 1)[-1].lower()\
        if not base_name.endswith("." + ext):\
            base_name = base_name.rsplit(".", 1)[0] + "." + ext' \
      "$INSTALL_DIR"/cps/editbooks.py

    msg_info "Updating Calibre-Web-Automated"
    cd "$INSTALL_DIR" || exit
    if [[ ! -d "$VIRTUAL_ENV" ]]; then
      $STD uv venv --clear "$VIRTUAL_ENV"
    fi
    $STD uv pip install --python "$VIRTUAL_ENV"/bin/python --no-cache-dir --upgrade pip setuptools wheel
    $STD uv pip install --python "$VIRTUAL_ENV"/bin/python --no-cache-dir -r requirements.txt -r optional-requirements.txt
    # Match install_script() — force compatible cryptography + pyOpenSSL versions.
    $STD uv pip install --python "$VIRTUAL_ENV"/bin/python --no-cache-dir --upgrade cryptography pyOpenSSL

    if [[ -d "$INSTALL_DIR"/koreader/plugins/cwasync.koplugin ]]; then
      cd "$INSTALL_DIR"/koreader/plugins || exit
      PLUGIN_DIGEST="$(find cwasync.koplugin -type f \( -name "*.lua" -o -name "*.json" \) | sort | xargs sha256sum | sha256sum | cut -d' ' -f1)"
      {
        echo "Plugin files digest: $PLUGIN_DIGEST"
        echo "Build date: $(date)"
        echo "Files included:"
        find cwasync.koplugin -type f \( -name "*.lua" -o -name "*.json" \) | sort
      } > "cwasync.koplugin/${PLUGIN_DIGEST}.digest"
      $STD zip -r koplugin.zip cwasync.koplugin/
      mkdir -p "$INSTALL_DIR"/cps/static
      cp koplugin.zip "$INSTALL_DIR"/cps/static/
    fi

    mkdir -p "$INSTALL_DIR"/metadata_temp
    $STD tar -xf ~/calibre-web-automated_bkp.tar --directory /

    KEPUB_VERSION="$(/usr/bin/kepubify --version | awk '{print $2}')"
    CALIBRE_RELEASE="$(curl -s https://api.github.com/repos/kovidgoyal/calibre/releases/latest | grep -o '"tag_name": "[^"]*' | cut -d'"' -f4)"
    echo "${KEPUB_VERSION#v}" > "$INSTALL_DIR"/KEPUBIFY_RELEASE
    echo "${CALIBRE_RELEASE#v}" > "$INSTALL_DIR"/CALIBRE_RELEASE
    sed 's/^/v/' ~/.calibre-web-automated > "$INSTALL_DIR"/CWA_RELEASE 2> /dev/null || true
    rm -f ~/calibre-web-automated_bkp.tar
    msg_ok "Updated Calibre-Web-Automated"

    msg_info "Starting Services"
    systemctl start calibre-web-automated cwa-metadata-detector cwa-ingest cwa-auto-zipper
    msg_ok "Started Services"

    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
