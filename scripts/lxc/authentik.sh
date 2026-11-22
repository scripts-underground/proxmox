#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2046
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Thieneret
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/goauthentik/authentik

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="authentik"
var_tags="${var_tags:-auth}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-16}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"
var_lxc_git_repo="${var_lxc_git_repo:-goauthentik/authentik}"

function install_script() {
  authentik_private_file() {
    local destination=$1 stage
    stage=$(mktemp "${destination}.XXXXXXXX")
    cat > "$stage"
    chown root:root "$stage"
    chmod 0600 "$stage"
    mv -f -- "$stage" "$destination"
  }

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
  AUTHENTIK_VERSION="version/2026.5.2"
  fetch_and_deploy_gh_release "xmlsec" "lsh123/xmlsec" "tarball" "${XMLSEC_VERSION}" "/opt/xmlsec"
  fetch_and_deploy_gh_release "authentik" "$var_lxc_git_repo" "tarball" "${AUTHENTIK_VERSION}" "/opt/authentik"
  fetch_and_deploy_gh_release "geoipupdate" "maxmind/geoipupdate" "binary"

  msg_info "Setting up xmlsec"
  cd /opt/xmlsec || exit
  $STD ./autogen.sh
  $STD make -j $(nproc)
  $STD make check
  $STD make install
  $STD ldconfig
  msg_ok "Setup xmlsec"

  msg_info "Configuring rust"
  cd /opt/authentik || exit
  $STD rustup install
  $STD rustup default "$(sed -n 's/channel = "\(.*\)"/\1/p' rust-toolchain.toml)"
  msg_ok "Configured rust"

  msg_info "Setting up web"
  cd /opt/authentik/web || exit
  export NODE_ENV="production"
  $STD npm install
  $STD npm run build
  $STD npm run build:sfe
  msg_ok "Setup web"

  msg_info "Setting up go proxy"
  cd /opt/authentik || exit
  export CGO_ENABLED="1"
  export CC="x86_64-linux-gnu-gcc"
  $STD go mod download
  $STD go build -o /opt/authentik/authentik-server ./cmd/server
  $STD go build -o /opt/authentik/ldap ./cmd/ldap
  $STD go build -o /opt/authentik/rac ./cmd/rac
  $STD go build -o /opt/authentik/radius ./cmd/radius
  msg_ok "Setup go proxy"

  authentik_private_file /usr/local/etc/GeoIP.conf << EOF
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
  cd /opt/authentik || exit
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
  cd /opt/authentik || exit
  $STD uv sync --frozen --no-install-project --no-dev
  cp /opt/authentik/authentik/sources/kerberos/krb5.conf /etc/krb5.conf
  msg_ok "Setup python server"

  msg_info "Creating authentik config"
  mkdir -p /etc/authentik
  $STD useradd -U -s /usr/sbin/nologin -r -M -d /opt/authentik authentik
  local config_stage
  config_stage=$(mktemp /etc/authentik/.config.XXXXXXXX)
  cp /opt/authentik/authentik/lib/default.yml "$config_stage"
  yq -i ".secret_key = \"$(openssl rand -base64 128 | tr -dc 'a-zA-Z0-9' | head -c64)\"" "$config_stage"
  yq -i ".postgresql.password = \"${PG_DB_PASS}\"" "$config_stage"
  yq -i ".events.context_processors.geoip = \"/opt/authentik-data/geoip/GeoLite2-City.mmdb\"" "$config_stage"
  yq -i ".events.context_processors.asn = \"/opt/authentik-data/geoip/GeoLite2-ASN.mmdb\"" "$config_stage"
  yq -i ".blueprints_dir = \"/opt/authentik/blueprints\"" "$config_stage"
  yq -i ".cert_discovery_dir = \"/opt/authentik-data/certs\"" "$config_stage"
  yq -i ".email.template_dir = \"/opt/authentik-data/templates\"" "$config_stage"
  yq -i ".storage.file.path = \"/opt/authentik-data\"" "$config_stage"
  yq -i ".disable_startup_analytics = \"true\"" "$config_stage"
  chown root:authentik "$config_stage"
  chmod 0640 "$config_stage"
  mv -f -- "$config_stage" /etc/authentik/config.yml
  chown -R authentik:authentik /opt/authentik
  cat << EOF > /etc/default/authentik-server
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
  cat << EOF > /etc/default/authentik-worker
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
  authentik_private_file /etc/default/authentik_ldap << EOF
AUTHENTIK_HOST="https://127.0.0.1:9443"
AUTHENTIK_INSECURE="true"
AUTHENTIK_TOKEN="token-generated-by-authentik"
EOF
  authentik_private_file /etc/default/authentik_rac << EOF
AUTHENTIK_HOST="https://127.0.0.1:9443"
AUTHENTIK_INSECURE="true"
AUTHENTIK_TOKEN="token-generated-by-authentik"
EOF
  authentik_private_file /etc/default/authentik_radius << EOF
AUTHENTIK_HOST="https://127.0.0.1:9443"
AUTHENTIK_INSECURE="true"
AUTHENTIK_TOKEN="token-generated-by-authentik"
EOF
  msg_ok "Created authentik config"

  msg_info "Creating services"
  cat << EOF > /etc/systemd/system/authentik-server.service
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

  cat << EOF > /etc/systemd/system/authentik-worker.service
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

  cat << EOF > /etc/systemd/system/authentik-ldap.service
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

  cat << EOF > /etc/systemd/system/authentik-rac.service
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

  cat << EOF > /etc/systemd/system/authentik-radius.service
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
  $STD pct exec "$CTID" -- bash -e -c "mkdir -p /opt/authentik-data/{certs,media,geoip,templates}; \
    chown authentik:authentik /opt/authentik-data; \
    chown -R authentik:authentik /opt/authentik-data/{certs,media,geoip,templates}"
  msg_ok "Attached data storage volume"

  msg_info "Starting Services"
  pct exec "$CTID" -- systemctl enable -q --now authentik-server authentik-worker
  msg_ok "Started Services"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}https://${IP}:9443${CL}"
  msg_info "GeoIP/ASN policies need real MaxMind databases; no test databases are installed."
  echo "Setup: https://docs.goauthentik.io/install-config/geoip/"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/authentik ]]; then
    msg_error "No authentik Installation Found!"
    exit 1
  fi

  if [[ ! -f /etc/authentik/config.yml ]]; then
    msg_error "No authentik configuration found; refusing to regenerate secrets."
    exit 1
  fi
  local file
  for file in /etc/authentik/config.yml /etc/authentik/config.bak; do
    [[ ! -f "$file" ]] || {
      chown root:authentik "$file"
      chmod 0640 "$file"
    }
  done
  for file in /usr/local/etc/GeoIP.conf /etc/default/authentik_{ldap,rac,radius} /etc/default/authentik.bak; do
    [[ ! -f "$file" ]] || {
      chown root:root "$file"
      chmod 0600 "$file"
    }
  done

  # Inspect only: policy data is operator-owned, including known test databases.
  setup_yq
  local city_database asn_database database digest remaining component resolved link
  local -A inspected_databases=()
  local -a CLEAN_INSTALL_KEEP_PATHS=("${CLEAN_INSTALL_KEEP_PATHS[@]}")
  city_database=$(yq -r '.events.context_processors.geoip // ""' /etc/authentik/config.yml)
  asn_database=$(yq -r '.events.context_processors.asn // ""' /etc/authentik/config.yml)
  for database in "$city_database" "$asn_database" /opt/authentik-data/geoip/GeoLite2-City.mmdb /opt/authentik-data/geoip/GeoLite2-ASN.mmdb; do
    [[ -n "$database" ]] || continue
    # Relative configuration is consumed from the service's application cwd.
    [[ "$database" == /* ]] || database="/opt/authentik/$database"
    [[ -f "$database" ]] || continue
    [[ ! ${inspected_databases["$database"]+present} ]] || continue
    inspected_databases["$database"]=1
    # Walk the consumer's path, preserving every link and the final file. Resolve
    # dot components after links, just as the kernel does, not lexically first.
    remaining=${database#/} resolved=''
    while [[ -n "$remaining" ]]; do
      component=${remaining%%/*}
      if [[ "$remaining" == */* ]]; then remaining=${remaining#*/}; else remaining=''; fi
      case "$component" in
        '' | .) continue ;;
        ..)
          # The consumer must still traverse this directory before going up.
          case "$resolved" in /opt/authentik/*) CLEAN_INSTALL_KEEP_PATHS+=("${resolved#/opt/authentik/}") ;; esac
          resolved=${resolved%/*}
          continue
          ;;
      esac
      resolved+="/$component"
      if [[ -L "$resolved" ]]; then
        case "$resolved" in /opt/authentik/*) CLEAN_INSTALL_KEEP_PATHS+=("${resolved#/opt/authentik/}") ;; esac
        link=$(readlink -- "$resolved") || return $?
        resolved=${resolved%/*}
        [[ "$link" != /* ]] || resolved=''
        remaining="$link${remaining:+/$remaining}"
      fi
    done
    case "$resolved" in /opt/authentik/*) CLEAN_INSTALL_KEEP_PATHS+=("${resolved#/opt/authentik/}") ;; esac
    digest=$(sha256sum < "$database")
    case "${digest%% *}" in
      f936702b51dcb6c94b286d77a6f182c31a1601baf4b27e8e896934deb41f49f2 | 75901b98ed6e58d3bd41af9985044b747a7ec0be1369f930c24f5e044427181a)
        msg_warn "MaxMind test database at $database is not production policy data; retained unchanged. Replace it with real MaxMind data: https://docs.goauthentik.io/install-config/geoip/"
        ;;
    esac
  done

  read -r MAJOR MINOR PATCH <<< "$(sed 's/^version\///; s/\./ /g' "$HOME/.authentik")"

  msg_info "Update dependencies"
  ensure_dependencies crossbuild-essential-amd64 gcc-x86-64-linux-gnu cmake clang libunwind-18-dev
  msg_ok "Update dependencies"

  NODE_VERSION="24" setup_nodejs
  setup_go
  UV_PYTHON_INSTALL_DIR="/usr/local/bin" PYTHON_VERSION="3.14.3" setup_uv
  RUST_PROFILE="minimal" RUST_TOOLCHAIN="stable" setup_rust

  AUTHENTIK_VERSION="version/2026.5.2"
  XMLSEC_VERSION="1.3.11"

  local geoip_release='' xmlsec_release='' authentik_release='' status
  if check_for_gh_release "geoipupdate" "maxmind/geoipupdate"; then
    geoip_release=$CHECK_UPDATE_RELEASE
  else
    status=$?
    [[ "$status" == 1 ]] || return "$status"
  fi
  if check_for_gh_release "xmlsec" "lsh123/xmlsec" "${XMLSEC_VERSION}"; then
    xmlsec_release=$CHECK_UPDATE_RELEASE
  else
    status=$?
    [[ "$status" == 1 ]] || return "$status"
  fi
  if check_for_gh_release "authentik" "$var_lxc_git_repo" "${AUTHENTIK_VERSION}"; then
    authentik_release=$CHECK_UPDATE_RELEASE
  else
    status=$?
    [[ "$status" == 1 ]] || return "$status"
  fi

  if [[ -n "$geoip_release" ]]; then
    fetch_and_deploy_gh_release "geoipupdate" "maxmind/geoipupdate" "binary" "$geoip_release"
  fi

  if [[ -n "$xmlsec_release" ]]; then
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "xmlsec" "lsh123/xmlsec" "tarball" "$xmlsec_release" "/opt/xmlsec"

    msg_info "Updating xmlsec"
    cd /opt/xmlsec || exit
    $STD ./autogen.sh
    $STD make -j $(nproc)
    $STD make check
    $STD make install
    $STD ldconfig
    msg_ok "Updated xmlsec"
  fi

  if [[ -n "$authentik_release" ]]; then
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

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "authentik" "$var_lxc_git_repo" "tarball" "$authentik_release" "/opt/authentik"

    msg_info "Configuring rust"
    cd /opt/authentik || exit
    $STD rustup install
    $STD rustup default "$(sed -n 's/channel = "\(.*\)"/\1/p' rust-toolchain.toml)"
    msg_ok "Configured rust"

    msg_info "Updating web"
    cd /opt/authentik/web || exit
    export NODE_ENV="production"
    $STD npm install
    $STD npm run build
    $STD npm run build:sfe
    msg_ok "Updated web"

    msg_info "Updating go proxy"
    cd /opt/authentik || exit
    export CGO_ENABLED="1"
    $STD go mod download
    $STD go build -o /opt/authentik/authentik-server ./cmd/server
    $STD go build -o /opt/authentik/ldap ./cmd/ldap
    $STD go build -o /opt/authentik/rac ./cmd/rac
    $STD go build -o /opt/authentik/radius ./cmd/radius
    msg_ok "Updated go proxy"

    msg_info "Building worker"
    export AWS_LC_FIPS_SYS_CC="clang"
    cd /opt/authentik || exit
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
    cd /opt/authentik || exit
    $STD uv sync --frozen --no-install-project --no-dev
    chown -R authentik:authentik /opt/authentik
    msg_ok "Updated python server"

    if [[ $MAJOR == 2026 && $MINOR -lt 5 ]]; then
      msg_info "Updating Worker and Server config"
      cp --preserve=mode,ownership /etc/authentik/config.yml /etc/authentik/config.bak
      yq -i ".postgresql.conn_max_age = 0" /etc/authentik/config.yml
      yq -i ".postgresql.conn_health_checks = false" /etc/authentik/config.yml
      yq -i ".listen.debug_tokio = \"[::]:6669\"" /etc/authentik/config.yml
      yq -i ".log.rust_log.console_subscriber = \"info\"" /etc/authentik/config.yml
      yq -i ".log.rust_log.h2 = \"info\"" /etc/authentik/config.yml
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
      chown root:root /etc/default/authentik
      chmod 0600 /etc/default/authentik
      mv /etc/default/authentik /etc/default/authentik.bak
      cat << EOF > /etc/default/authentik-server
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
      cat << EOF > /etc/default/authentik-worker
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
      cat << EOF > /etc/systemd/system/authentik-server.service
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

      cat << EOF > /etc/systemd/system/authentik-worker.service
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

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc") --script-id "authentik" -- "$@"
