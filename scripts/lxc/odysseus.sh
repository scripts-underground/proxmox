#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2026 scripts-underground.org
# Author: Alex Indigo (alexindigo)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/odysseus-dev/odysseus | https://odysseus-dev.github.io/odysseus/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Odysseus"
var_tags="${var_tags:-ai;workspace;llm}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"
var_lxc_git_repo="${var_lxc_git_repo:-odysseus-dev/odysseus}"
var_lxc_git_branch="${var_lxc_git_branch:-main}"
var_lxc_git_tag="${var_lxc_git_tag:-}"
var_lxc_pinned_commit="${var_lxc_pinned_commit:-93107c5}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    build-essential \
    cmake \
    git \
    nodejs \
    npm \
    chromium \
    tmux \
    libgl1 \
    libglib2.0-0t64 \
    libxcb1 \
    libmagic1
  msg_ok "Installed Dependencies"

  PYTHON_VERSION="3.12" setup_uv

  msg_info "Cloning Odysseus"
  clone_and_deploy_gh_commit "odysseus" "$var_lxc_git_repo" "$var_lxc_git_branch" "$var_lxc_git_tag" "$var_lxc_pinned_commit" /opt/odysseus
  msg_ok "Cloned Odysseus"

  msg_info "Setting up Python Environment"
  cd /opt/odysseus || exit
  $STD uv venv /opt/odysseus/venv
  $STD uv pip install -r /opt/odysseus/requirements.txt --python=/opt/odysseus/venv/bin/python
  $STD uv pip install python-magic --python=/opt/odysseus/venv/bin/python
  msg_ok "Set up Python Environment"

  msg_info "Creating Directories"
  mkdir -p /opt/odysseus/data
  mkdir -p /opt/odysseus/logs
  msg_ok "Created Directories"

  msg_info "Running Setup"
  cd /opt/odysseus || exit
  ADMIN_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
  export ODYSSEUS_ADMIN_USER="admin"
  export ODYSSEUS_ADMIN_PASSWORD="$ADMIN_PASS"
  /opt/odysseus/venv/bin/python /opt/odysseus/setup.py
  msg_ok "Setup Complete"
  echo -e "${INFO}${YW} Admin Username: admin${CL}"
  echo -e "${INFO}${YW} Admin Password: ${ADMIN_PASS}${CL}"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/odysseus.service
[Unit]
Description=Odysseus AI Workspace
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/odysseus
Environment=PATH=/opt/odysseus/.local/bin:/opt/odysseus/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=/opt/odysseus/venv/bin/uvicorn app:app --host 0.0.0.0 --port 80
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now odysseus
  msg_ok "Created Service"

}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
}

function update_script() {
  render_header

  if [[ ! -d /opt/odysseus ]]; then
    msg_error "No Odysseus Installation Found!"
    exit
  fi

  local TRACK_FILE="$HOME/.odysseus"
  local CURRENT_MODE="" CURRENT_REF=""
  if [[ -f "$TRACK_FILE" ]]; then
    IFS=: read -r CURRENT_MODE CURRENT_REF < "$TRACK_FILE"
  fi

  cd /opt/odysseus || exit
  $STD git fetch origin --tags

  local DESIRED_MODE="$CURRENT_MODE" DESIRED_REF="$CURRENT_REF"
  if [[ -n "${var_lxc_pinned_commit:-}" ]]; then
    DESIRED_MODE="commit" DESIRED_REF="$var_lxc_pinned_commit"
  elif [[ -n "${var_lxc_git_tag:-}" ]]; then
    DESIRED_MODE="tag" DESIRED_REF="$var_lxc_git_tag"
  elif [[ -n "${var_lxc_git_branch:-}" ]]; then
    DESIRED_MODE="branch" DESIRED_REF="$var_lxc_git_branch"
  fi

  if [[ -z "$DESIRED_MODE" ]]; then
    msg_ok "No update mode configured — exiting"
    exit
  fi

  if [[ "$CURRENT_MODE" == "$DESIRED_MODE" && "$CURRENT_REF" == "$DESIRED_REF" ]]; then
    case "$DESIRED_MODE" in
      commit | tag)
        msg_ok "Odysseus is at ${DESIRED_MODE} ${DESIRED_REF} — no update needed"
        exit
        ;;
      branch)
        LOCAL=$(git rev-parse HEAD)
        REMOTE=$(git rev-parse "origin/$DESIRED_REF")
        if [[ "$LOCAL" == "$REMOTE" ]]; then
          msg_ok "Odysseus is up to date — no update needed"
          exit
        fi
        ;;
    esac
  fi

  msg_info "Updating Odysseus"
  PYTHON_VERSION="3.12" setup_uv
  msg_info "Stopping Service"
  systemctl stop odysseus
  msg_ok "Stopped Service"

  case "$DESIRED_MODE" in
    commit)
      $STD git checkout "$DESIRED_REF"
      ;;
    tag)
      $STD git checkout "tags/$DESIRED_REF"
      ;;
    branch)
      $STD git pull origin "$DESIRED_REF"
      ;;
  esac
  echo "${DESIRED_MODE}:${DESIRED_REF}" > "$TRACK_FILE"

  $STD uv pip install -r /opt/odysseus/requirements.txt --python=/opt/odysseus/venv/bin/python --upgrade
  $STD /opt/odysseus/venv/bin/python /opt/odysseus/setup.py

  msg_info "Starting Service"
  systemctl start odysseus
  msg_ok "Started Service"
  msg_ok "Updated to ${DESIRED_MODE} ${DESIRED_REF}!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
