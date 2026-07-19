#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: jdacode
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/comfyanonymous/ComfyUI

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="ComfyUI"
var_tags="${var_tags:-ai}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-25}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_gpu="${var_gpu:-yes}"

function install_script() {
  setup_hwaccel

  msg_info "GPU Selection"
  echo
  echo "Choose the GPU type for ComfyUI:"
  echo "[1]-None  [2]-NVIDIA  [3]-AMD  [4]-Intel"
  read -rp "Enter your choice [1-4] (default: 1): " gpu_choice
  gpu_choice=${gpu_choice:-1}
  case "$gpu_choice" in
    1) comfyui_gpu_type="none" ;;
    2) comfyui_gpu_type="nvidia" ;;
    3) comfyui_gpu_type="amd" ;;
    4) comfyui_gpu_type="intel" ;;
    *)
      comfyui_gpu_type="none"
      echo "Invalid choice. Defaulting to ${comfyui_gpu_type}."
      ;;
  esac
  msg_ok "GPU Selection done"

  PYTHON_VERSION="3.12" setup_uv

  fetch_and_deploy_gh_release "ComfyUI" "comfyanonymous/ComfyUI" "tarball" "latest" "/opt/ComfyUI"

  msg_info "Python Dependencies"
  $STD uv venv --clear "/opt/ComfyUI/venv"

  if [[ "${comfyui_gpu_type,,}" == "nvidia" ]]; then
    pytorch_url="https://download.pytorch.org/whl/cu130"
    if [[ -f "/opt/ComfyUI/README.md" ]]; then
      extracted=$(grep -oP 'pip install.*?--extra-index-url\s+\Khttps://download\.pytorch\.org/whl/cu\d+' /opt/ComfyUI/README.md | head -1 || true)
      [[ -n "$extracted" ]] && pytorch_url="$extracted"
    fi
    $STD uv pip install \
      torch \
      torchvision \
      torchaudio \
      --extra-index-url "$pytorch_url" \
      --python="/opt/ComfyUI/venv/bin/python"
  elif [[ "${comfyui_gpu_type,,}" == "amd" ]]; then
    pytorch_url="https://download.pytorch.org/whl/rocm6.4"
    if [[ -f "/opt/ComfyUI/README.md" ]]; then
      extracted=$(grep -oP 'pip install.*?--index-url\s+\Khttps://download\.pytorch\.org/whl/rocm[\d.]+' /opt/ComfyUI/README.md | grep -v 'nightly' | head -1 || true)
      [[ -n "$extracted" ]] && pytorch_url="$extracted"
    fi
    $STD uv pip install \
      torch \
      torchvision \
      torchaudio \
      --index-url "$pytorch_url" \
      --python="/opt/ComfyUI/venv/bin/python"
  elif [[ "${comfyui_gpu_type,,}" == "intel" ]]; then
    pytorch_url="https://download.pytorch.org/whl/xpu"
    if [[ -f "/opt/ComfyUI/README.md" ]]; then
      extracted=$(grep -oP 'pip install.*?--index-url\s+\Khttps://download\.pytorch\.org/whl/xpu' /opt/ComfyUI/README.md | head -1 || true)
      [[ -n "$extracted" ]] && pytorch_url="$extracted"
    fi
    $STD uv pip install \
      torch \
      torchvision \
      torchaudio \
      --index-url "$pytorch_url" \
      --python="/opt/ComfyUI/venv/bin/python"
  fi
  $STD uv pip install -r "/opt/ComfyUI/requirements.txt" --python="/opt/ComfyUI/venv/bin/python"
  msg_ok "Python Dependencies"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/comfyui.service
[Unit]
Description=ComfyUI Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/ComfyUI
ExecStart=/opt/ComfyUI/venv/bin/python /opt/ComfyUI/main.py --listen --port 8188
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now comfyui
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8188${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/ComfyUI ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_error "To update use the ComfyUI Manager."
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
