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
  [[ "$OS_TYPE" == ubuntu && "$OS_VERSION" == 24.04 && "$(get_system_arch)" == amd64 ]] || exit 65
  [[ "$var_lxc_pinned_commit" =~ ^[a-f0-9]{40}$ && "$var_lxc_ggml_commit" =~ ^[a-f0-9]{40}$ &&
    "$var_lxc_cuda_arch" =~ ^[0-9]+$ && "$var_lxc_build_jobs" =~ ^[1-9][0-9]*$ &&
    "$var_lxc_port" =~ ^[0-9]+$ && "$var_lxc_memory_max_mib" =~ ^[1-9][0-9]*$ ]] || exit 65
  msg_info "Installing Strata build dependencies"
  $STD apt install -y --no-install-recommends git gpg gcc-13 g++-13 python3-venv
  ensure_dependencies jq
  setup_deb822_repo strata-cuda "https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/3bf863cc.pub" \
    "https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64" / "" amd64
  $STD apt install -y --no-install-recommends cuda-nvcc-12-8 cuda-cudart-dev-12-8 libcublas-dev-12-8 cuda-nvrtc-dev-12-8
  setup_uv
  if ! id strata > /dev/null 2>&1; then
    useradd --system --user-group --create-home --home-dir /var/lib/strata --shell /usr/sbin/nologin strata
  fi
  install -d -m 755 -o strata -g strata /var/lib/strata/models /var/lib/strata/packs /var/lib/strata/mtp /var/log/strata
  setup_hwaccel strata

  msg_info "Building pinned Strata CUDA engine"
  (
    local stage='' python runtime
    install -d -m 755 /opt/strata-builds /opt/strata/venvs
    runtime=$(mktemp -d /opt/strata/venvs/venv.XXXXXX)
    python="$runtime/bin/python"
    # Scope cleanup to this build; the bundle owns the outer EXIT trap.
    # Once published, runtime.json owns the Python environment the launcher uses.
    trap '[[ -z "$stage" ]] || rm -rf "$stage"; if [[ ! -f /opt/strata/runtime.json ]] || [[ "$(jq -r .python /opt/strata/runtime.json)" != "$python" ]]; then rm -rf "$runtime"; fi' EXIT
    chmod 755 "$runtime"
    stage=$(mktemp -d /opt/strata-builds/build.XXXXXX)
    chmod 755 "$stage"
    mkdir -m 700 "$stage/home"
    GIT_LFS_SKIP_SMUDGE=1 HOME="$stage/home" clone_and_deploy_gh_commit strata-source Niko1221/Strata main '' "$var_lxc_pinned_commit" "$stage/source"
    GIT_LFS_SKIP_SMUDGE=1 HOME="$stage/home" clone_and_deploy_gh_commit strata-ggml ggml-org/llama.cpp master '' "$var_lxc_ggml_commit" "$stage/ggml"
    [[ "$(git -C "$stage/source" rev-parse HEAD)" == "$var_lxc_pinned_commit" &&
    "$(git -C "$stage/ggml" rev-parse HEAD)" == "$var_lxc_ggml_commit" ]] || exit 250
    $STD uv venv --python /usr/bin/python3 "$runtime"
    $STD uv pip install --python "$python" -r "$stage/source/requirements.txt"
    $STD "$runtime/bin/cmake" -S "$stage/source" -B "$stage/build" -G Ninja \
      -DCMAKE_BUILD_TYPE=Release -DSTRATA_ENABLE_CUDA=ON -DCMAKE_CUDA_COMPILER=/usr/local/cuda-12.8/bin/nvcc \
      -DCMAKE_CUDA_HOST_COMPILER=/usr/bin/g++-13 -DCMAKE_CXX_COMPILER=/usr/bin/g++-13 \
      -DCMAKE_MAKE_PROGRAM="$runtime/bin/ninja" -DCMAKE_CUDA_ARCHITECTURES="$var_lxc_cuda_arch" -DSTRATA_PORTABLE=ON \
      -DSTRATA_GGML_DIR="$stage/ggml" -DSTRATA_BUILD_TESTS=OFF
    $STD "$runtime/bin/cmake" --build "$stage/build" --target strata -j "$var_lxc_build_jobs"
    "$stage/build/strata" --help > "$stage/native-help.txt" 2>&1
    install -d -m 755 /opt/strata/bin
    cp -a "$stage/source/serve" "$stage/source/tools" "$stage/source/data" /opt/strata/
    cp "$stage/source/requirements.txt" /opt/strata/requirements.txt
    [[ ! -f "$stage/source/LICENSE" ]] || cp "$stage/source/LICENSE" /opt/strata/LICENSE
    install -m 755 "$stage/build/strata" /opt/strata/bin/strata
    jq -n --arg source "$var_lxc_pinned_commit" --arg ggml "$var_lxc_ggml_commit" --arg python "$python" --arg arch "$var_lxc_cuda_arch" \
      '{source_commit:$source,ggml_commit:$ggml,python:$python,cuda_arch:$arch,cuda:"12.8",portable:true}' > /opt/strata/runtime.json
  )
  cat << 'PY' > /opt/strata/bin/strata-launch
