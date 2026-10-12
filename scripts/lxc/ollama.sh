#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: havardthom
# Co-Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://ollama.com/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Ollama"
var_tags="${var_tags:-ai}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-40}"
var_os="${var_os:-ubuntu}"
var_version="${var_version:-24.04}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_gpu="${var_gpu:-yes}"
var_lxc_release="${var_lxc_release:-${var_appversion:-latest}}"
var_lxc_port="${var_lxc_port:-80}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y curl zstd
  msg_ok "Installed Dependencies"

  if ! id ollama > /dev/null 2>&1; then
    useradd --system --user-group --create-home --home-dir /usr/share/ollama --shell /usr/sbin/nologin ollama
  fi
  install -d -m 750 -o ollama -g ollama /usr/share/ollama/.ollama
  setup_hwaccel ollama || return $?
  local arch amd_layer=0
  arch=$(get_system_arch) || return $?
  [[ " ${HWACCEL_VENDORS:-} " != *' amd '* || ! -c /dev/kfd ]] || amd_layer=1
  _ollama_deploy /opt/ollama "$var_lxc_release" "$arch" "$amd_layer" || return $?
  [[ "$var_lxc_port" =~ ^[0-9]+$ ]] || return 65
  cat << EOF > /etc/ollama.env
HOME=/usr/share/ollama
OLLAMA_HOST=0.0.0.0:$var_lxc_port
# OLLAMA_MODELS defaults to HOME/.ollama/models; set an explicit path here if needed.
EOF
  chown root:ollama /etc/ollama.env
  chmod 640 /etc/ollama.env
  cat << 'EOF' > /etc/systemd/system/ollama.service
[Unit]
Description=Ollama Service
Wants=network-online.target
After=network-online.target

[Service]
Type=exec
User=ollama
Group=ollama
WorkingDirectory=/opt/ollama
EnvironmentFile=/etc/ollama.env
ExecStart=/opt/ollama/bin/ollama serve
AmbientCapabilities=CAP_NET_BIND_SERVICE
Restart=on-failure
RestartSec=3
TimeoutStopSec=60

[Install]
WantedBy=multi-user.target
EOF
  cat << EOF > /usr/local/bin/ollama
#!/usr/bin/env sh
export OLLAMA_HOST="\${OLLAMA_HOST:-127.0.0.1:$var_lxc_port}"
exec /opt/ollama/bin/ollama "\$@"
EOF
  chmod 755 /usr/local/bin/ollama
  systemctl daemon-reload
  systemctl enable --now ollama
  msg_ok "Installed Ollama with an empty model store"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:${var_lxc_port}${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  local exec_metadata executable resolved prefix arch amd_layer=0 clean=0 pin="${var_appversion:-$var_lxc_release}" magic
  local exec_pattern='path=([^[:space:];}]+)'
  exec_metadata=$(systemctl show --property=ExecStart --value ollama) || return $?
  [[ "$exec_metadata" =~ $exec_pattern ]] || return 250
  executable=${BASH_REMATCH[1]}
  resolved=$(realpath -e -- "$executable") || return 250
  case "$resolved" in
    /opt/ollama/bin/ollama) prefix=/opt/ollama clean=1 ;;
    /usr/local/lib/ollama/bin/ollama) prefix=/usr/local/lib/ollama ;;
    /usr/local/bin/ollama) prefix=/usr/local ;;
    *)
      msg_error "Custom Ollama executable layout left unchanged: $resolved"
      return 250
      ;;
  esac
  magic=$(od -An -tx1 -N4 -- "$resolved") || return 250
  [[ "${magic//[[:space:]]/}" == 7f454c46 ]] || return 250
  _release_recover_archive "$prefix" "$HOME/.ollama-com" || return $?
  [[ "$pin" != latest ]] || pin=''
  if check_for_gh_release ollama-com ollama/ollama "$pin"; then
    arch=$(get_system_arch) || return $?
    # Existing installations select their actual runtime layer, without rewriting
    # effective account/HOME/model configuration, units, bindings or launchers.
    [[ ! -c /dev/kfd || ! -d "$prefix/lib/ollama/rocm" ]] || amd_layer=1
    CLEAN_INSTALL="$clean" _release_service_deploy ollama "$prefix" "$HOME/.ollama-com" \
      _ollama_deploy "$prefix" "$CHECK_UPDATE_RELEASE" "$arch" "$amd_layer" selected || return $?
    msg_ok "Updated Ollama; account, models and service configuration preserved"
  else
    local release_status=$?
    [[ "$release_status" == 1 ]] || return "$release_status"
    _release_service_deploy ollama "$prefix" "$HOME/.ollama-com" || return $?
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
