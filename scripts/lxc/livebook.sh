#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: dkuku
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/livebook-dev/livebook

# shellcheck disable=SC2034
APP="Livebook"
var_tags="${var_tags:-development}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-ubuntu}"
var_version="${var_version:-24.04}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    build-essential \
    ca-certificates \
    cmake \
    git \
    libncurses5-dev
  msg_ok "Installed Dependencies"

  msg_info "Creating livebook user"
  mkdir -p /opt/livebook /data
  export HOME=/opt/livebook
  $STD adduser --system --group --home /opt/livebook --shell /bin/bash livebook
  msg_ok "Created livebook user"

  msg_warn "Running installer from https://elixir-lang.org - review before proceeding"
  curl -fsSL "https://elixir-lang.org/install.sh" -o /opt/livebook/install.sh
  $STD bash /opt/livebook/install.sh elixir@latest otp@latest
  msg_ok "Elixir installer completed"

  msg_info "Setup Erlang and Elixir"
  ERLANG_VERSION=$(ls /opt/livebook/.elixir-install/installs/otp/ | head -n1)
  ELIXIR_VERSION=$(ls /opt/livebook/.elixir-install/installs/elixir/ | head -n1)
  LIVEBOOK_PASSWORD=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c16)

  export ERLANG_BIN="/opt/livebook/.elixir-install/installs/otp/$ERLANG_VERSION/bin"
  export ELIXIR_BIN="/opt/livebook/.elixir-install/installs/elixir/$ELIXIR_VERSION/bin"
  export PATH="$ERLANG_BIN:$ELIXIR_BIN:$PATH"

  $STD mix local.hex --force
  $STD mix local.rebar --force
  $STD mix escript.install hex livebook --force

  cat << EOF > /opt/livebook/.env
export HOME=/opt/livebook
export ERLANG_VERSION=$ERLANG_VERSION
export ELIXIR_VERSION=$ELIXIR_VERSION
export LIVEBOOK_PORT=8080
export LIVEBOOK_IP="::"
export LIVEBOOK_HOME=/data
export LIVEBOOK_PASSWORD="$LIVEBOOK_PASSWORD"
export ESCRIPTS_BIN=/opt/livebook/.mix/escripts
export ERLANG_BIN="/opt/livebook/.elixir-install/installs/otp/\${ERLANG_VERSION}/bin"
export ELIXIR_BIN="/opt/livebook/.elixir-install/installs/elixir/\${ELIXIR_VERSION}/bin"
export PATH="\$ESCRIPTS_BIN:\$ERLANG_BIN:\$ELIXIR_BIN:\$PATH"
EOF

  cat << EOF > /root/livebook.creds
Livebook-Credentials
Livebook Password: $LIVEBOOK_PASSWORD
EOF
  msg_ok "Installed Erlang $ERLANG_VERSION and Elixir $ELIXIR_VERSION"

  msg_info "Installing Livebook"
  cat << EOF > /etc/systemd/system/livebook.service
[Unit]
Description=Livebook
After=network.target

[Service]
Type=exec
User=livebook
Group=livebook
WorkingDirectory=/data
EnvironmentFile=-/opt/livebook/.env
ExecStart=/bin/bash -c 'source /opt/livebook/.env && cd /opt/livebook && livebook server'
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  chown -R livebook:livebook /opt/livebook /data
  systemctl enable -q --now livebook
  msg_ok "Installed Livebook"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8080${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /opt/livebook/.mix/escripts/livebook ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "livebook" "livebook-dev/livebook"; then
    msg_info "Stopping Service"
    systemctl stop livebook
    msg_ok "Stopped Service"

    msg_info "Updating Container"
    $STD apt update
    $STD apt upgrade -y
    msg_ok "Updated Container"

    msg_info "Updating Livebook"
    source /opt/livebook/.env
    cd /opt/livebook || exit
    $STD mix escript.install hex livebook --force

    chown -R livebook:livebook /opt/livebook /data

    msg_info "Starting Service"
    systemctl start livebook
    msg_ok "Started Service"

    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