#!/usr/bin/env python3
import json, os, pathlib, re, sys
root = pathlib.Path(__file__).resolve().parents[1]
try:
    config = json.loads(pathlib.Path('/etc/strata/config.json').read_text())
    args = config['args']
    paths = [pathlib.Path(config['tokenizer']) / name for name in ('vocab.json', 'merges.txt', 'token_type.json')]
    pack = pathlib.Path(args[args.index('--pack') + 1])
    paths += [pack / 'index.txt', pack / 'dense.bin']
    native = pathlib.Path(args[args.index('--native') + 1])
    paths.append(native)
    split = re.fullmatch(r'(.*)-00001-of-(\d{5})\.gguf', native.name)
    if split:
        count = int(split[2])
        if not 1 <= count <= 128:
            raise ValueError('invalid shard count')
        paths += [native.with_name(f'{split[1]}-{i:05d}-of-{count:05d}.gguf') for i in range(2, count + 1)]
    if '--mtp' in args:
        paths.append(pathlib.Path(args[args.index('--mtp') + 1]) / 'draft_vocab.bin')
    missing = [str(path) for path in paths if not path.is_file() or path.stat().st_size == 0]
    if missing:
        print('Strata awaiting administrator model pack/tokenizer: ' + ', '.join(missing), flush=True)
        raise SystemExit(1)
    if '--check-data' in sys.argv:
        raise SystemExit(0)
    runtime = json.loads((root / 'runtime.json').read_text())
except (OSError, ValueError, KeyError, IndexError) as error:
    print('Strata configuration error: ' + str(error), file=sys.stderr)
    raise SystemExit(255)
os.chdir(root)
os.execv(runtime['python'], [runtime['python'], '-B', '-u', '-m', 'serve.server', '--engine', 'strata',
                           '--config', '/etc/strata/config.json', '--host', config['host'], '--port', str(config['port'])])
PY
  cat << 'PY' > /opt/strata/bin/strata-engine-guard
