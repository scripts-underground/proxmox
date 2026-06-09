#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"
source <(curl -fsSL "$REPO_BASE/misc/build.func")

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Thieneret
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/goauthentik/authentik

APP="authentik"
var_tags="${var_tags:-auth}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-16}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/authentik ]]; then
    msg_error "No authentik Installation Found!"
    exit
  fi

  read -r MAJOR MINOR PATCH <<< "$(sed 's/^version\///; s/\./ /g' "$HOME/.authentik")"

  msg_info "Update dependencies"
  ensure_dependencies crossbuild-essential-amd64 gcc-x86-64-linux-gnu cmake clang libunwind-18-dev
  msg_ok "Update dependencies"

  NODE_VERSION="24" setup_nodejs
  setup_go
  UV_PYTHON_INSTALL_DIR="/usr/local/bin" PYTHON_VERSION="3.14.3" setup_uv
  RUST_PROFILE="minimal" RUST_TOOLCHAIN="stable" setup_rust
  setup_yq

  AUTHENTIK_VERSION="version/2026.5.2"
  XMLSEC_VERSION="1.3.11"

  if check_for_gh_release "geoipupdate" "maxmind/geoipupdate"; then
    fetch_and_deploy_gh_release "geoipupdate" "maxmind/geoipupdate" "binary"
  fi

  if check_for_gh_release "xmlsec" "lsh123/xmlsec" "${XMLSEC_VERSION}"; then
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "xmlsec" "lsh123/xmlsec" "tarball" "${XMLSEC_VERSION}" "/opt/xmlsec"

    msg_info "Updating xmlsec"
    cd /opt/xmlsec
    $STD ./autogen.sh
    $STD make -j $(nproc)
    $STD make check
    $STD make install
    $STD ldconfig
    msg_ok "Updated xmlsec"
  fi

  if check_for_gh_release "authentik" "goauthentik/authentik" "${AUTHENTIK_VERSION}"; then
    msg_info "Stopping Services"
    systemctl stop authentik-server authentik-worker
	if [[ $(systemctl is-active authentik-ldap) == active ]]; then
		systemctl stop authentik-ldap
	fi
	if [[ $(systemctl is-active authentik-rac) == active ]]; then
		systemctl stop authentik-rac
	fi
	if [[ $(systemctl is-active authentik-radius) == active ]]; then
		systemctl stop authentik-radius
	fi
    msg_ok "Stopped Services"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "authentik" "goauthentik/authentik" "tarball" "${AUTHENTIK_VERSION}" "/opt/authentik"

	msg_info "Configuring rust"
	cd /opt/authentik
	$STD rustup install
	$STD rustup default "$(sed -n 's/channel = "\(.*\)"/\1/p' rust-toolchain.toml)"
	msg_ok "Configured rust"

	msg_info "Updating web"
    cd /opt/authentik/web
    export NODE_ENV="production"
    $STD npm install
    $STD npm run build
    $STD npm run build:sfe
    msg_ok "Updated web"

    msg_info "Updating go proxy"
    cd /opt/authentik
    export CGO_ENABLED="1"
    $STD go mod download
    $STD go build -o /opt/authentik/authentik-server ./cmd/server
	$STD go build -o /opt/authentik/ldap ./cmd/ldap
	$STD go build -o /opt/authentik/rac ./cmd/rac
	$STD go build -o /opt/authentik/radius ./cmd/radius
    msg_ok "Updated go proxy"

	msg_info "Building worker"
	export AWS_LC_FIPS_SYS_CC="clang"
	cd /opt/authentik
	$STD cargo build --package authentik --no-default-features --features core --locked --release --jobs 1
	cp ./target/release/authentik /opt/authentik/authentik-worker
	rm -r ./target
	msg_ok "Built worker"

    msg_info "Updating python server"
    export UV_NO_BINARY_PACKAGE="cryptography lxml python-kadmin-rs xmlsec"
    export UV_COMPILE_BYTECODE="1"
    export UV_LINK_MODE="copy"
    export UV_NATIVE_TLS="1"
    export RUSTUP_PERMIT_COPY_RENAME="true"
    export UV_PYTHON_INSTALL_DIR="/usr/local/bin"
    cd /opt/authentik
    $STD uv sync --frozen --no-install-project --no-dev
    chown -R authentik:authentik /opt/authentik
    msg_ok "Updated python server"

    if [[ $MAJOR == 2026 && $MINOR -lt 5 ]]; then
	  msg_info "Updating Worker and Server config"
	  cp /etc/authentik/config.yml /etc/authentik/config.bak
	  yq -i ".postgresql.conn_max_age = 0" /etc/authentik/config.yml
	  yq -i ".postgresql.conn_health_checks = false" /etc/authentik/config.yml
	  yq -i ".listen.debug_tokio = \"[::]:6669\"" /etc/authentik/config.yml
      yq -i ".log.rust_log.console_subscriber = \"info\"" /etc/authentik/config.yml
      yq -i ".log.rust_log.h2 = \"info\""  /etc/authentik/config.yml
      yq -i ".log.rust_log.hyper_util = \"warn\"" /etc/authentik/config.yml
      yq -i ".log.rust_log.mio = \"info\"" /etc/authentik/config.yml
      yq -i ".log.rust_log.notify = \"info\"" /etc/authentik/config.yml
	  yq -i ".log.rust_log.reqwest = \"info\"" /etc/authentik/config.yml
      yq -i ".log.rust_log.runtime = \"info\"" /etc/authentik/config.yml
      yq -i ".log.rust_log.rustls = \"info\"" /etc/authentik/config.yml
      yq -i ".log.rust_log.sqlx = \"info\"" /etc/authentik/config.yml
      yq -i ".log.rust_log.sqlx_postgres = \"info\"" /etc/authentik/config.yml
      yq -i ".log.rust_log.tokio = \"info\"" /etc/authentik/config.yml
      yq -i ".log.rust_log.tungstenite = \"info\"" /etc/authentik/config.yml
	  yq -i ".web.workers = 2" /etc/authentik/config.yml
	  mv /etc/default/authentik /etc/default/authentik.bak
	  cat <<EOF >/etc/default/authentik-server
