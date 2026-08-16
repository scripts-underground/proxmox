#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MorganCSIT | MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://brew.sh | Github: https://github.com/Homebrew/brew

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="homebrew"

# Bundle-consumed configuration (var_addon_* is baked into update/uninstall
# bundles at install time — hooks may reference these directly)
var_addon_brew_home="${var_addon_brew_home:-/home/linuxbrew}"
var_addon_brew_group="${var_addon_brew_group:-linuxbrew}"
var_addon_profile_d="${var_addon_profile_d:-/etc/profile.d/homebrew.sh}"

function install_script() {
  if [[ "$OS_FAMILY" != "debian" ]]; then
    msg_error "Unsupported OS: ${OS_TYPE} (Debian/Ubuntu only)"
    exit 1
  fi

  msg_info "Detecting Non-Root User"
  BREW_USER=$(awk -F: '$3 >= 1000 && $3 < 65534 { print $1; exit }' /etc/passwd)
  if [[ -z "$BREW_USER" ]]; then
    msg_warn "No non-root user found (uid >= 1000). Homebrew cannot run as root."
    read -erp "${TAB}Create a 'brew' user automatically? (y/N): " create_user_prompt || true
    create_user_prompt="${create_user_prompt:-n}"
    if [[ "${create_user_prompt,,}" =~ ^(y|yes)$ ]]; then
      msg_info "Creating user 'brew'"
      useradd -m -s /bin/bash brew
      BREW_USER="brew"
      msg_ok "Created user 'brew'"
    else
      msg_error "Cannot install Homebrew without a non-root user. Exiting."
      exit 254
    fi
  fi
  msg_ok "Detected User: $BREW_USER"

  msg_info "Installing Dependencies"
  $STD apt update
  $STD apt install -y build-essential git file procps
  msg_ok "Installed Dependencies"

  msg_info "Setting Up Homebrew Prefix"
  export PATH="/usr/sbin:$PATH"
  groupadd -f "$var_addon_brew_group"
  mkdir -p "${var_addon_brew_home}/.linuxbrew"
  chown -R "$BREW_USER:$var_addon_brew_group" "$var_addon_brew_home"
  chmod 2775 "$var_addon_brew_home"
  chmod 2775 "${var_addon_brew_home}/.linuxbrew"
  usermod -aG "$var_addon_brew_group" "$BREW_USER"
  msg_ok "Set Up Homebrew Prefix"

  msg_info "Installing Homebrew"
  $STD su - "$BREW_USER" -c 'NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
  msg_ok "Installed Homebrew"

  msg_info "Configuring Shell Integration"
  cat << EOF > "$var_addon_profile_d"
#!/bin/bash
if [ -d "${var_addon_brew_home}/.linuxbrew" ]; then
    eval "\$(${var_addon_brew_home}/.linuxbrew/bin/brew shellenv)"
fi
EOF
  chmod +x "$var_addon_profile_d"

  BREW_USER_HOME=$(getent passwd "$BREW_USER" | cut -d: -f6)
  BREW_SHELL_BLOCK="\n# Homebrew (Linuxbrew)\nif [ -d \"${var_addon_brew_home}/.linuxbrew\" ]; then\n    eval \"\$(${var_addon_brew_home}/.linuxbrew/bin/brew shellenv)\"\nfi"
  for rc_file in "$BREW_USER_HOME/.bashrc" "$BREW_USER_HOME/.profile"; do
    if ! grep -q 'linuxbrew' "$rc_file" 2> /dev/null; then
      echo -e "$BREW_SHELL_BLOCK" >> "$rc_file"
    fi
  done
  msg_ok "Configured Shell Integration"

  msg_info "Verifying Installation"
  $STD su - "$BREW_USER" -c "eval \"\$(${var_addon_brew_home}/.linuxbrew/bin/brew shellenv)\" && brew --version"
  msg_ok "Homebrew Verified"
}

function post_install_script() {
  echo ""
  msg_ok "${APP} installed successfully"
  msg_ok "Ready for user: ${BL}${BREW_USER}${CL}"
  echo ""
  echo -e "${TAB}${INFO} Usage: Switch to the brew user with a login shell:"
  echo -e "${TAB}  ${BL}su - ${BREW_USER}${CL}"
  echo -e "${TAB}  Then run: ${BL}brew install <package>${CL}"
  echo -e "${INFO}${YW}Update:${CL} update-${APP_SLUG}   ${YW}Uninstall:${CL} uninstall-${APP_SLUG}"
}

function update_script() {
  if [[ ! -d "${var_addon_brew_home}/.linuxbrew" ]]; then
    msg_error "No ${APP} installation found!"
    exit
  fi

  msg_info "Detecting Non-Root User"
  BREW_USER=$(awk -F: '$3 >= 1000 && $3 < 65534 { print $1; exit }' /etc/passwd)
  if [[ -z "$BREW_USER" ]]; then
    msg_error "No non-root user found (uid >= 1000) — cannot update ${APP}"
    exit
  fi
  msg_ok "Detected User: $BREW_USER"

  msg_info "Updating ${APP}"
  $STD su - "$BREW_USER" -c "eval \"\$(${var_addon_brew_home}/.linuxbrew/bin/brew shellenv)\" && brew update"
  msg_ok "Updated successfully!"
  exit
}

function uninstall_script() {
  msg_info "Uninstalling ${APP}"

  BREW_USER=$(awk -F: '$3 >= 1000 && $3 < 65534 { print $1; exit }' /etc/passwd)
  if [[ -n "$BREW_USER" ]]; then
    BREW_USER_HOME=$(getent passwd "$BREW_USER" | cut -d: -f6)
    for rc_file in "$BREW_USER_HOME/.bashrc" "$BREW_USER_HOME/.profile"; do
      if [[ -f "$rc_file" ]]; then
        sed -i '/# Homebrew (Linuxbrew)/,/^fi$/d' "$rc_file"
      fi
    done
  fi

  rm -rf "$var_addon_brew_home"
  rm -f "$var_addon_profile_d"
  groupdel "$var_addon_brew_group" &> /dev/null || true

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
