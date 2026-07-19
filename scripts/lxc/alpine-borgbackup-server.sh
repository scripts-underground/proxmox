#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Sander Koenders (sanderkoenders)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.borgbackup.org/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Alpine-BorgBackup-Server"
var_tags="${var_tags:-alpine;backup}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-20}"
var_os="${var_os:-alpine}"
var_version="${var_version:-3.23}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing BorgBackup"
  $STD apk add --no-cache borgbackup openssh
  $STD rc-update add sshd
  $STD rc-service sshd start
  msg_ok "Installed BorgBackup"

  msg_info "Creating backup user"
  $STD adduser -D -s /bin/bash -h /home/backup backup
  $STD passwd -d backup
  msg_ok "Created backup user"

  msg_info "Configure SSH, disabling password authentication and enabling public key authentication"
  $STD sed -i -e 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
  $STD rc-service sshd restart
  msg_ok "Configured SSH"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Connection information:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}ssh backup@${IP}${CL}"
  echo -e "${TAB}${VERIFYPW}${YW} To set SSH key, run the update option and select option 2${CL}"
}

function update_script() {
  header_info
  if [[ ! -f /usr/bin/borg ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  CHOICE=$(msg_menu "BorgBackup Server Update Options" \
    "1" "Update BorgBackup Server" \
    "2" "Reset SSH Access" \
    "3" "Enable password authentication for backup user (not recommended, use SSH key instead)" \
    "4" "Disable password authentication for backup user (recommended for security, use SSH key)")

  case $CHOICE in
    1)
      msg_info "Updating $APP LXC"
      $STD apk -U upgrade
      msg_ok "Updated $APP LXC successfully!"
      ;;
    2)
      if [[ "${PHS_SILENT:-0}" == "1" ]]; then
        msg_warn "Reset SSH Public key requires interactive mode, skipping."
        exit
      fi
      msg_info "Setting up SSH Public Key for backup user"
      msg_info "Please paste your SSH public key (e.g., ssh-rsa AAAAB3... user@host): \n"
      read -p "Key: " SSH_PUBLIC_KEY
      echo
      if [[ -z "$SSH_PUBLIC_KEY" ]]; then
        msg_error "No SSH public key provided!"
        exit 1
      fi
      if [[ ! "$SSH_PUBLIC_KEY" =~ ^(ssh-rsa|ssh-dss|ssh-ed25519|ecdsa-sha2-) ]]; then
        msg_error "Invalid SSH public key format!"
        exit 1
      fi
      msg_info "Setting up SSH access"
      mkdir -p /home/backup/.ssh
      echo "$SSH_PUBLIC_KEY" > /home/backup/.ssh/authorized_keys
      chown -R backup:backup /home/backup/.ssh
      chmod 700 /home/backup/.ssh
      chmod 600 /home/backup/.ssh/authorized_keys
      msg_ok "SSH access configured for backup user"
      ;;
    3)
      if [[ "${PHS_SILENT:-0}" == "1" ]]; then
        msg_warn "Enabling password authentication requires interactive mode, skipping."
        exit
      fi
      msg_info "Enabling password authentication for backup user"
      msg_warn "Password authentication is less secure than using SSH keys. Consider using SSH keys instead."
      passwd backup
      sed -i 's/^#*\s*PasswordAuthentication\s\+\(yes\|no\)/PasswordAuthentication yes/' /etc/ssh/sshd_config
      rc-service sshd restart
      msg_ok "Password authentication enabled for backup user"
      ;;
    4)
      msg_info "Disabling password authentication for backup user"
      sed -i 's/^#*\s*PasswordAuthentication\s\+\(yes\|no\)/PasswordAuthentication no/' /etc/ssh/sshd_config
      rc-service sshd restart
      msg_ok "Password authentication disabled for backup user"
      ;;
  esac
  exit 0
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