TMPDIR=/dev/shm/
UV_LINK_MODE=copy
UV_PYTHON_DOWNLOADS=0
UV_NATIVE_TLS=1
VENV_PATH=/opt/authentik/.venv
PYTHONDONTWRITEBYTECODE=1
PYTHONUNBUFFERED=1
PATH=/opt/authentik/lifecycle:/opt/authentik/.venv/bin:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin
DJANGO_SETTINGS_MODULE=authentik.root.settings
PROMETHEUS_MULTIPROC_DIR="/tmp/authentik_prometheus_tmp"
AUTHENTIK_LISTEN__HTTP="[::]:9000"
AUTHENTIK_LISTEN__HTTPS="[::]:9443"
AUTHENTIK_LISTEN__METRICS="[::]:9300"
EOF
	  cat <<EOF >/etc/default/authentik-worker
TMPDIR=/dev/shm/
UV_LINK_MODE=copy
UV_PYTHON_DOWNLOADS=0
UV_NATIVE_TLS=1
VENV_PATH=/opt/authentik/.venv
PYTHONDONTWRITEBYTECODE=1
PYTHONUNBUFFERED=1
PATH=/opt/authentik/lifecycle:/opt/authentik/.venv/bin:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin
DJANGO_SETTINGS_MODULE=authentik.root.settings
PROMETHEUS_MULTIPROC_DIR="/tmp/authentik_prometheus_tmp"
AUTHENTIK_LISTEN__HTTP="[::]:8000"
AUTHENTIK_LISTEN__HTTPS="[::]:8443"
AUTHENTIK_LISTEN__METRICS="[::]:8300"
EOF
	  msg_ok "Updated Worker and Server config!"
	  msg_warn "Please check /etc/default/authentik-worker and /etc/default/authentik-server config files for port configurations!"

	  msg_info "Updating services"
	  cat <<EOF >/etc/systemd/system/authentik-server.service
[Unit]
Description=authentik Go Server (API Gateway)
After=network.target
Wants=postgresql.service

[Service]
User=authentik
Group=authentik
ExecStartPre=/usr/bin/mkdir -p "\${PROMETHEUS_MULTIPROC_DIR}"
ExecStart=/opt/authentik/authentik-server
WorkingDirectory=/opt/authentik/
Restart=always
RestartSec=5
EnvironmentFile=/etc/default/authentik-server

[Install]
WantedBy=multi-user.target
EOF

	  cat <<EOF >/etc/systemd/system/authentik-worker.service
[Unit]
Description=authentik Worker
After=network.target postgresql.service

