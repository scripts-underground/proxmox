#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2026 scripts-underground.org
# Author: Alex Indigo (alexindigo)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/alexindigo/kosmozoo

# shellcheck disable=SC2034
APP="Kosmozoo"
var_tags="${var_tags:-comfyui;review;curation}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_lxc_git_repo="${var_lxc_git_repo:-alexindigo/kosmozoo}"
var_lxc_git_branch="${var_lxc_git_branch:-main}"
var_lxc_git_tag="${var_lxc_git_tag:-}"
var_lxc_pinned_commit="${var_lxc_pinned_commit:-}"
var_lxc_comfyui_hosts="${var_lxc_comfyui_hosts:-}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y git curl
  msg_ok "Installed Dependencies"

  msg_info "Cloning Kosmozoo"
  clone_and_deploy_gh_commit "kosmozoo" "$var_lxc_git_repo" "$var_lxc_git_branch" "$var_lxc_git_tag" "$var_lxc_pinned_commit" /opt/kosmozoo
  msg_ok "Cloned Kosmozoo"

  msg_info "Creating Data Directories"
  mkdir -p /opt/kosmozoo/data /opt/kosmozoo/downloads
  msg_ok "Created Data Directories"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/kosmozoo.service
[Unit]
Description=Kosmozoo Review Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/kosmozoo
Environment=KOZMOZOO_BIND=0.0.0.0
Environment=KOZMOZOO_PORT=80
Environment=KOZMOZOO_FEEDBACK=/opt/kosmozoo/data/feedback.json
Environment=KOZMOZOO_DOWNLOADS=/opt/kosmozoo/downloads
Environment=KOZMOZOO_HOSTS=${var_lxc_comfyui_hosts}
ExecStart=/usr/bin/python3 /opt/kosmozoo/server.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now kosmozoo
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
  echo -e "${INFO}${YW}Point it at your ComfyUI hosts with var_lxc_comfyui_hosts=\"studio=comfyui.lan:8188,gpu2=192.168.1.5:8188\"${CL}"
  echo -e "${INFO}${YW}No authentication by design — trusted LAN only.${CL}"
}

function update_script() {
  render_header
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/kosmozoo ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  local TRACK_FILE="$HOME/.kosmozoo"
  local CURRENT_MODE="" CURRENT_REF=""
  if [[ -f "$TRACK_FILE" ]]; then
    IFS=: read -r CURRENT_MODE CURRENT_REF < "$TRACK_FILE"
  fi

  cd /opt/kosmozoo || exit
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
        msg_ok "Kosmozoo is at ${DESIRED_MODE} ${DESIRED_REF} — no update needed"
        exit
        ;;
      branch)
        LOCAL=$(git rev-parse HEAD)
        REMOTE=$(git rev-parse "origin/$DESIRED_REF")
        if [[ "$LOCAL" == "$REMOTE" ]]; then
          msg_ok "Kosmozoo is up to date — no update needed"
          exit
        fi
        ;;
    esac
  fi

  msg_info "Updating Kosmozoo"
  systemctl stop kosmozoo
  git_update_checkout /opt/kosmozoo "$DESIRED_MODE" "$DESIRED_REF"
  echo "${DESIRED_MODE}:${DESIRED_REF}" > "$TRACK_FILE"
  systemctl start kosmozoo
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
