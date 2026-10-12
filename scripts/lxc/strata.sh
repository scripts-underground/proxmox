#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2026 scripts-underground.org
# Author: Alex Indigo (alexindigo)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/Niko1221/Strata

# shellcheck disable=SC2034
APP="Strata"
var_tags="${var_tags:-ai}"
var_cpu="${var_cpu:-6}"
var_ram="${var_ram:-65536}"
var_disk="${var_disk:-40}"
var_os="${var_os:-ubuntu}"
var_version="${var_version:-24.04}"
var_unprivileged="${var_unprivileged:-1}"
var_gpu="${var_gpu:-yes}"
var_lxc_pinned_commit="${var_lxc_pinned_commit:-fb58e0dbc8399662c0e47c76578c6e878b14f6cf}"
var_lxc_ggml_commit="${var_lxc_ggml_commit:-3cf03257f219afbe7334045ff7c6a06ac68c627d}"
var_lxc_cuda_arch="${var_lxc_cuda_arch:-89}"
var_lxc_build_jobs="${var_lxc_build_jobs:-4}"
var_lxc_port="${var_lxc_port:-80}"
var_lxc_memory_max_mib="${var_lxc_memory_max_mib:-$((var_ram * 9 / 10))}"

function install_script() {
  [[ "$OS_TYPE" == ubuntu && "$OS_VERSION" == 24.04 && "$(get_system_arch)" == amd64 ]] || return 65
  msg_info "Installing Strata build dependencies"
  $STD apt install -y --no-install-recommends git gpg gcc-13 g++-13 python3-venv || return $?
  _hwaccel_cuda_repo ubuntu2404 x86_64 || return $?
  $STD apt install -y --no-install-recommends cuda-nvcc-12-8 cuda-cudart-dev-12-8 libcublas-dev-12-8 cuda-nvrtc-dev-12-8 || return $?
  setup_uv || return $?
  if ! id strata > /dev/null 2>&1; then
    useradd --system --user-group --create-home --home-dir /var/lib/strata --shell /usr/sbin/nologin strata || return $?
  fi
  install -d -m 755 -o strata -g strata /var/lib/strata/models /var/lib/strata/packs /var/lib/strata/mtp /var/log/strata || return $?
  setup_hwaccel strata || return $?
  _strata_deploy /opt/strata "$var_lxc_pinned_commit" "$var_lxc_ggml_commit" "$var_lxc_cuda_arch" "$var_lxc_build_jobs" || return $?
  [[ "$var_lxc_port" =~ ^[0-9]+$ && "$var_lxc_memory_max_mib" =~ ^[1-9][0-9]*$ ]] || return 65
  install -d -m 750 -o root -g strata /etc/strata || return $?
  cat << EOF > /etc/strata/config.json
{
  "exe": "/opt/strata/bin/strata-engine-guard",
  "cwd": "/opt/strata",
  "tokenizer": "/var/lib/strata/packs/qwen3.8-flash-next-ud-iq4_xs/tokenizer",
  "model_name": "qwen3.8-flash-next-ud-iq4_xs",
  "host": "0.0.0.0",
  "port": $var_lxc_port,
  "lazy_load": true,
  "idle_unload_s": 300,
  "log": "/var/log/strata/engine.log",
  "args": ["--pack", "/var/lib/strata/packs/qwen3.8-flash-next-ud-iq4_xs",
    "--native", "/var/lib/strata/models/Qwen3.8-Flash-Next-UD-IQ4_XS-00001-of-00003.gguf",
    "--expert-profile", "/opt/strata/data/expert-profile.bin", "--expert-cache", "auto",
    "--prefill", "auto", "--resident-budget-gib", "16", "--max-context", "131072",
    "--kv", "int8", "--kv-resident", "32768"]
}
EOF
  printf '{"min_free_ram_gib":24,"reserve_ram_gib":8,"min_free_vram_mib":8192}\n' > /etc/strata/admission.json
  chown root:strata /etc/strata/config.json /etc/strata/admission.json
  chmod 640 /etc/strata/config.json /etc/strata/admission.json
  cat << EOF > /etc/systemd/system/strata.service
[Unit]
Description=Strata native CUDA model server (awaits administrator model data)
Wants=network-online.target
After=network-online.target

[Service]
Type=exec
User=strata
Group=strata
WorkingDirectory=/opt/strata
Environment=LD_LIBRARY_PATH=/usr/local/cuda-12.8/lib64
ExecCondition=/opt/strata/bin/strata-launch --check-data
ExecStart=/opt/strata/bin/strata-launch
AmbientCapabilities=CAP_NET_BIND_SERVICE
LimitMEMLOCK=infinity
MemoryMax=${var_lxc_memory_max_mib}M
Nice=10
KillMode=control-group
TimeoutStopSec=120
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now strata
  msg_ok "Installed Strata CUDA engine; awaiting real model pack/tokenizer"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${INFO}${YW}Strata is installed without model weights. Its service waits for real model data.${CL}"
  echo -e "${INFO}${YW}Configure /etc/strata/config.json and /etc/strata/admission.json inside the container.${CL}"
  echo -e "${INFO}${YW}Native UI/API after data is configured: http://${IP}:${var_lxc_port}${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  _release_recover_archive /opt/strata "$HOME/.strata" || return $?
  [[ -f /opt/strata/runtime.json ]] || return 250
  local current runtime_status
  current=$(cat "$HOME/.strata") || return $?
  if jq -e --arg source "$var_lxc_pinned_commit" --arg ggml "$var_lxc_ggml_commit" --arg arch "$var_lxc_cuda_arch" \
    '.source_commit == $source and .ggml_commit == $ggml and .cuda_arch == $arch and .cuda == "12.8" and .portable == true' /opt/strata/runtime.json > /dev/null; then
    runtime_status=0
  else
    runtime_status=$?
    [[ "$runtime_status" == 1 ]] || return 250
  fi
  if [[ "$current" != "$var_lxc_pinned_commit" || "$runtime_status" == 1 || "${FORCE_DEPLOY:-0}" == 1 ]]; then
    _update_services_begin strata strata || return $?
    systemctl stop strata || return $?
    FORCE_DEPLOY=1 _strata_deploy /opt/strata "$var_lxc_pinned_commit" "$var_lxc_ggml_commit" "$var_lxc_cuda_arch" "$var_lxc_build_jobs" || return $?
  fi
  systemctl start strata || return $?
  # A model-empty unit is intentionally skipped; active-serving claims require data.
  local data_status
  if /opt/strata/bin/strata-launch --check-data; then
    _update_services_finish strata || return $?
    systemctl is-active --quiet strata || return 150
  else
    data_status=$?
    [[ "$data_status" == 1 ]] || return "$data_status"
    msg_ok "Pinned Strata engine installed; service still awaits model data"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