[Service]
User=authentik
Group=authentik
Type=simple
EnvironmentFile=/etc/default/authentik-worker
ExecStartPre=/usr/bin/mkdir -p "\${PROMETHEUS_MULTIPROC_DIR}"
ExecStart=/opt/authentik/authentik-worker worker
WorkingDirectory=/opt/authentik
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
	  systemctl daemon-reload
	  msg_ok "Updated services"
	fi
  fi

  msg_info "Starting Services"
  systemctl start authentik-server authentik-worker
  if [[ $(systemctl is-enabled authentik-ldap) == enabled ]]; then
  	systemctl start authentik-ldap
  fi
  if [[ $(systemctl is-enabled authentik-rac) == enabled ]]; then
  	systemctl start authentik-rac
  fi
  if [[ $(systemctl is-enabled authentik-radius) == enabled ]]; then
  	systemctl start authentik-radius
  fi
  msg_ok "Started Services"
  msg_ok "Updated successfully!"
  exit
}

function install_script() {
  color
  verb_ip6
  catch_errors
  setting_up_container
  network_check
  update_os

  msg_info "Installing Dependencies"
  $STD apt install -y \
    build-essential \
    pkg-config \
    libffi-dev \
    libxslt-dev \
    zlib1g-dev \
    libpq-dev \
    krb5-multidev \
    libkrb5-dev \
    heimdal-multidev \
    libclang-dev \
    libltdl-dev \
    libpq5 \
    libmaxminddb0 \
    libkadm5clnt-mit12 \
    libkadm5clnt7t64-heimdal \
    libltdl7 \
    libxslt1.1 \
    python3-dev \
    libxml2-dev \
    libxml2 \
    libxslt1-dev \
    automake \
    autoconf \
    libtool \
    libtool-bin \
    gcc \
    crossbuild-essential-amd64 \
    gcc-x86-64-linux-gnu \
    cmake \
    clang \
    libunwind-18-dev \
    git
  msg_ok "Installed Dependencies"

  NODE_VERSION="24" setup_nodejs
  setup_yq
  setup_go
  RUST_PROFILE="minimal" RUST_TOOLCHAIN="stable" setup_rust
  UV_PYTHON_INSTALL_DIR="/usr/local/bin" PYTHON_VERSION="3.14.3" setup_uv
  PG_VERSION="17" setup_postgresql
  PG_DB_NAME="authentik" PG_DB_USER="authentik" PG_DB_GRANT_SUPERUSER="true" setup_postgresql_db

  XMLSEC_VERSION="1.3.11"
  AUTHENTIK_VERSION="version/2026.5.3"
  fetch_and_deploy_gh_release "xmlsec" "lsh123/xmlsec" "tarball" "${XMLSEC_VERSION}" "/opt/xmlsec"
  fetch_and_deploy_gh_release "authentik" "goauthentik/authentik" "tarball" "${AUTHENTIK_VERSION}" "/opt/authentik"
  fetch_and_deploy_gh_release "geoipupdate" "maxmind/geoipupdate" "binary"

  msg_info "Setting up xmlsec"
  cd /opt/xmlsec
  $STD ./autogen.sh
  $STD make -j $(nproc)
  $STD make check
  $STD make install
  $STD ldconfig
  msg_ok "Setup xmlsec"

  msg_info "Configuring rust"
  cd /opt/authentik
  $STD rustup install
  $STD rustup default "$(sed -n 's/channel = "\(.*\)"/\1/p' rust-toolchain.toml)"
  msg_ok "Configured rust"

  msg_info "Setting up web"
  cd /opt/authentik/web
  export NODE_ENV="production"
  $STD npm install
  $STD npm run build
  $STD npm run build:sfe
  msg_ok "Setup web"

  msg_info "Setting up go proxy"
  cd /opt/authentik
  export CGO_ENABLED="1"
  export CC="x86_64-linux-gnu-gcc"
  $STD go mod download
  $STD go build -o /opt/authentik/authentik-server ./cmd/server
  $STD go build -o /opt/authentik/ldap ./cmd/ldap
  $STD go build -o /opt/authentik/rac ./cmd/rac
  $STD go build -o /opt/authentik/radius ./cmd/radius
  msg_ok "Setup go proxy"

  cat <<EOF >/usr/local/etc/GeoIP.conf
AccountID ChangeME
LicenseKey ChangeME
EditionIDs GeoLite2-ASN GeoLite2-City GeoLite2-Country
DatabaseDirectory /opt/authentik-data/geoip
RetryFor 5m
Parallelism 1
EOF

  echo "#39 19 * * 6,4 /usr/bin/geoipupdate -f /usr/local/etc/GeoIP.conf" | crontab -

  msg_info "Building worker"
  export AWS_LC_FIPS_SYS_CC="clang"
  cd /opt/authentik
  $STD cargo build --package authentik --no-default-features --features core --locked --release --jobs 1
  cp ./target/release/authentik /opt/authentik/authentik-worker
  rm -r ./target
  msg_ok "Built worker"

  msg_info "Setting up python server"
  export UV_NO_BINARY_PACKAGE="cryptography lxml python-kadmin-rs xmlsec"
  export UV_COMPILE_BYTECODE="1"
  export UV_LINK_MODE="copy"
  export UV_NATIVE_TLS="1"
  export UV_PYTHON_INSTALL_DIR="/usr/local/bin"
  cd /opt/authentik
  $STD uv sync --frozen --no-install-project --no-dev
  cp /opt/authentik/authentik/sources/kerberos/krb5.conf /etc/krb5.conf
  msg_ok "Setup python server"

  msg_info "Creating authentik config"
  mkdir -p /etc/authentik
  mv /opt/authentik/authentik/lib/default.yml /etc/authentik/config.yml
  yq -i ".secret_key = \"$(openssl rand -base64 128 | tr -dc 'a-zA-Z0-9' | head -c64)\"" /etc/authentik/config.yml
  yq -i ".postgresql.password = \"${PG_DB_PASS}\"" /etc/authentik/config.yml
  yq -i ".events.context_processors.geoip = \"/opt/authentik-data/geoip/GeoLite2-City.mmdb\"" /etc/authentik/config.yml
  yq -i ".events.context_processors.asn = \"/opt/authentik-data/geoip/GeoLite2-ASN.mmdb\"" /etc/authentik/config.yml
  yq -i ".blueprints_dir = \"/opt/authentik/blueprints\"" /etc/authentik/config.yml
  yq -i ".cert_discovery_dir = \"/opt/authentik-data/certs\"" /etc/authentik/config.yml
  yq -i ".email.template_dir = \"/opt/authentik-data/templates\"" /etc/authentik/config.yml
  yq -i ".storage.file.path = \"/opt/authentik-data\"" /etc/authentik/config.yml
  yq -i ".disable_startup_analytics = \"true\"" /etc/authentik/config.yml
  $STD useradd -U -s /usr/sbin/nologin -r -M -d /opt/authentik authentik
  chown -R authentik:authentik /opt/authentik
  cat <<EOF >/etc/default/authentik-server
TMPDIR=/dev/shm/
UV_LINK_MODE=copy
UV_PYTHON_DOWNLOADS=0
UV_NATIVE_TLS=1
VENV_PATH=/opt/authentik/.venv
PYTHONDONTWRITEBYTECODE=1
PYTHONUNBUFFERED=1
PATH=/opt/authentik/lifecycle:/opt/authentik/.venv/bin:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin
DJANGO_SETTINGS_MODULE=authentik.root.settings
PROMETHEUS_MULTIPROC_DIR="/tmp/authentik_prometheus_tmp"
AUTHENTIK_LISTEN__HTTP="[::]:9000"
AUTHENTIK_LISTEN__HTTPS="[::]:9443"
AUTHENTIK_LISTEN__METRICS="[::]:9300"
EOF
  cat <<EOF >/etc/default/authentik-worker
TMPDIR=/dev/shm/
UV_LINK_MODE=copy
UV_PYTHON_DOWNLOADS=0
UV_NATIVE_TLS=1
VENV_PATH=/opt/authentik/.venv
PYTHONDONTWRITEBYTECODE=1
PYTHONUNBUFFERED=1
PATH=/opt/authentik/lifecycle:/opt/authentik/.venv/bin:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin
DJANGO_SETTINGS_MODULE=authentik.root.settings
PROMETHEUS_MULTIPROC_DIR="/tmp/authentik_prometheus_tmp"
AUTHENTIK_LISTEN__HTTP="[::]:8000"
AUTHENTIK_LISTEN__HTTPS="[::]:8443"
AUTHENTIK_LISTEN__METRICS="[::]:8300"
EOF
  cat <<EOF >/etc/default/authentik_ldap
AUTHENTIK_HOST="https://127.0.0.1:9443"
AUTHENTIK_INSECURE="true"
AUTHENTIK_TOKEN="token-generated-by-authentik"
EOF
  cat <<EOF >/etc/default/authentik_rac
AUTHENTIK_HOST="https://127.0.0.1:9443"
AUTHENTIK_INSECURE="true"
AUTHENTIK_TOKEN="token-generated-by-authentik"
EOF
  cat <<EOF >/etc/default/authentik_radius
AUTHENTIK_HOST="https://127.0.0.1:9443"
AUTHENTIK_INSECURE="true"
AUTHENTIK_TOKEN="token-generated-by-authentik"
EOF
  msg_ok "Created authentik config"

  msg_info "Creating services"
  cat <<EOF >/etc/systemd/system/authentik-server.service
[Unit]
Description=authentik Go Server (API Gateway)
After=network.target
Wants=postgresql.service

[Service]
User=authentik
Group=authentik
EnvironmentFile=/etc/default/authentik-server
ExecStartPre=/usr/bin/mkdir -p "\${PROMETHEUS_MULTIPROC_DIR}"
ExecStart=/opt/authentik/authentik-server
WorkingDirectory=/opt/authentik/
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  cat <<EOF >/etc/systemd/system/authentik-worker.service
[Unit]
Description=authentik Worker
After=network.target postgresql.service

[Service]
User=authentik
Group=authentik
Type=simple
EnvironmentFile=/etc/default/authentik-worker
ExecStartPre=/usr/bin/mkdir -p "\${PROMETHEUS_MULTIPROC_DIR}"
ExecStart=/opt/authentik/authentik-worker worker
WorkingDirectory=/opt/authentik
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  cat <<EOF >/etc/systemd/system/authentik-ldap.service
[Unit]
Description=authentik LDAP Outpost
After=network.target
Wants=postgresql.service

[Service]
User=authentik
Group=authentik
ExecStart=/opt/authentik/ldap
WorkingDirectory=/opt/authentik/
Restart=always
RestartSec=5
EnvironmentFile=/etc/default/authentik_ldap

[Install]
WantedBy=multi-user.target
EOF

  cat <<EOF >/etc/systemd/system/authentik-rac.service
[Unit]
Description=authentik RAC Outpost
After=network.target
Wants=postgresql.service

[Service]
User=authentik
Group=authentik
ExecStart=/opt/authentik/rac
WorkingDirectory=/opt/authentik/
Restart=always
RestartSec=5
EnvironmentFile=/etc/default/authentik_rac

[Install]
WantedBy=multi-user.target
EOF

  cat <<EOF >/etc/systemd/system/authentik-radius.service
[Unit]
Description=authentik Radius Outpost
After=network.target
Wants=postgresql.service

[Service]
User=authentik
Group=authentik
ExecStart=/opt/authentik/radius
WorkingDirectory=/opt/authentik/
Restart=always
RestartSec=5
EnvironmentFile=/etc/default/authentik_radius

[Install]
WantedBy=multi-user.target
EOF
  msg_ok "Created services"
}