#!/usr/bin/env python3
import json, math, os, pathlib, subprocess, sys
root = pathlib.Path(__file__).resolve().parents[1]
try:
    policy = json.loads(pathlib.Path('/etc/strata/admission.json').read_text())
    if '--resident-budget-gib' not in sys.argv:
        raise ValueError('a bounded --resident-budget-gib is required for managed admission')
    resident = float(sys.argv[sys.argv.index('--resident-budget-gib') + 1])
    reserve = float(policy.get('reserve_ram_gib', 8))
    floor = float(policy['min_free_ram_gib'])
    if not all(math.isfinite(value) for value in (resident, reserve, floor)) or resident <= 0 or reserve < 8 or floor <= 0:
        raise ValueError('resident budget must be positive and RAM reserve at least 8 GiB')
    minimum_ram = int(max(floor, resident + reserve) * (1 << 30))
    minimum_vram = int(policy['min_free_vram_mib'])
    if minimum_ram <= 0 or minimum_vram <= 0:
        raise ValueError('admission floors must be positive')
    meminfo = dict(line.split(':', 1) for line in pathlib.Path('/proc/meminfo').read_text().splitlines())
    available = int(meminfo['MemAvailable'].split()[0]) * 1024
    cgroup_root = pathlib.Path('/sys/fs/cgroup')
    relative = next(line.split(':', 2)[2] for line in pathlib.Path('/proc/self/cgroup').read_text().splitlines() if line.startswith('0::'))
    current = (cgroup_root / relative.lstrip('/')).resolve()
    if not current.is_relative_to(cgroup_root) or not current.is_dir():
        raise ValueError('cannot identify own memory cgroup')
    while current.is_relative_to(cgroup_root):
        limit_file = current / 'memory.max'
        if limit_file.exists():
            limit = limit_file.read_text().strip()
            if limit != 'max':
                usage = int((current / 'memory.current').read_text())
                available = min(available, max(0, int(limit) - usage))
        if current == cgroup_root:
            break
        current = current.parent
    if available < minimum_ram:
        raise ValueError(f'RAM admission refused: {available} bytes available, {minimum_ram} required')
    gpu = subprocess.run(['nvidia-smi', '--query-gpu=memory.free', '--format=csv,noheader,nounits'],
                         capture_output=True, text=True, timeout=15)
    if gpu.returncode != 0:
        raise ValueError('NVIDIA admission query failed: ' + gpu.stderr.strip())
    free = [int(line.strip()) for line in gpu.stdout.splitlines() if line.strip()]
    if not free or min(free) < minimum_vram:
        raise ValueError(f'VRAM admission refused: observed {free}, required {minimum_vram} MiB')
except (OSError, ValueError, KeyError, IndexError, StopIteration, subprocess.TimeoutExpired) as error:
    print('Strata engine not started: ' + str(error), file=sys.stderr, flush=True)
    raise SystemExit(75)
