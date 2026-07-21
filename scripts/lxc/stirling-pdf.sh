#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.stirlingpdf.com/ | Github: https://github.com/Stirling-Tools/Stirling-PDF

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Stirling-PDF"
var_tags="${var_tags:-pdf-editor}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies (Patience)"
  $STD apt install -y \
    automake \
    autoconf \
    libtool \
    libleptonica-dev \
    pkg-config \
    zlib1g-dev \
    make \
    g++ \
    unpaper \
    fonts-urw-base35 \
    qpdf \
    poppler-utils \
    jbig2 \
    patchelf
  msg_ok "Installed Dependencies"

  PYTHON_VERSION="3.12" setup_uv
  JAVA_VERSION="25" setup_java

  read -r -p "${TAB3}Do you want to use Stirling-PDF with Login? (no/n = without Login) [Y/n] " response
  response=${response,,}
  login_mode="false"
  if [[ "$response" == "y" || "$response" == "yes" || -z "$response" ]]; then
    USE_ORIGINAL_FILENAME=true fetch_and_deploy_gh_release "stirling-pdf" "Stirling-Tools/Stirling-PDF" "singlefile" "latest" "/opt/Stirling-PDF" "Stirling-PDF-with-login.jar"
    mv /opt/Stirling-PDF/Stirling-PDF-with-login.jar /opt/Stirling-PDF/Stirling-PDF.jar
    touch ~/.Stirling-PDF-login
    login_mode="true"
  else
    USE_ORIGINAL_FILENAME=true fetch_and_deploy_gh_release "stirling-pdf" "Stirling-Tools/Stirling-PDF" "singlefile" "latest" "/opt/Stirling-PDF" "Stirling-PDF.jar"
  fi

  msg_info "Installing LibreOffice Components"
  $STD apt install -y \
    libreoffice-writer \
    libreoffice-calc \
    libreoffice-impress \
    libreoffice-core \
    libreoffice-common \
    libreoffice-base-core \
    libreoffice-script-provider-python \
    libreoffice-java-common \
    pngquant \
    weasyprint
  msg_ok "Installed LibreOffice Components"

  msg_info "Installing Python Dependencies"
  mkdir -p /tmp/stirling-pdf
  $STD uv venv --clear /opt/.venv
  export PATH="/opt/.venv/bin:$PATH"
  source /opt/.venv/bin/activate
  $STD uv pip install --upgrade pip
  $STD uv pip install \
    opencv-python-headless \
    ocrmypdf \
    pillow \
    pdf2image
  $STD apt install -y python3-uno python3-pip
  $STD pip3 install --break-system-packages --timeout=120 unoserver
  ln -sf /opt/.venv/bin/python3 /usr/local/bin/python3
  ln -sf /opt/.venv/bin/pip /usr/local/bin/pip
  msg_ok "Installed Python Dependencies"

  msg_info "Installing Language Packs (Patience)"
  $STD apt install -y 'tesseract-ocr-*'
  msg_ok "Installed Language Packs"

  msg_info "Creating Environment Variables"
  cat << EOF > /opt/Stirling-PDF/.env
# Java tuning
JAVA_BASE_OPTS="-XX:+UnlockExperimentalVMOptions -XX:MaxRAMPercentage=75 -XX:InitiatingHeapOccupancyPercent=20 -XX:+G1PeriodicGCInvokesConcurrent -XX:G1PeriodicGCInterval=10000 -XX:+UseStringDeduplication -XX:G1PeriodicGCSystemLoadThreshold=70"
JAVA_CUSTOM_OPTS=""

# LibreOffice
PATH=/opt/.venv/bin:/usr/lib/libreoffice/program:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
UNO_PATH=/usr/lib/libreoffice/program
URE_BOOTSTRAP=file:///usr/lib/libreoffice/program/fundamentalrc
PYTHONPATH=/usr/lib/libreoffice/program:/opt/.venv/lib/python3.12/site-packages
LD_LIBRARY_PATH=/usr/lib/libreoffice/program

STIRLING_TEMPFILES_DIRECTORY=/tmp/stirling-pdf
TMPDIR=/tmp/stirling-pdf
TEMP=/tmp/stirling-pdf
TMP=/tmp/stirling-pdf