function post_build_script() {
  msg_info "Attaching data storage volume"
  $STD pct stop "$CTID"
  if [ "${PROTECT_CT:-}" == "1" ] || [ "${PROTECT_CT:-}" == "yes" ]; then
    $STD pct set "$CTID" --protection 0
    $STD pct set "$CTID" -mp0 "${CONTAINER_STORAGE}":1,mp=/opt/authentik-data,backup=1
    $STD pct set "$CTID" --protection 1
  else
    $STD pct set "$CTID" -mp0 "${CONTAINER_STORAGE}":1,mp=/opt/authentik-data,backup=1
  fi
  $STD pct start "$CTID"
  for i in {1..10}; do
    pct status "$CTID" | grep -q "status: running" && break
    sleep 1
  done
  $STD pct exec "$CTID" -- bash -c "mkdir -p /opt/authentik-data/{certs,media,geoip,templates}; \
    cp /opt/authentik/tests/GeoLite2-ASN-Test.mmdb /opt/authentik-data/geoip/GeoLite2-ASN.mmdb; \
    cp /opt/authentik/tests/GeoLite2-City-Test.mmdb /opt/authentik-data/geoip/GeoLite2-City.mmdb; \
    chown authentik:authentik /opt/authentik-data; \
    chown -R authentik:authentik /opt/authentik-data/{certs,media,geoip,templates}"
  msg_ok "Attached data storage volume"

  msg_info "Starting Services"
  pct exec "$CTID" -- systemctl enable -q --now authentik-server authentik-worker
  msg_ok "Started Services"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}https://${IP}:9443${CL}"
}

source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