os.execv(str(root / 'bin/strata'), [str(root / 'bin/strata'), *sys.argv[1:]])
PY
  chmod 755 /opt/strata/bin/strata-launch /opt/strata/bin/strata-engine-guard
  ln -sfn /opt/strata/bin/strata /usr/local/bin/strata
  ln -sfn /opt/strata/bin/strata-launch /usr/local/bin/strata-launch
  install -d -m 750 -o root -g strata /etc/strata
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
  printf '%s\n' "$var_lxc_pinned_commit" > "$HOME/.strata"
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
  ensure_dependencies jq
  [[ -x /opt/strata/bin/strata && -f /opt/strata/runtime.json ]] || exit 250
  [[ "$var_lxc_pinned_commit" =~ ^[a-f0-9]{40}$ && "$var_lxc_ggml_commit" =~ ^[a-f0-9]{40}$ &&
    "$var_lxc_cuda_arch" =~ ^[0-9]+$ && "$var_lxc_build_jobs" =~ ^[1-9][0-9]*$ ]] || exit 65
  local current runtime_status
  current=$(< "$HOME/.strata")
  if jq -e --arg source "$var_lxc_pinned_commit" --arg ggml "$var_lxc_ggml_commit" --arg arch "$var_lxc_cuda_arch" \
    '.source_commit == $source and .ggml_commit == $ggml and .cuda_arch == $arch and .cuda == "12.8" and .portable == true' /opt/strata/runtime.json > /dev/null; then
    runtime_status=0
  else
    runtime_status=$?
    [[ "$runtime_status" == 1 ]] || exit 250
  fi
  if [[ "$current" != "$var_lxc_pinned_commit" || "$runtime_status" == 1 || "${FORCE_DEPLOY:-0}" == 1 ]]; then
    (
      local stage='' python runtime previous_runtime active=0
      msg_info "Building pinned Strata CUDA engine"
      previous_runtime=$(jq -r '.python // empty' /opt/strata/runtime.json)
      previous_runtime=${previous_runtime%/bin/python}
      install -d -m 755 /opt/strata-builds /opt/strata/venvs
      runtime=$(mktemp -d /opt/strata/venvs/venv.XXXXXX)
      python="$runtime/bin/python"
      # Keep the published runtime on deploy failure, but never the build tree.
      trap '
        [[ -z "$stage" ]] || rm -rf "$stage"
        if [[ "$(jq -r .python /opt/strata/runtime.json)" == "$python" ]]; then
          if [[ "$previous_runtime" != "$runtime" && "${previous_runtime%/*}" == /opt/strata/venvs && "${previous_runtime##*/}" == venv.* ]]; then
            rm -rf "$previous_runtime"
          fi
        else
          rm -rf "$runtime"
        fi
      ' EXIT
      chmod 755 "$runtime"
      stage=$(mktemp -d /opt/strata-builds/build.XXXXXX)
      chmod 755 "$stage"
      mkdir -m 700 "$stage/home"
      GIT_LFS_SKIP_SMUDGE=1 HOME="$stage/home" clone_and_deploy_gh_commit strata-source Niko1221/Strata main '' "$var_lxc_pinned_commit" "$stage/source"
      GIT_LFS_SKIP_SMUDGE=1 HOME="$stage/home" clone_and_deploy_gh_commit strata-ggml ggml-org/llama.cpp master '' "$var_lxc_ggml_commit" "$stage/ggml"
      [[ "$(git -C "$stage/source" rev-parse HEAD)" == "$var_lxc_pinned_commit" &&
      "$(git -C "$stage/ggml" rev-parse HEAD)" == "$var_lxc_ggml_commit" ]] || exit 250
      $STD uv venv --python /usr/bin/python3 "$runtime"
      $STD uv pip install --python "$python" -r "$stage/source/requirements.txt"
      $STD "$runtime/bin/cmake" -S "$stage/source" -B "$stage/build" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release -DSTRATA_ENABLE_CUDA=ON -DCMAKE_CUDA_COMPILER=/usr/local/cuda-12.8/bin/nvcc \
        -DCMAKE_CUDA_HOST_COMPILER=/usr/bin/g++-13 -DCMAKE_CXX_COMPILER=/usr/bin/g++-13 \
        -DCMAKE_MAKE_PROGRAM="$runtime/bin/ninja" -DCMAKE_CUDA_ARCHITECTURES="$var_lxc_cuda_arch" -DSTRATA_PORTABLE=ON \
        -DSTRATA_GGML_DIR="$stage/ggml" -DSTRATA_BUILD_TESTS=OFF
      $STD "$runtime/bin/cmake" --build "$stage/build" --target strata -j "$var_lxc_build_jobs"
      "$stage/build/strata" --help > "$stage/native-help.txt" 2>&1
      jq -n --arg source "$var_lxc_pinned_commit" --arg ggml "$var_lxc_ggml_commit" --arg python "$python" --arg arch "$var_lxc_cuda_arch" \
        '{source_commit:$source,ggml_commit:$ggml,python:$python,cuda_arch:$arch,cuda:"12.8",portable:true}' > "$stage/runtime.json"
      # Finish cloning and building before touching the installed service or runtime.
      systemctl is-active --quiet strata && active=1
      [[ "$active" == 0 ]] || systemctl stop strata
      cp -a --remove-destination "$stage/source/serve" "$stage/source/tools" "$stage/source/data" /opt/strata/
      cp "$stage/source/requirements.txt" /opt/strata/requirements.txt
      [[ ! -f "$stage/source/LICENSE" ]] || cp "$stage/source/LICENSE" /opt/strata/LICENSE
      install -m 755 "$stage/build/strata" /opt/strata/bin/strata
      cp "$stage/runtime.json" /opt/strata/runtime.json
      [[ "$active" == 0 ]] || systemctl start strata
      printf '%s\n' "$var_lxc_pinned_commit" > "$HOME/.strata"
    )
    msg_ok "Updated Strata; configuration, launcher, unit and model data preserved"
  else
    # A model-empty unit is intentionally skipped; active-serving claims require data.
    msg_ok "Pinned Strata engine is already installed"
  fi
  exit 0
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
