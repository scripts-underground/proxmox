#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 tteck
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.webmin.com/ | Github: https://github.com/webmin/webmin

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Webmin"

# Bundle-consumed configuration (var_addon_* is baked into update/uninstall
# bundles at install time — hooks may reference these directly)
var_addon_pkg="${var_addon_pkg:-webmin}"
var_addon_service="${var_addon_service:-webmin}"
var_addon_gh_repo="${var_addon_gh_repo:-webmin/webmin}"
var_addon_default_port="${var_addon_default_port:-10000}"

function install_script() {
  if [[ "$OS_FAMILY" != "debian" ]]; then
    msg_error "Unsupported OS: ${OS_TYPE} (Debian/Ubuntu only)"
    exit 1
  fi

  local listener_port
  if [[ ! "$var_addon_default_port" =~ ^0*([1-9][0-9]{0,4})$ ]] || ((10#${BASH_REMATCH[1]} > 65535)); then
    msg_error "Invalid Webmin listener port: ${var_addon_default_port}"
    return 65
  fi
  listener_port=${BASH_REMATCH[1]}

  msg_info "Installing Prerequisites"
  $STD apt update
  $STD apt install -y \
    libnet-ssleay-perl \
    libauthen-pam-perl \
    libio-pty-perl \
    unzip \
    shared-mime-info
  msg_ok "Installed Prerequisites"

  msg_info "Installing ${APP}"
  fetch_and_deploy_gh_release "$var_addon_pkg" "$var_addon_gh_repo" "binary" "latest" "/opt/webmin" "webmin_*_all.deb"
  /usr/share/webmin/changepass.pl /etc/webmin root root &> /dev/null
  # This transition owns only its candidate, not later operator edits. Keep the
  # full preimage on the same filesystem until the native restart has completed.
  local listener_config=/etc/webmin/miniserv.conf listener_stage listener_identity listener_state listener_status=0
  [[ -f "$listener_config" && ! -L "$listener_config" ]] || return 65
  listener_identity=$(stat -c '%d:%i:%u:%g:%a:%h' -- "$listener_config") || return $?
  [[ "${listener_identity##*:}" == 1 ]] || return 65
  listener_state=$(systemctl show --property=ActiveState --value "$var_addon_service") || return $?
  case "$listener_state" in active | activating | reloading | inactive | failed) ;; *) return 69 ;; esac
  listener_stage=$(mktemp -d /etc/webmin/.addon-listener.XXXXXXXX) || return $?
  cp -p -- "$listener_config" "$listener_stage/previous" || listener_status=$?
  if [[ "$listener_status" == 0 ]]; then cp -p -- "$listener_stage/previous" "$listener_stage/candidate" || listener_status=$?; fi
  if [[ "$listener_status" == 0 ]]; then
    # Match miniserv's reader: trim keys/values and use the last assignment.
    # Preserve all unrelated lines, and append using the existing newline style.
    perl - "$listener_stage/candidate" "$listener_port" << 'PERL' || listener_status=$?
use strict;
use warnings;
my ($file, $port) = @ARGV;
open my $input, '<', $file or die "$file: $!";
binmode $input;
my @lines = <$input>;
close $input or die "$file: $!";
my %effective;
for (@lines) {
  next if /^#/;
  if (/^([^=]+)=(.*?)[\r\n]*$/) {
    my ($key, $value) = ($1, $2);
    s/^\s+|\s+$//g for ($key, $value);
    $effective{$key} = $value;
  }
}
my $paired = defined($effective{port}) && length($effective{port}) &&
  defined($effective{listen}) && $effective{listen} eq $effective{port};
my $newline = grep(/\r\n$/, @lines) ? "\r\n" : "\n";
my $found = 0;
for (@lines) {
  if (/^\s*port\s*=/) {
    my $ending = /([\r\n]+)$/ ? $1 : '';
    $_ = "port=$port$ending";
    $found = 1;
  } elsif ($paired && /^\s*listen\s*=/) {
    my $ending = /([\r\n]+)$/ ? $1 : '';
    $_ = "listen=$port$ending";
  }
}
if (!$found) {
  push @lines, $newline if @lines && $lines[-1] !~ /[\r\n]$/;
  push @lines, "port=$port$newline";
}
open my $output, '>', $file or die "$file: $!";
binmode $output;
print {$output} @lines or die "$file: $!";
close $output or die "$file: $!";
PERL
  fi
  if [[ "$listener_status" == 0 ]]; then
    if [[ ! -L "$listener_config" && "$(stat -c '%d:%i:%u:%g:%a:%h' -- "$listener_config")" == "$listener_identity" ]] &&
      cmp -s -- "$listener_config" "$listener_stage/previous"; then
      cp -p -- "$listener_stage/candidate" "$listener_stage/expected" || listener_status=$?
      if [[ "$listener_status" == 0 ]]; then ln -- "$listener_stage/candidate" "$listener_stage/published" || listener_status=$?; fi
      if [[ "$listener_status" == 0 ]]; then mv -T -- "$listener_stage/candidate" "$listener_config" || listener_status=$?; fi
    else
      msg_error "Webmin configuration changed; recovery retained at ${listener_stage}"
      return 65
    fi
  fi
  if [[ "$listener_status" == 0 ]]; then
    systemctl restart "$var_addon_service" || listener_status=$?
    if [[ "$listener_status" != 0 ]]; then
      if [[ ! -L "$listener_config" && "$listener_config" -ef "$listener_stage/published" ]] &&
        cmp -s -- "$listener_config" "$listener_stage/expected" &&
        [[ "$(stat -c '%u:%g:%a' -- "$listener_config")" == "$(stat -c '%u:%g:%a' -- "$listener_stage/expected")" ]]; then
        if ! mv -T -- "$listener_stage/previous" "$listener_config"; then
          msg_error "Webmin rollback failed; recovery retained at ${listener_stage}"
          return "$listener_status"
        fi
        case "$listener_state" in active | activating | reloading)
          if ! systemctl restart "$var_addon_service"; then
            msg_error "Webmin prior listener recovery failed; recovery retained at ${listener_stage}"
            return "$listener_status"
          fi
          ;;
        esac
      else
        msg_error "Webmin configuration changed; recovery retained at ${listener_stage}"
        return "$listener_status"
      fi
    fi
  fi
  local listener_cleanup=0
  rm -f -- "$listener_stage/previous" "$listener_stage/candidate" "$listener_stage/expected" "$listener_stage/published" || listener_cleanup=$?
  if [[ "$listener_cleanup" == 0 ]]; then rmdir -- "$listener_stage" || listener_cleanup=$?; fi
  [[ "$listener_status" == 0 ]] || return "$listener_status"
  [[ "$listener_cleanup" == 0 ]] || return "$listener_cleanup"
  msg_ok "Installed ${APP}"
}

