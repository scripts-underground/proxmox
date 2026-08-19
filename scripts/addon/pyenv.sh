#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 tteck
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://pyenv.run/ | Github: https://github.com/pyenv/pyenv

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="pyenv"

# Bundle-consumed configuration (var_addon_* is baked into update/uninstall
# bundles at install time — hooks may reference these directly)
var_addon_pyenv_root="${var_addon_pyenv_root:-${HOME}/.pyenv}"
var_addon_python_series="${var_addon_python_series:-3.14}"

function install_script() {
  if [[ "$OS_FAMILY" != "debian" ]]; then
    msg_error "Unsupported OS: ${OS_TYPE} (Debian/Ubuntu only)"
    exit 1
  fi

  export PYENV_ROOT="$var_addon_pyenv_root"

  msg_info "Installing dependencies"
  $STD apt update

  # Official Python build dependencies for Debian/Ubuntu
  # https://github.com/pyenv/pyenv/wiki#suggested-build-environment
  local -a PYENV_DEPS=(
    build-essential
    libssl-dev
    zlib1g-dev
    libbz2-dev
    libreadline-dev
    libsqlite3-dev
    curl
    git
    xz-utils
    tk-dev
    libxml2-dev
    libxmlsec1-dev
    libffi-dev
    liblzma-dev
  )

  # Extras for the optional Home Assistant / ESPHome installs below (Pillow et al.)
  PYENV_DEPS+=(make llvm libjpeg-dev libpcap-dev libopenjp2-7)

  # These were renamed between releases (libtiff5 is gone on Debian 13 / Ubuntu 24.04),
  # so take whichever variant the distro actually ships
  local candidates pkg
  for candidates in "libncurses-dev libncursesw5-dev" "libtiff-dev libtiff5-dev" "libturbojpeg0-dev libturbojpeg-dev"; do
    for pkg in $candidates; do
      if apt-cache show "$pkg" &> /dev/null; then
        PYENV_DEPS+=("$pkg")
        break
      fi
    done
  done

  install_packages_with_retry "${PYENV_DEPS[@]}"
  msg_ok "Installed dependencies"

  # The upstream installer refuses to run when PYENV_ROOT already exists
  if [[ -d "$PYENV_ROOT" ]]; then
    msg_ok "${APP} is already installed at ${PYENV_ROOT}"
  else
    msg_info "Installing ${APP}"
    # Official installer - also sets up the pyenv-doctor/update/virtualenv plugins
    $STD bash <(curl -fsSL https://pyenv.run)
    msg_ok "Installed ${APP}"
  fi

  # Shell setup per upstream docs. On Debian-based systems ~/.profile prepends the
  # per-user bin dirs *after* sourcing ~/.bashrc, so both files need the init call.
  msg_info "Configuring shell environment"
  local rc
  for rc in "${HOME}/.bashrc" "${HOME}/.profile"; do
    [[ -f "$rc" ]] || touch "$rc"
    if ! grep -q 'PYENV_ROOT' "$rc"; then
      cat >> "$rc" << 'EOF'

# pyenv
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init - bash)"
EOF
    fi
  done
  msg_ok "Configured shell environment"

  # Activate pyenv for the remainder of this script (the eval would otherwise
  # trip the error traps catch_errors installed: set -Ee -o pipefail)
  export PATH="${PYENV_ROOT}/bin:${PATH}"
  set +Ee +o pipefail
  eval "$(pyenv init - bash)"
  set -Ee -o pipefail

  # pyenv resolves a version prefix to the latest release in that line, so pinning
  # a patch level (the old 3.11.1) is neither needed nor portable across distros.
  #
  # 3.14 is the only series all three optional payloads below agree on:
  #   Home Assistant Core   >= 3.14.2
  #   ESPHome               >= 3.12.0, < 3.15
  #   python-matter-server  >= 3.12
  # (3.11 has been security-fix-only since 2024 and is EOL in 10/2027.)
  msg_info "Installing Python ${var_addon_python_series} (latest patch release)"
  $STD pyenv install -s "$var_addon_python_series"
  pyenv global "$var_addon_python_series"
  msg_ok "Installed Python $(pyenv version-name)"

  local prompt=""
  read -rp "Would you like to install Home Assistant Beta? <y/N> " prompt || true
  if [[ "${prompt,,}" =~ ^(y|yes)$ ]]; then
    msg_info "Installing Home Assistant Beta"
    cat << 'EOF' > /etc/systemd/system/homeassistant.service
[Unit]
Description=Home Assistant
After=network-online.target
[Service]
Type=simple
WorkingDirectory=/root/.homeassistant
ExecStart=/srv/homeassistant/bin/hass -c "/root/.homeassistant"
RestartForceExitStatus=100
[Install]
WantedBy=multi-user.target
EOF
    mkdir /srv/homeassistant
    cd /srv/homeassistant
    python3 -m venv .
    # shellcheck source=/dev/null
    source bin/activate
    $STD python3 -m pip install wheel
    $STD pip3 install --upgrade pip
    $STD pip3 install psycopg2-binary
    $STD pip3 install --pre homeassistant
    systemctl enable homeassistant &> /dev/null
    msg_ok "Installed Home Assistant Beta"
  fi

  prompt=""
  read -rp "Would you like to install ESPHome Beta? <y/N> " prompt || true
  if [[ "${prompt,,}" =~ ^(y|yes)$ ]]; then
    msg_info "Installing ESPHome Beta"
    mkdir /srv/esphome
    cd /srv/esphome
    python3 -m venv .
    # shellcheck source=/dev/null
    source bin/activate
    $STD python3 -m pip install wheel
    $STD pip3 install --upgrade pip
    $STD pip3 install --pre esphome
    cat << 'EOF' > /srv/esphome/start.sh
#!/usr/bin/env bash

# Copyright (c) 2021-2026 tteck
# Author: tteck (tteckster)
# License: MIT
# https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

source /srv/esphome/bin/activate
esphome dashboard /srv/esphome/
EOF
    chmod +x start.sh
    cat << 'EOF' > /etc/systemd/system/esphomedashboard.service
[Unit]
Description=ESPHome Dashboard Service
After=network.target
[Service]
Type=simple
User=root
WorkingDirectory=/srv/esphome
ExecStart=/srv/esphome/start.sh
RestartSec=30
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
    systemctl enable --now esphomedashboard &> /dev/null
    msg_ok "Installed ESPHome Beta"
  fi

  prompt=""
  read -rp "Would you like to install Matter-Server (Beta)? <y/N> " prompt || true
  if [[ "${prompt,,}" =~ ^(y|yes)$ ]]; then
    msg_info "Installing Matter Server"
    $STD apt install -y \
      libcairo2-dev \
      libjpeg62-turbo-dev \
      libgirepository1.0-dev \
      libpango1.0-dev \
      libgif-dev \
      g++
    $STD python3 -m pip install wheel
    $STD pip3 install --upgrade pip
    $STD pip install "python-matter-server[server]"
    msg_ok "Installed Matter Server"
    echo -e "${TAB}Start server > python -m matter_server.server"
  fi
}

