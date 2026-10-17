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
  setup_hwaccel ollama

  msg_info "Installing Ollama"
  local arch release var_appversion rocm_dir has_rocm=0
  arch=$(get_system_arch)
  case "$arch" in
    amd64 | arm64) ;;
    *)
      msg_error "Unsupported Ollama architecture: $arch"
      exit 65
      ;;
  esac
  var_appversion="$var_lxc_release"
  [[ "$var_appversion" == latest ]] || var_appversion="v${var_appversion#v}"
  fetch_and_deploy_gh_release "ollama-com" "ollama/ollama" "prebuild" "$var_appversion" /opt/ollama "ollama-linux-${arch}.tar.zst"
  release=$(< "$HOME/.ollama-com")
  if [[ "$var_appversion" != latest && "$release" != "${var_appversion#v}" ]]; then
    msg_error "Requested Ollama release was not deployed"
    exit 250
  fi
  if [[ " ${HWACCEL_VENDORS:-} " == *' amd '* && -c /dev/kfd ]]; then
    [[ "$arch" == amd64 ]] || {
      msg_error "Ollama ROCm requires amd64"
      exit 65
    }
    var_appversion="v$release"
    # The prebuild helper strips the ROCm archive's single top-level lib directory.
    fetch_and_deploy_gh_release "ollama-rocm" "ollama/ollama" "prebuild" "$var_appversion" /opt/ollama/lib "ollama-linux-amd64-rocm.tar.zst"
    [[ "$(< "$HOME/.ollama-rocm")" == "$release" ]] || {
      msg_error "Ollama ROCm release mismatch"
      exit 250
    }
    for rocm_dir in /opt/ollama/lib/ollama/rocm /opt/ollama/lib/ollama/rocm_v*; do
      [[ ! -d "$rocm_dir" ]] || has_rocm=1
    done
    [[ "$has_rocm" == 1 ]] || {
      msg_error "Ollama ROCm runtime missing"
      exit 250
    }
  fi
  [[ "$var_lxc_port" =~ ^[0-9]+$ ]] || {
    msg_error "Invalid Ollama port"
    exit 65
  }
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

  local exec_metadata executable resolved prefix arch stage release_status rocm_dir has_rocm=0 active=0
  local -a payload=()
  local pin="${var_appversion:-$var_lxc_release}" var_appversion
  local exec_pattern='path=([^[:space:];}]+)' magic
  exec_metadata=$(systemctl show --property=ExecStart --value ollama)
  [[ "$exec_metadata" =~ $exec_pattern ]] || {
    msg_error "No ${APP} Installation Found!"
    exit 250
  }
  executable=${BASH_REMATCH[1]}
  resolved=$(realpath -e -- "$executable")
  case "$resolved" in
    /opt/ollama/bin/ollama) prefix=/opt/ollama ;;
    /usr/local/lib/ollama/bin/ollama) prefix=/usr/local/lib/ollama ;;
    /usr/local/bin/ollama) prefix=/usr/local ;;
    *)
      msg_error "Custom Ollama executable layout left unchanged: $resolved"
      exit 250
      ;;
  esac
  magic=$(od -An -tx1 -N4 -- "$resolved")
  [[ "${magic//[[:space:]]/}" == 7f454c46 ]] || {
    msg_error "Ollama executable is not an ELF binary"
    exit 250
  }

  if check_for_gh_release "ollama-com" "ollama/ollama" "$pin"; then
    ensure_dependencies zstd
    arch=$(get_system_arch)
    case "$arch" in
      amd64 | arm64) ;;
      *)
        msg_error "Unsupported Ollama architecture: $arch"
        exit 65
        ;;
    esac
    stage=$(mktemp -d)
    var_appversion="$CHECK_UPDATE_RELEASE"
    # Download all runtime layers before stopping the service or changing live files.
    if ! HOME="$stage" FORCE_DEPLOY=1 CLEAN_INSTALL=1 fetch_and_deploy_gh_release "ollama-com" "ollama/ollama" "prebuild" "$var_appversion" "$stage/payload" "ollama-linux-${arch}.tar.zst"; then
      rm -rf "$stage"
      msg_error "Download or deployment failed – check network connectivity and GitHub API availability"
      exit 250
    fi
    if [[ "$(< "$stage/.ollama-com")" != "${CHECK_UPDATE_RELEASE#v}" || ! -x "$stage/payload/bin/ollama" ]]; then
      rm -rf "$stage"
      msg_error "Requested Ollama release was not staged"
      exit 250
    fi
    # Existing installations select their actual runtime layer, without rewriting
    # effective account/HOME/model configuration, units, bindings or launchers.
    for rocm_dir in "$prefix/lib/ollama/rocm" "$prefix"/lib/ollama/rocm_v*; do
      [[ ! -d "$rocm_dir" ]] || has_rocm=1
    done
    if [[ "$has_rocm" == 1 ]]; then
      if [[ "$arch" != amd64 ]] || ! HOME="$stage" FORCE_DEPLOY=1 CLEAN_INSTALL=0 fetch_and_deploy_gh_release "ollama-rocm" "ollama/ollama" "prebuild" "$var_appversion" "$stage/payload/lib" "ollama-linux-amd64-rocm.tar.zst"; then
        rm -rf "$stage"
        msg_error "Ollama ROCm download failed; installed runtime left unchanged"
        exit 250
      fi
      has_rocm=0
      for rocm_dir in "$stage/payload/lib/ollama/rocm" "$stage"/payload/lib/ollama/rocm_v*; do
        [[ ! -d "$rocm_dir" ]] || has_rocm=1
      done
      if [[ "$(< "$stage/.ollama-rocm")" != "${CHECK_UPDATE_RELEASE#v}" || "$has_rocm" != 1 ]]; then
        rm -rf "$stage"
        msg_error "Requested Ollama ROCm release was not staged"
        exit 250
      fi
    fi

    systemctl is-active --quiet ollama && active=1
    if [[ "$active" == 1 ]]; then
      msg_info "Stopping Services"
      systemctl stop ollama
      msg_ok "Services Stopped"
    fi
    mapfile -d '' payload < <(find "$stage/payload" -mindepth 1 -maxdepth 1 -print0)
    if ! cp -a --remove-destination -- "${payload[@]}" "$prefix/"; then
      if [[ "$active" == 1 ]]; then
        systemctl start ollama
      fi
      rm -rf "$stage"
      msg_error "Ollama runtime copy failed; retry the unfinished update"
      exit 250
    fi
    if [[ "$active" == 1 ]]; then
      msg_info "Starting Services"
      systemctl start ollama
      msg_ok "Started Services"
    fi
    cp "$stage/.ollama-com" "$HOME/.ollama-com"
    [[ ! -f "$stage/.ollama-rocm" ]] || cp "$stage/.ollama-rocm" "$HOME/.ollama-rocm"
    rm -rf "$stage"
    msg_ok "Updated Ollama; account, models and service configuration preserved"
  else
    release_status=$?
    [[ "$release_status" == 1 ]] || exit "$release_status"
  fi
  exit 0
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