function post_install_script() {
  echo ""
  msg_ok "${APP} installed successfully"
  echo -e "${INFO}${YW}Web UI:${CL} ${BGN}https://${LOCAL_IP}:${var_addon_default_port}${CL}"
  echo -e "${INFO}${YW}Login:${CL} ${GN}root${CL} / ${GN}root${CL} (change via Webmin Configuration)"
  echo -e "${INFO}${YW}Update:${CL} update-${APP_SLUG}   ${YW}Uninstall:${CL} uninstall-${APP_SLUG}"
}

function update_script() {
  if check_for_gh_release "$var_addon_pkg" "$var_addon_gh_repo"; then
    msg_info "Updating ${APP}"
    fetch_and_deploy_gh_release "$var_addon_pkg" "$var_addon_gh_repo" "binary" "$CHECK_UPDATE_RELEASE" "/opt/webmin" "webmin_*_all.deb"
    systemctl restart "$var_addon_service"
    msg_ok "Updated successfully!"
  else
    local release_status=$?
    [[ "$release_status" == 1 ]] || return "$release_status"
  fi
  exit
}

function uninstall_script() {
  msg_info "Uninstalling ${APP}"
  svc_prepare_uninstall "$var_addon_service"
  $STD apt remove -y "$var_addon_pkg"
  rm -f "$HOME/.${var_addon_pkg}"
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
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/addon_lxc") --script-id webmin -- "$@"