function post_install_script() {
  echo ""
  msg_ok "${APP} installed successfully"
  echo -e "${INFO}${YW}Python:${CL} ${GN}$(pyenv version-name 2> /dev/null || echo "${var_addon_python_series}")${CL} ${YW}in${CL} ${var_addon_pyenv_root}"
  if [[ -f /etc/systemd/system/homeassistant.service ]]; then
    echo -e "${INFO}${YW}Home Assistant:${CL} ${BGN}http://${LOCAL_IP}:8123${CL} ${YW}(start with: systemctl start homeassistant)${CL}"
  fi
  if [[ -f /etc/systemd/system/esphomedashboard.service ]]; then
    echo -e "${INFO}${YW}ESPHome Dashboard:${CL} ${BGN}http://${LOCAL_IP}:6052${CL}"
  fi
  echo -e "${INFO}${YW}Restart your shell (or run 'exec \$SHELL') to activate pyenv${CL}"
  echo -e "${INFO}${YW}Update:${CL} update-${APP_SLUG}   ${YW}Uninstall:${CL} uninstall-${APP_SLUG}"
}

function update_script() {
  msg_info "Updating ${APP}"
  export PYENV_ROOT="$var_addon_pyenv_root"
  export PATH="${PYENV_ROOT}/bin:${PATH}"
  if pyenv commands 2> /dev/null | grep -qx "update"; then
    # pyenv-update plugin (installed by pyenv.run) - updates pyenv + all plugins
    $STD pyenv update
  else
    # Fallback for installs without the plugin: plain git pulls
    $STD git -C "$PYENV_ROOT" pull --ff-only
    local plugin
    for plugin in "${PYENV_ROOT}"/plugins/*/; do
      if [[ -d "${plugin}.git" ]]; then
        $STD git -C "$plugin" pull --ff-only
      fi
    done
  fi
  msg_ok "Updated successfully!"
  exit
}

function uninstall_script() {
  msg_info "Uninstalling ${APP}"
  rm -rf "$var_addon_pyenv_root"
  local rc
  for rc in "${HOME}/.bashrc" "${HOME}/.profile"; do
    [[ -f "$rc" ]] || continue
    sed -i '/^# pyenv$/,/^eval "$(pyenv init - bash)"$/d' "$rc"
  done
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
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/addon_lxc")
