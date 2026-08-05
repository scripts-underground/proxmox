#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2026 scripts-underground.org
# Author: Alex Indigo (alexindigo)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/zas/mcp-musicbrainz

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="MusicBrainz MCP"
var_tags="${var_tags:-music;mcp}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_hostname="${var_hostname:-musicbrainz}"
var_git_repo="${var_git_repo:-zas/mcp-musicbrainz}"
var_git_branch="${var_git_branch:-main}"
var_git_tag="${var_git_tag:-}"
var_pinned_commit="${var_pinned_commit:-370310a}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y git curl
  msg_ok "Installed Dependencies"

  # uv-managed Python lands in /usr/local/bin so the unprivileged
  # service user can execute the venv interpreter (default is ~/.local)
  UV_PYTHON_INSTALL_DIR="/usr/local/bin" PYTHON_VERSION="3.12" setup_uv

  msg_info "Cloning MusicBrainz MCP Server"
  # Inline defaults: the install bundle runs with `set -u` and only receives
  # user-exported var_* via lxc-attach env passthrough (top-level assignments
  # are not propagated), so unguarded references would abort the install
  clone_and_deploy_gh_commit "musicbrainz" "${var_git_repo:-zas/mcp-musicbrainz}" "${var_git_branch:-main}" "${var_git_tag:-}" "${var_pinned_commit:-370310a}" /opt/mcp-musicbrainz
  msg_ok "Cloned MusicBrainz MCP Server"

  msg_info "Installing Python Dependencies"
  export UV_PYTHON_INSTALL_DIR="/usr/local/bin"
  cd /opt/mcp-musicbrainz || exit
  $STD uv sync --locked
  msg_ok "Installed Python Dependencies"

  msg_info "Creating Service User"
  useradd --system --no-create-home --shell /usr/sbin/nologin mcp
  # diskcache writes here relative to the service WorkingDirectory;
  # /opt/mcp-musicbrainz stays root-owned, only the cache is writable
  mkdir -p /opt/mcp-musicbrainz/.musicbrainz_cache
  chown -R mcp:mcp /opt/mcp-musicbrainz/.musicbrainz_cache
  msg_ok "Created Service User"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/musicbrainz.service
[Unit]
Description=MusicBrainz MCP Server
After=network.target

[Service]
Type=simple
User=mcp
WorkingDirectory=/opt/mcp-musicbrainz
Environment=MCP_MUSICBRAINZ_HTTP_HOST=0.0.0.0
Environment=MCP_MUSICBRAINZ_HTTP_PORT=8000
ExecStart=/opt/mcp-musicbrainz/.venv/bin/mcp-musicbrainz-sse
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now musicbrainz
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}The MCP endpoint (streamable HTTP) is available at:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8000/mcp${CL}"
}

function update_script() {
  render_header

  if [[ ! -d /opt/mcp-musicbrainz ]]; then
    msg_error "No MusicBrainz MCP Installation Found!"
    exit
  fi

  local TRACK_FILE="$HOME/.musicbrainz"
  local CURRENT_MODE="" CURRENT_REF=""
  if [[ -f "$TRACK_FILE" ]]; then
    IFS=: read -r CURRENT_MODE CURRENT_REF < "$TRACK_FILE"
  fi

  cd /opt/mcp-musicbrainz || exit
  $STD git fetch origin --tags

  local DESIRED_MODE="$CURRENT_MODE" DESIRED_REF="$CURRENT_REF"
  if [[ -n "${var_pinned_commit:-}" ]]; then
    DESIRED_MODE="commit" DESIRED_REF="$var_pinned_commit"
  elif [[ -n "${var_git_tag:-}" ]]; then
    DESIRED_MODE="tag" DESIRED_REF="$var_git_tag"
  elif [[ -n "${var_git_branch:-}" ]]; then
    DESIRED_MODE="branch" DESIRED_REF="$var_git_branch"
  fi

  if [[ -z "$DESIRED_MODE" ]]; then
    msg_ok "No update mode configured — exiting"
    exit
  fi

  if [[ "$CURRENT_MODE" == "$DESIRED_MODE" && "$CURRENT_REF" == "$DESIRED_REF" ]]; then
    case "$DESIRED_MODE" in
      commit | tag)
        msg_ok "MusicBrainz MCP is at ${DESIRED_MODE} ${DESIRED_REF} — no update needed"
        exit
        ;;
      branch)
        LOCAL=$(git rev-parse HEAD)
        REMOTE=$(git rev-parse "origin/$DESIRED_REF")
        if [[ "$LOCAL" == "$REMOTE" ]]; then
          msg_ok "MusicBrainz MCP is up to date — no update needed"
          exit
        fi
        ;;
    esac
  fi

  msg_info "Updating MusicBrainz MCP"
  UV_PYTHON_INSTALL_DIR="/usr/local/bin" PYTHON_VERSION="3.12" setup_uv
  msg_info "Stopping Service"
  systemctl stop musicbrainz
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

  export UV_PYTHON_INSTALL_DIR="/usr/local/bin"
  $STD uv sync --locked

  msg_info "Starting Service"
  systemctl start musicbrainz
  msg_ok "Started Service"
  msg_ok "Updated to ${DESIRED_MODE} ${DESIRED_REF}!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
