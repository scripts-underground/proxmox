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
  setup_hwaccel llama-cpp
  local backend=$var_lxc_backend arch stage release build asset var_appversion
  local -a payload=()
  case "$(get_system_arch)" in
    amd64) arch=x64 ;;
    arm64) arch=arm64 ;;
    *)
      msg_error "Unsupported llama.cpp architecture"
      exit 65
      ;;
  esac
  if [[ "$backend" == auto ]]; then
    case "${HWACCEL_VENDOR:-none}" in
      nvidia) [[ "$arch" == x64 ]] && backend=cuda || backend=cpu ;;
      intel | amd) backend=vulkan ;;
      *) backend=cpu ;;
    esac
  fi
  case "$backend-$arch" in
    cpu-x64 | cpu-arm64) asset="bin-ubuntu-$arch" ;;
    vulkan-x64 | vulkan-arm64)
      $STD apt install -y libvulkan1 mesa-vulkan-drivers vulkan-tools
      asset="bin-ubuntu-vulkan-$arch"
      ;;
    cuda-x64) asset=bin-ubuntu-cuda-12.8-x64 ;;
    sycl-x64)
      # Upstream's Ubuntu SYCL build uses oneAPI 2026.1 and oneDNN 2026.0.
      # Install runtime components, not the compiler or full oneAPI toolkit.
      setup_deb822_repo intel-oneapi "https://apt.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB" "https://apt.repos.intel.com/oneapi" all main amd64
      $STD apt install -y intel-oneapi-compiler-dpcpp-cpp-runtime-2026.1 intel-oneapi-mkl-sycl-blas-2026.1 intel-oneapi-dnnl-2026.0 libze1 ocl-icd-libopencl1
      find /opt/intel/oneapi -type f -name '*.so*' -printf '%h\n' | sort -u > /etc/ld.so.conf.d/llama-cpp-sycl.conf
      ldconfig
      asset=bin-ubuntu-sycl-fp16-x64
      ;;
    *)
      msg_error "Supported llama.cpp backends: auto, cpu, vulkan, cuda (x64), sycl (x64)"
      exit 65
      ;;
  esac
  [[ "$var_lxc_models_max" =~ ^[1-9][0-9]*$ && "$var_lxc_port" =~ ^[0-9]+$ ]] || exit 65

  msg_info "Installing llama.cpp"
  stage=$(mktemp -d)
  release="$var_lxc_release"
  [[ "$release" != latest ]] || release=$(get_latest_github_release "ggml-org/llama.cpp" false)
  var_appversion="$release"
  # Stable releases designate their compatible b* binaries through this asset.
  HOME="$stage" USE_ORIGINAL_FILENAME=true FORCE_DEPLOY=1 fetch_and_deploy_gh_release "llama-cpp-designation" "ggml-org/llama.cpp" "singlefile" "$var_appversion" "$stage/designation" "nightly-tag.txt"
  [[ "$(< "$stage/.llama-cpp-designation")" == "${release#v}" ]] || exit 250
  release="${release#v}"
  build=$(< "$stage/designation/nightly-tag.txt")
  [[ "$build" =~ ^b[0-9]+$ ]] || {
    msg_error "Invalid designated llama.cpp binary release"
    exit 250
  }
  var_appversion="$build"
  HOME="$stage" FORCE_DEPLOY=1 CLEAN_INSTALL=1 fetch_and_deploy_gh_release "llama-cpp" "ggml-org/llama.cpp" "prebuild" "$build" "$stage/payload" "llama-$build-$asset.tar.gz"
  [[ "$(< "$stage/.llama-cpp")" == "$build" && -x "$stage/payload/llama-server" ]] || exit 250
  if [[ "$backend" == cuda ]]; then
    HOME="$stage" FORCE_DEPLOY=1 CLEAN_INSTALL=0 fetch_and_deploy_gh_release "llama-cpp-cudart" "ggml-org/llama.cpp" "prebuild" "$build" "$stage/payload" "cudart-llama-$build-$asset.tar.gz"
    [[ "$(< "$stage/.llama-cpp-cudart")" == "$build" && -f "$stage/payload/libcudart.so.12" && -f "$stage/payload/libcublas.so.12" && -f "$stage/payload/libcublasLt.so.12" ]] || exit 250
  fi
  install -d /opt/llama-cpp
  mapfile -d '' payload < <(find "$stage/payload" -mindepth 1 -maxdepth 1 -print0)
  cp -a -- "${payload[@]}" /opt/llama-cpp/
  printf '%s\n' "$release" > "$HOME/.llama-cpp"
  rm -rf "$stage"
  printf '%s\n' "$backend" > /var/lib/llama-cpp/.backend

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
  ln -sfn /opt/llama-cpp/llama-server /usr/local/bin/llama-server
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
  [[ -x /opt/llama-cpp/llama-server && -f /var/lib/llama-cpp/.backend ]] || exit 250
  local backend arch asset stage release build status active=0
  local -a payload=()
  local pin="${var_appversion:-$var_lxc_release}" var_appversion
  backend=$(< /var/lib/llama-cpp/.backend)
  case "$(get_system_arch)" in
    amd64) arch=x64 ;;
    arm64) arch=arm64 ;;
    *)
      msg_error "Unsupported llama.cpp architecture"
      exit 65
      ;;
  esac
  case "$backend-$arch" in
    cpu-x64 | cpu-arm64) asset="bin-ubuntu-$arch" ;;
    vulkan-x64 | vulkan-arm64) asset="bin-ubuntu-vulkan-$arch" ;;
    cuda-x64) asset=bin-ubuntu-cuda-12.8-x64 ;;
    sycl-x64) asset=bin-ubuntu-sycl-fp16-x64 ;;
    *)
      msg_error "Unsupported installed llama.cpp backend: $backend $arch"
      exit 65
      ;;
  esac
  if check_for_gh_release "llama-cpp" "ggml-org/llama.cpp" "$pin"; then
    stage=$(mktemp -d)
    release="${CHECK_UPDATE_RELEASE#v}"
    var_appversion="$CHECK_UPDATE_RELEASE"
    HOME="$stage" USE_ORIGINAL_FILENAME=true FORCE_DEPLOY=1 fetch_and_deploy_gh_release "llama-cpp-designation" "ggml-org/llama.cpp" "singlefile" "$var_appversion" "$stage/designation" "nightly-tag.txt"
    [[ "$(< "$stage/.llama-cpp-designation")" == "$release" ]] || exit 250
    build=$(< "$stage/designation/nightly-tag.txt")
    [[ "$build" =~ ^b[0-9]+$ ]] || {
      msg_error "Invalid designated llama.cpp binary release"
      exit 250
    }
    var_appversion="$build"
    # Prepare every runtime layer before touching the installed service or marker.
    HOME="$stage" FORCE_DEPLOY=1 CLEAN_INSTALL=1 fetch_and_deploy_gh_release "llama-cpp" "ggml-org/llama.cpp" "prebuild" "$build" "$stage/payload" "llama-$build-$asset.tar.gz"
    [[ "$(< "$stage/.llama-cpp")" == "$build" && -x "$stage/payload/llama-server" ]] || exit 250
    if [[ "$backend" == cuda ]]; then
      HOME="$stage" FORCE_DEPLOY=1 CLEAN_INSTALL=0 fetch_and_deploy_gh_release "llama-cpp-cudart" "ggml-org/llama.cpp" "prebuild" "$build" "$stage/payload" "cudart-llama-$build-$asset.tar.gz"
      [[ "$(< "$stage/.llama-cpp-cudart")" == "$build" && -f "$stage/payload/libcudart.so.12" && -f "$stage/payload/libcublas.so.12" && -f "$stage/payload/libcublasLt.so.12" ]] || exit 250
    fi
    systemctl is-active --quiet llama-cpp && active=1
    [[ "$active" == 0 ]] || systemctl stop llama-cpp
    mapfile -d '' payload < <(find "$stage/payload" -mindepth 1 -maxdepth 1 -print0)
    cp -a --remove-destination -- "${payload[@]}" /opt/llama-cpp/
    [[ "$active" == 0 ]] || systemctl start llama-cpp
    printf '%s\n' "$release" > "$HOME/.llama-cpp"
    rm -rf "$stage"
    msg_ok "Updated llama.cpp; model store, presets and service configuration preserved"
  else
    status=$?
    [[ "$status" == 1 ]] || exit "$status"
  fi
  exit 0
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
