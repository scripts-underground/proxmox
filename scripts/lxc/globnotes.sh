#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2026 scripts-underground.org
# Author: Alex Indigo (alexindigo)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/alexindigo/globnotes

# shellcheck disable=SC2034
APP="Globnotes"
var_tags="${var_tags:-notes;markdown}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_lxc_git_repo="${var_lxc_git_repo:-alexindigo/globnotes}"
var_lxc_git_branch="${var_lxc_git_branch:-main}"
var_lxc_git_tag="${var_lxc_git_tag:-}"
var_lxc_pinned_commit="${var_lxc_pinned_commit:-}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y git curl
  msg_ok "Installed Dependencies"

  NODE_VERSION="24" setup_nodejs
  PYTHON_VERSION="3.13" setup_uv

  msg_info "Cloning Globnotes"
  clone_and_deploy_gh_commit "globnotes" "$var_lxc_git_repo" "main" "${var_lxc_git_tag:-}" "${var_lxc_pinned_commit:-}" /opt/globnotes
  msg_ok "Cloned Globnotes"

  msg_info "Building Frontend"
  cd /opt/globnotes || exit
  $STD npm ci
  $STD npm run build
  msg_ok "Built Frontend"

  msg_info "Installing Python Dependencies"
  $STD uv sync --locked --no-dev
  msg_ok "Installed Python Dependencies"

  msg_info "Creating Data Directory"
  mkdir -p /opt/globnotes/data
  msg_ok "Created Data Directory"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/globnotes.service
[Unit]
Description=GlobNotes
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/globnotes
Environment=GLOBNOTES_PATH=/opt/globnotes/data
ExecStart=/opt/globnotes/.venv/bin/uvicorn main:app --app-dir /opt/globnotes/server --host 0.0.0.0 --port 80 --proxy-headers --forwarded-allow-ips '*'
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now globnotes
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
  echo -e "${INFO}${YW}Complete the first-run setup wizard to create a password (or disable auth).${CL}"
  echo -e "${INFO}${YW}Place your markdown notes in /opt/globnotes/data/ or mount your Obsidian vault there.${CL}"
}

function update_script() {
  render_header
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/globnotes ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  cd /opt/globnotes || exit
  $STD git fetch origin --tags

  local TRACK_FILE="$HOME/.globnotes"
  local CURRENT_MODE="" CURRENT_REF=""
  if [[ -f "$TRACK_FILE" ]]; then
    IFS=: read -r CURRENT_MODE CURRENT_REF < "$TRACK_FILE"
  fi

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
        msg_ok "Globnotes is at ${DESIRED_MODE} ${DESIRED_REF} — no update needed"
        exit
        ;;
      branch)
        LOCAL=$(git rev-parse HEAD)
        REMOTE=$(git rev-parse "origin/$DESIRED_REF")
        if [[ "$LOCAL" == "$REMOTE" ]]; then
          msg_ok "Globnotes is up to date — no update needed"
          exit
        fi
        ;;
    esac
  fi

  msg_info "Updating Globnotes"
  systemctl stop globnotes

  NODE_VERSION="24" setup_nodejs
  PYTHON_VERSION="3.13" setup_uv

  # setup_nodejs leaves CWD in /opt — return to the app dir before building
  cd /opt/globnotes || exit
  git_update_checkout /opt/globnotes "$DESIRED_MODE" "$DESIRED_REF"
  echo "${DESIRED_MODE}:${DESIRED_REF}" > "$TRACK_FILE"
  $STD npm ci
  $STD npm run build
  $STD uv sync --locked --no-dev

  systemctl start globnotes
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
