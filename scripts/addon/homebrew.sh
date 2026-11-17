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

  local prefix="${var_addon_brew_home}/.linuxbrew"
  if [[ -e "$prefix" || -L "$prefix" || -e "$var_addon_profile_d" || -L "$var_addon_profile_d" ]]; then
    msg_error "Homebrew prefix or profile is already occupied; preserve it and use explicit adoption."
    return 65
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
  mkdir -p "$prefix"
  chown "$BREW_USER:$var_addon_brew_group" "$prefix"
  chmod 2775 "$prefix"
  usermod -aG "$var_addon_brew_group" "$BREW_USER"
  msg_ok "Set Up Homebrew Prefix"

  msg_info "Installing Homebrew"
  local installer installer_status install_command
  installer=$(mktemp "${TMPDIR:-/tmp}/homebrew-installer.XXXXXXXX")
  if curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$installer"; then
    if [[ ! -s "$installer" ]]; then
      rm -f -- "$installer"
      msg_error "Homebrew installer is empty"
      return 251
    fi
  else
    installer_status=$?
    rm -f -- "$installer"
    return "$installer_status"
  fi
  if bash -n "$installer"; then :; else
    installer_status=$?
    rm -f -- "$installer"
    return "$installer_status"
  fi
  printf -v install_command 'NONINTERACTIVE=1 /bin/bash -s -- --path=%q' "$prefix"
  # The root-owned private stage is read by this shell, never exposed to the
  # target account. su passes the completed bytes on stdin to upstream Bash.
  if $STD su -s /bin/bash - "$BREW_USER" -c "$install_command" < "$installer"; then
    rm -f -- "$installer"
  else
    installer_status=$?
    rm -f -- "$installer"
    return "$installer_status"
  fi
  msg_ok "Installed Homebrew"

  msg_info "Configuring Shell Integration"
  mkdir -p "$(dirname "$var_addon_profile_d")"
  cat << EOF > "$var_addon_profile_d"
#!/bin/bash
if [ -d "${var_addon_brew_home}/.linuxbrew" ]; then
    eval "\$("${prefix}/bin/brew" shellenv)"
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
  local verify_command
  printf -v verify_command '%q --version' "${prefix}/bin/brew"
  $STD su -s /bin/bash - "$BREW_USER" -c "$verify_command"
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
  local prefix="${var_addon_brew_home}/.linuxbrew"
  if [[ ! -x "${prefix}/bin/brew" ]]; then
    msg_error "No ${APP} installation found!"
    return 233
  fi

  # The installed prefix records the chosen account through its ownership,
  # including legacy installs; account-list order is not installation identity.
  local owner record
  owner=$(stat -c %u "$prefix")
  if record=$(getent passwd "$owner"); then :; else
    msg_error "The Homebrew prefix owner no longer has a login account"
    return 254
  fi
  IFS=: read -r BREW_USER _ <<< "$record"
  if [[ -z "$BREW_USER" || "$owner" == 0 ]]; then
    msg_error "No non-root Homebrew prefix owner found"
    return 254
  fi
  msg_ok "Detected User: $BREW_USER"

  msg_info "Updating ${APP}"
  local update_command
  printf -v update_command '%q update' "${prefix}/bin/brew"
  $STD su -s /bin/bash - "$BREW_USER" -c "$update_command"
  msg_ok "Updated successfully!"
  exit
}

function uninstall_script() {
  msg_info "Uninstalling ${APP}"

  local prefix="${var_addon_brew_home}/.linuxbrew" owner record
  if [[ ! -x "${prefix}/bin/brew" ]]; then
    msg_error "No ${APP} installation found!"
    return 233
  fi
  owner=$(stat -c %u "$prefix")
  if record=$(getent passwd "$owner"); then :; else
    msg_error "The Homebrew prefix owner no longer has a login account"
    return 254
  fi
  IFS=: read -r BREW_USER _ _ _ _ BREW_USER_HOME _ <<< "$record"
  if [[ -z "$BREW_USER" || "$owner" == 0 || "$BREW_USER_HOME" != /* ]]; then
    msg_error "No non-root Homebrew prefix owner home found"
    return 254
  fi
  local rc_file
  for rc_file in "$BREW_USER_HOME/.bashrc" "$BREW_USER_HOME/.profile"; do
    if [[ -f "$rc_file" ]]; then
      sed -i '/# Homebrew (Linuxbrew)/,/^fi$/d' "$rc_file"
    fi
  done

  rm -rf "$prefix"
  rm -f "$var_addon_profile_d"

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
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/addon_lxc") --script-id homebrew -- "$@"
