#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/ggml-org/llama.cpp

# shellcheck disable=SC2034
APP="llama.cpp"
var_hostname="${var_hostname:-llama-cpp}"
var_tags="${var_tags:-ai}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-16}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_gpu="${var_gpu:-yes}"
var_lxc_release="${var_lxc_release:-${var_appversion:-latest}}"
var_lxc_backend="${var_lxc_backend:-auto}"
var_lxc_models_max="${var_lxc_models_max:-4}"
var_lxc_port="${var_lxc_port:-80}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y libgomp1 zstd
  msg_ok "Installed Dependencies"

  if ! id llama-cpp > /dev/null 2>&1; then
    useradd --system --user-group --create-home --home-dir /var/lib/llama-cpp --shell /usr/sbin/nologin llama-cpp
  fi
  install -d -m 755 -o llama-cpp -g llama-cpp /var/lib/llama-cpp/models /var/cache/llama-cpp
  setup_hwaccel llama-cpp || return $?
  local backend=$var_lxc_backend arch
  case "$(get_system_arch)" in amd64) arch=x64 ;; arm64) arch=arm64 ;; *) return 65 ;; esac
  if [[ "$backend" == auto ]]; then
    case "${HWACCEL_VENDOR:-none}" in
      nvidia) [[ "$arch" == x64 ]] && backend=cuda || backend=vulkan ;;
      intel | amd) backend=vulkan ;;
      *) backend=cpu ;;
    esac
  fi
  case "$backend" in
    cpu) ;;
    vulkan) $STD apt install -y libvulkan1 mesa-vulkan-drivers vulkan-tools ;;
    cuda) [[ "$arch" == x64 ]] || return 65 ;;
    *)
      msg_error "Supported llama.cpp backends are auto, cpu, vulkan and cuda"
      return 65
      ;;
  esac
  _llama_cpp_deploy /opt/llama-cpp "$var_lxc_release" "$backend" "$arch" || return $?
  printf '%s\n' "$backend" > /var/lib/llama-cpp/.backend
  [[ "$var_lxc_models_max" =~ ^[0-9]+$ && "$var_lxc_port" =~ ^[0-9]+$ ]] || return 65

  msg_info "Configuring native model router"
  cat << EOF > /etc/llama-cpp.env
LLAMA_ARG_HOST=0.0.0.0
LLAMA_ARG_PORT=$var_lxc_port
LLAMA_ARG_MODELS_DIR=/var/lib/llama-cpp/models
LLAMA_CACHE=/var/cache/llama-cpp
LLAMA_ARG_MODELS_PRESET=/etc/llama-cpp-models.ini
LLAMA_ARG_MODELS_MAX=$var_lxc_models_max
LLAMA_ARG_MODELS_AUTOLOAD=true
# Set LLAMA_API_KEY or LLAMA_ARG_API_KEY_FILE here when needed.
# Native per-model context/offload/fit options belong in the presets file.
EOF
  printf 'version = 1\n' > /etc/llama-cpp-models.ini
  chmod 640 /etc/llama-cpp.env /etc/llama-cpp-models.ini
  chown root:llama-cpp /etc/llama-cpp.env /etc/llama-cpp-models.ini
  cat << 'EOF' > /etc/systemd/system/llama-cpp.service
[Unit]
Description=llama.cpp native model router
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=llama-cpp
Group=llama-cpp
WorkingDirectory=/opt/llama-cpp
EnvironmentFile=/etc/llama-cpp.env
Environment=LD_LIBRARY_PATH=/opt/llama-cpp
ExecStart=/opt/llama-cpp/llama-server
AmbientCapabilities=CAP_NET_BIND_SERVICE
Restart=on-failure
RestartSec=5
TimeoutStopSec=60

[Install]
WantedBy=multi-user.target
EOF
  ln -s /opt/llama-cpp/llama-server /usr/local/bin/llama-server
  systemctl daemon-reload
  systemctl enable --now llama-cpp
  msg_ok "Configured empty native model router"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Native UI and API: http://${IP}:${var_lxc_port}${CL}"
  echo -e "${INFO}${YW}No models were downloaded. Add GGUF files under /var/lib/llama-cpp/models or configure /etc/llama-cpp-models.ini.${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  _release_recover_archive /opt/llama-cpp "$HOME/.llama-cpp" || return $?
  [[ -f /opt/llama-cpp/llama-server && -f /var/lib/llama-cpp/.backend ]] || return 250
  local backend arch status request="${var_appversion:-$var_lxc_release}" pin
  pin=$request
  [[ "$pin" != latest ]] || pin=''
  backend=$(cat -- /var/lib/llama-cpp/.backend) || return $?
  case "$(get_system_arch)" in amd64) arch=x64 ;; arm64) arch=arm64 ;; *) return 65 ;; esac
  if check_for_gh_release llama-cpp ggml-org/llama.cpp "$pin"; then
    CLEAN_INSTALL=1 _release_service_deploy llama-cpp /opt/llama-cpp "$HOME/.llama-cpp" \
      _llama_cpp_deploy /opt/llama-cpp "$CHECK_UPDATE_RELEASE" "$backend" "$arch" selected || return $?
    msg_ok "Updated llama.cpp; model store, presets and service configuration preserved"
  else
    status=$?
    [[ "$status" == 1 ]] || return "$status"
    _release_service_deploy llama-cpp /opt/llama-cpp "$HOME/.llama-cpp" || return $?
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