# Paths
PATH=/opt/.venv/bin:/usr/lib/libreoffice/program:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
EOF

  if [[ "$login_mode" == "true" ]]; then
    cat << EOF > /opt/Stirling-PDF/.env
# activate Login
DISABLE_ADDITIONAL_FEATURES=false
SECURITY_ENABLELOGIN=true

# login credentials
SECURITY_INITIALLOGIN_USERNAME=admin
SECURITY_INITIALLOGIN_PASSWORD=stirling
EOF
  fi
  msg_ok "Created Environment Variables"

  msg_info "Patching Native Libraries for LXC Compatibility"
  find /usr/lib -name "libicudata.so.*" -exec patchelf --clear-execstack {} \; || true
  msg_ok "Patched Native Libraries"

  msg_info "Refreshing Font Cache"
  $STD fc-cache -fv
  msg_ok "Font Cache Updated"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/libreoffice-listener.service
[Unit]
Description=LibreOffice Headless Listener Service
After=network.target

[Service]
Type=simple
User=root
Group=root
ExecStart=/usr/lib/libreoffice/program/soffice --headless --invisible --nodefault --nofirststartwizard --nolockcheck --nologo --accept="socket,host=127.0.0.1,port=2002;urp;StarOffice.ComponentContext"
Restart=always

[Install]
WantedBy=multi-user.target
EOF

  cat << EOF > /etc/systemd/system/stirlingpdf.service
[Unit]
Description=Stirling-PDF service
After=syslog.target network.target libreoffice-listener.service
Requires=libreoffice-listener.service

[Service]
SuccessExitStatus=143
Type=simple
User=root
Group=root
EnvironmentFile=/opt/Stirling-PDF/.env
WorkingDirectory=/opt/Stirling-PDF
ExecStart=/usr/bin/java -jar Stirling-PDF.jar
ExecStop=/bin/kill -15 %n
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

  cat << EOF > /etc/systemd/system/unoserver.service
[Unit]
Description=UnoServer RPC Interface
After=libreoffice-listener.service
Requires=libreoffice-listener.service

[Service]
Type=simple
ExecStart=/usr/local/bin/unoserver --port 2003 --interface 127.0.0.1
Restart=always
EnvironmentFile=/opt/Stirling-PDF/.env

[Install]
WantedBy=multi-user.target
EOF

  systemctl enable -q --now libreoffice-listener
  systemctl enable -q --now stirlingpdf
  systemctl enable -q --now unoserver
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/Stirling-PDF ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "stirling-pdf" "Stirling-Tools/Stirling-PDF"; then
    if [[ ! -f /etc/systemd/system/unoserver.service ]]; then
      msg_custom "\u26A0\ufe0f " "\e[33m" "Legacy installation detected \u2013 please recreate the container using the latest install script."
      exit 0
    fi

    PYTHON_VERSION="3.12" setup_uv
    JAVA_VERSION="25" setup_java

    msg_info "Patching Native Libraries for LXC Compatibility"
    ensure_dependencies patchelf
    find /usr/lib -name "libicudata.so.*" -exec patchelf --clear-execstack {} \; || true
    msg_ok "Patched Native Libraries"

    msg_info "Stopping Services"
    systemctl stop stirlingpdf libreoffice-listener unoserver
    msg_ok "Stopped Services"

    if [[ -f ~/.Stirling-PDF-login ]]; then
      USE_ORIGINAL_FILENAME=true fetch_and_deploy_gh_release "stirling-pdf" "Stirling-Tools/Stirling-PDF" "singlefile" "latest" "/opt/Stirling-PDF" "Stirling-PDF-with-login.jar"
      mv /opt/Stirling-PDF/Stirling-PDF-with-login.jar /opt/Stirling-PDF/Stirling-PDF.jar
    else
      USE_ORIGINAL_FILENAME=true fetch_and_deploy_gh_release "stirling-pdf" "Stirling-Tools/Stirling-PDF" "singlefile" "latest" "/opt/Stirling-PDF" "Stirling-PDF.jar"
    fi

    msg_info "Refreshing Font Cache"
    $STD fc-cache -fv
    msg_ok "Font Cache Updated"

    msg_info "Starting Services"
    systemctl start stirlingpdf libreoffice-listener unoserver
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
