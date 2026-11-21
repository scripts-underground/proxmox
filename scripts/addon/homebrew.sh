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

  local prefix="${var_addon_brew_home}/.linuxbrew" prefix_parent prefix_default=/home/linuxbrew/.linuxbrew
  # Match upstream install.sh's Linux prefix admission before account, group or
  # prefix effects. Canonicalize only the existing ancestor, retaining the exact
  # not-yet-created suffix so invalid components are not normalized away.
  [[ "$prefix" == /* ]] || {
    msg_error "Homebrew prefix must be absolute: $prefix"
    return 65
  }
  prefix_parent=$prefix
  while [[ ! -e "$prefix_parent" ]]; do
    prefix_parent=${prefix_parent%/*}
    prefix_parent=${prefix_parent:-/}
  done
  prefix=$(cd -P -- "$prefix_parent" && printf '%s%s' "${PWD%/}" "${prefix#"${prefix_parent%/}"}") || return $?
  case "$prefix/" in
    / | /usr/ | *[[:space:]:]* | *//* | */./* | */../*)
      msg_error "Invalid Homebrew prefix: $prefix"
      return 65
      ;;
  esac
  if ! (
    LC_ALL=C
    [[ ${#prefix} -le ${#prefix_default} ]]
  ); then
    msg_error "Homebrew prefix is longer than /home/linuxbrew/.linuxbrew: $prefix"
    return 65
  fi
  if [[ -e "$prefix" || -L "$prefix" || -e "$var_addon_profile_d" || -L "$var_addon_profile_d" ]]; then
    msg_error "Homebrew prefix or profile is already occupied; preserve it and use explicit adoption."
    return 65
  fi

  local installer installer_status install_command installer_fd
  installer=$(mktemp "${TMPDIR:-/tmp}/homebrew-installer.XXXXXXXX") || return $?
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
  # Hold the checked bytes on a private read descriptor and retire the exact
  # stage before any account/package work can fail. The account receives stdin,
  # not pathname access; process exit closes the descriptor on failure.
  if exec {installer_fd}< "$installer"; then :; else
    installer_status=$?
    rm -f -- "$installer"
    return "$installer_status"
  fi
  rm -f -- "$installer" || return $?

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
  addon_install_begin "$prefix" homebrew
  chown "$BREW_USER:$var_addon_brew_group" "$prefix"
  chmod 2775 "$prefix"
  usermod -aG "$var_addon_brew_group" "$BREW_USER"
  msg_ok "Set Up Homebrew Prefix"

  msg_info "Installing Homebrew"
  printf -v install_command 'NONINTERACTIVE=1 /bin/bash -s -- --path=%q' "$prefix"
  # The root-owned private stage is read by this shell, never exposed to the
  # target account. su passes the completed bytes on stdin to upstream Bash.
  addon_install_expose "$prefix" homebrew "$BREW_USER"
  if $STD su -s /bin/bash - "$BREW_USER" -c "$install_command" <&"$installer_fd"; then
    exec {installer_fd}<&-
  else
    installer_status=$?
    exec {installer_fd}<&-
    return "$installer_status"
  fi
  msg_ok "Installed Homebrew"

  msg_info "Configuring Shell Integration"
  # .profile is POSIX shell, not Bash: single-quoted literal words preserve every
  # path byte without leaving future dollar/backtick/quote evaluation behind.
  local quoted_prefix quoted_brew shell_block profile_command
  quoted_prefix="'${prefix//\'/\'\\\'\'}'"
  quoted_brew="'${prefix//\'/\'\\\'\'}/bin/brew'"
  printf -v shell_block '# Homebrew (Linuxbrew)\nif [ -d %s ]; then\n    eval "$(%s shellenv)"\nfi\n' "$quoted_prefix" "$quoted_brew"
  mkdir -p "$(dirname "$var_addon_profile_d")"
  (
    set -o noclobber
    printf '#!/bin/bash\n%s' "$shell_block" > "$var_addon_profile_d"
  )
  chmod +x "$var_addon_profile_d"

  BREW_USER_HOME=$(getent passwd "$BREW_USER" | cut -d: -f6)
  [[ "$BREW_USER_HOME" == /* && "$BREW_USER_HOME" != / ]] || return 65
  printf -v profile_command '/bin/bash -s -- %q %q' "$BREW_USER_HOME" "$shell_block"
  # Never root-edit through account-owned profile links. The resolved account
  # validates its regular target, prepares a sibling and preserves the link.
  su -s /bin/bash "$BREW_USER" -c "$profile_command" << 'PROFILES'
set -euo pipefail
home=$1 block=$2
for rc_file in "$home/.bashrc" "$home/.profile"; do
  target=$rc_file content=''
  if [[ -e "$rc_file" || -L "$rc_file" ]]; then
    target=$(realpath -e -- "$rc_file")
    [[ -f "$target" && -r "$target" && -w "$target" && "$(stat -c %u -- "$target")" == "$(id -u)" && "$(stat -c %h -- "$target")" == 1 ]] || exit 65
    content=$(cat -- "$target" && printf .)
    content=${content%.}
  fi
  if [[ $'\n'"$content" == *$'\n# Homebrew (Linuxbrew)\n'* ]]; then
    [[ $'\n'"$content" == *$'\n'"$block"* ]] || printf 'Homebrew profile edited; manual cleanup: %s\n' "$rc_file" >&2
    continue
  fi
  stage=$(mktemp -- "$(dirname -- "$target")/.homebrew-profile.XXXXXXXX")
  status=0
  if [[ -e "$target" ]]; then chmod --reference="$target" -- "$stage" || status=$?; else chmod 0644 -- "$stage" || status=$?; fi
  if [[ "$status" == 0 ]]; then
    { printf '%s' "$content"; [[ -z "$content" || "$content" == *$'\n' ]] || printf '\n'; printf '%s' "$block"; } > "$stage" || status=$?
  fi
  if [[ "$status" == 0 ]]; then mv -T -- "$stage" "$target" || status=$?; fi
  rm -f -- "$stage"
  [[ "$status" == 0 ]] || exit "$status"
  done
PROFILES
  msg_ok "Configured Shell Integration"

  msg_info "Verifying Installation"
  local verify_command
  printf -v verify_command '%q --version' "${prefix}/bin/brew"
  $STD su -s /bin/bash - "$BREW_USER" -c "$verify_command"
  addon_install_complete "$prefix" homebrew
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
  prefix=$(realpath -m -- "$prefix") || return $?
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

  local prefix="${var_addon_brew_home}/.linuxbrew" owner record install_state
  prefix=$(realpath -m -- "$prefix") || return $?
  addon_install_status install_state "$prefix" homebrew || return $?
  if [[ "$install_state" != absent && ! -x "$prefix/bin/brew" ]]; then
    case "$install_state" in
      prepared | safe | cleaned)
        addon_install_cleanup "$prefix" homebrew || return $?
        msg_ok "${APP} incomplete installation cleanup completed"
        return 0
        ;;
    esac
    # The exposed attempt records the account even if brew was never produced.
    # Use it for exact profile cleanup too, including a removed brew after ready.
    addon_install_consumer_identity BREW_USER "$prefix" homebrew || return $?
    if record=$(getent passwd "$BREW_USER"); then :; else return 254; fi
    IFS=: read -r _ _ owner _ <<< "$record"
  elif [[ ! -x "${prefix}/bin/brew" ]]; then
    msg_error "No ${APP} installation found!"
    return 233
  else
    owner=$(stat -c %u "$prefix")
    if record=$(getent passwd "$owner"); then :; else
      msg_error "The Homebrew prefix owner no longer has a login account"
      return 254
    fi
  fi
  IFS=: read -r BREW_USER _ _ _ _ BREW_USER_HOME _ <<< "$record"
  if [[ -z "$BREW_USER" || "$owner" == 0 || "$BREW_USER_HOME" != /* ]]; then
    msg_error "No non-root Homebrew prefix owner home found"
    return 254
  fi
  local quoted_prefix quoted_brew shell_block legacy_block profile_command global_current global_legacy
  quoted_prefix="'${prefix//\'/\'\\\'\'}'"
  quoted_brew="'${prefix//\'/\'\\\'\'}/bin/brew'"
  printf -v shell_block '# Homebrew (Linuxbrew)\nif [ -d %s ]; then\n    eval "$(%s shellenv)"\nfi\n' "$quoted_prefix" "$quoted_brew"
  # Legacy text is compared only as data. Never evaluate its unquoted path.
  printf -v legacy_block '# Homebrew (Linuxbrew)\nif [ -d "%s" ]; then\n    eval "$(%s/bin/brew shellenv)"\nfi\n' "$prefix" "$prefix"
  printf -v profile_command '/bin/bash -s -- %q %q %q' "$BREW_USER_HOME" "$shell_block" "$legacy_block"
  su -s /bin/bash "$BREW_USER" -c "$profile_command" << 'PROFILES'
set -euo pipefail
home=$1 block=$2 legacy=$3
for rc_file in "$home/.bashrc" "$home/.profile"; do
  [[ -e "$rc_file" || -L "$rc_file" ]] || continue
  if ! target=$(realpath -e -- "$rc_file") || [[ ! -f "$target" || ! -r "$target" || ! -w "$target" || "$(stat -c %u -- "$target")" != "$(id -u)" || "$(stat -c %h -- "$target")" != 1 ]]; then
    printf 'Homebrew profile target retained; manual cleanup: %s\n' "$rc_file" >&2
    continue
  fi
  content=$(cat -- "$target" && printf .)
  content=${content%.}
  framed=$'\n'"$content"
  for exact in "$block" "$legacy"; do
    token=$'\n'"$exact"
    framed=${framed//"$token"/$'\n'}
  done
  remaining=${framed:1}
  if [[ $'\n'"$remaining" == *$'\n# Homebrew (Linuxbrew)\n'* ]]; then printf 'Homebrew profile edited; manual cleanup: %s\n' "$rc_file" >&2; fi
  [[ "$remaining" != "$content" ]] || continue
  stage=$(mktemp -- "$(dirname -- "$target")/.homebrew-profile.XXXXXXXX")
  status=0
  chmod --reference="$target" -- "$stage" || status=$?
  if [[ "$status" == 0 ]]; then printf '%s' "$remaining" > "$stage" || status=$?; fi
  if [[ "$status" == 0 ]]; then mv -T -- "$stage" "$target" || status=$?; fi
  rm -f -- "$stage"
  [[ "$status" == 0 ]] || exit "$status"
done
PROFILES

  printf -v global_current '#!/bin/bash\n%s' "$shell_block"
  printf -v global_legacy '#!/bin/bash\nif [ -d "%s" ]; then\n    eval "$("%s/bin/brew" shellenv)"\nfi\n' "$prefix" "$prefix"
  if [[ -e "$var_addon_profile_d" || -L "$var_addon_profile_d" ]]; then
    if [[ ! -L "$var_addon_profile_d" && -f "$var_addon_profile_d" ]] &&
      { cmp -s -- "$var_addon_profile_d" <(printf '%s' "$global_current") || cmp -s -- "$var_addon_profile_d" <(printf '%s' "$global_legacy"); }; then
      rm -f -- "$var_addon_profile_d"
    else msg_warn "Homebrew global profile retained; manual cleanup: $var_addon_profile_d"; fi
  fi

  if [[ "$install_state" == absent ]]; then
    rm -rf "$prefix"
  else
    # No daemon or external stack is owned by this local-file adapter. Profiles
    # are handled before safety/cleanup so an interruption cannot strand them.
    case "$install_state" in
      exposed | ready) addon_install_teardown_complete "$prefix" homebrew || return $? ;;
    esac
    addon_install_cleanup "$prefix" homebrew || return $?
  fi

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
