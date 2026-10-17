#!/usr/bin/env bash
# Offline pinned CUDA build, model-data gate and update preservation checks.
set -euo pipefail
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export work

scratch_paths() {
  local path
  for path in "$@"; do
    [[ "$path" != -* ]] || continue
    path=$(realpath -m -- "$path")
    [[ "$path" == "$work" || "$path" == "$work/"* ]] || return 99
  done
}
cp() {
  scratch_paths "$@" || return 99
  [[ "${fail_deploy:-0}" == 0 || "$1" != -a ]] || return 28
  command cp "$@"
}
rm() { scratch_paths "$@" && command rm "$@"; }
ln() { scratch_paths "$@" && command ln "$@"; }
msg_info() { :; }
msg_ok() { :; }
header_info() { :; }
check_container_storage() { :; }
check_container_resources() { :; }
get_system_arch() { printf '%s\n' "$test_arch"; }
id() { return 1; }
useradd() { :; }
chown() { :; }
apt() { printf '%s\n' "$*" >> "$fixture/packages"; }
ensure_dependencies() { printf '%s\n' "$*" >> "$fixture/dependencies"; }
setup_uv() { :; }
setup_hwaccel() { [[ "$1" == strata ]]; }
setup_deb822_repo() { printf '%s\n' "$*" > "$fixture/repo"; }
systemctl() {
  [[ "$1" != is-active ]] || return "$inactive"
  printf '%s\n' "$*" >> "$fixture/services"
  if [[ "$1" == start && "${fail_start:-0}" == 1 ]]; then return 32; fi
}
install() {
  local directory=0
  local -a paths=()
  while (($#)); do
    case "$1" in
      -d)
        directory=1
        shift
        ;;
      -m | -o | -g) shift 2 ;;
      *)
        paths+=("$1")
        shift
        ;;
    esac
  done
  scratch_paths "${paths[@]}"
  if [[ "$directory" == 1 ]]; then
    command mkdir -p "${paths[@]}"
  else
    command install -m 755 "${paths[@]}"
  fi
}
clone_and_deploy_gh_commit() {
  scratch_paths "$6" "$HOME"
  [[ "$GIT_LFS_SKIP_SMUDGE" == 1 && "$HOME" != "$fixture/home" && -z "$4" ]]
  printf '%s|%s|%s|%s\n' "$1" "$2" "$3" "$5" >> "$fixture/clones"
  [[ "$fail_clone" != "$1" ]] || return 22
  command mkdir -p "$6"/{serve,tools,data}
  printf '' > "$6/requirements.txt"
  printf '%s\n' "$5" > "$6/.head"
  [[ "$wrong_head" != "$1" ]] || printf '%040d\n' 0 > "$6/.head"
  printf new-runtime > "$6/serve/server.py"
}
git() {
  [[ "$1" == -C && "$3 $4" == 'rev-parse HEAD' ]]
  scratch_paths "$2"
  command cat "$2/.head"
}
uv() {
  if [[ "$1" == venv ]]; then
    scratch_paths "$4"
    command mkdir -p "$4/bin"
    cat << 'EOF' > "$4/bin/cmake"
#!/usr/bin/env bash
cmake_stub "$@"
EOF
    command chmod 755 "$4/bin/cmake"
    command ln -s "$(command -v python3)" "$4/bin/python"
  else
    [[ "$1 $2" == 'pip install' ]]
  fi
}
cmake_stub() {
  printf '%s\n' "$*" >> "$fixture/builds"
  [[ "$fail_build" == 0 ]] || return 31
  local build
  if [[ "$1" == --build ]]; then
    build=$2
    scratch_paths "$build"
    command mkdir -p "$build"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$build/strata"
    command chmod 755 "$build/strata"
  fi
}
silent_stub() {
  local status=0
  "$@" || status=$?
  [[ "$status" == 0 ]] || exit "$status"
}
export -f scratch_paths cp rm ln msg_info msg_ok header_info check_container_storage check_container_resources
export -f get_system_arch id useradd chown apt ensure_dependencies setup_uv setup_hwaccel setup_deb822_repo
export -f systemctl install clone_and_deploy_gh_commit git uv cmake_stub silent_stub

setup_case() {
  fixture="$work/$1"
  command mkdir -p "$fixture"/{home,stages,opt/strata/bin,etc/strata,etc/systemd/system,usr/local/bin,var/lib/strata}
  # Keep heredocs intact; their JSON braces are not Bash function boundaries.
  sed '/^source <(curl /d' "$ROOT/scripts/lxc/strata.sh" |
    sed -e "s#/opt/#$fixture/opt/#g" -e "s#/etc/#$fixture/etc/#g" -e "s#/var/#$fixture/var/#g" -e "s#/usr/#$fixture/usr/#g" > "$fixture/hooks"
  # Reject any unmapped absolute system root before invoking either hook.
  if sed -e "s#$work/#SCRATCH/#g" -e 's#/dev/null#NULL#g' -e 's#/proc/#PROC/#g' -e 's#/sys/#SYS/#g' \
    -e 's#"\$[[:alnum:]_]*"/#VARIABLE/#g' "$fixture/hooks" |
    grep -nE "(^|[[:space:]=\"'(])/[[:alnum:]_]"; then
    exit 99
  fi
  export fixture HOME="$fixture/home" TMPDIR="$fixture/stages" STD=''
  export OS_TYPE=ubuntu OS_VERSION=24.04 test_arch=amd64
  export var_lxc_pinned_commit=fb58e0dbc8399662c0e47c76578c6e878b14f6cf
  export var_lxc_ggml_commit=3cf03257f219afbe7334045ff7c6a06ac68c627d
  export var_lxc_cuda_arch=89 var_lxc_build_jobs=4 var_lxc_port=80 var_lxc_memory_max_mib=58982
  export fail_clone=none wrong_head=none fail_build=0 fail_deploy=0 fail_start=0 inactive=0 FORCE_DEPLOY=0
  : > "$fixture/services"
  : > "$fixture/clones"
  : > "$fixture/builds"
  : > "$fixture/dependencies"
}
run_hook() {
  rc=0
  export hook=$1
  bash -euo pipefail -c 'source "$fixture/hooks"; "$hook"' > "$fixture/output" 2>&1 || rc=$?
}

setup_case install
run_hook install_script
[[ "$rc" == 0 && "$(< "$HOME/.strata")" == "$var_lxc_pinned_commit" ]]
[[ -z "$(command find "$fixture/opt/strata-builds" -mindepth 1 -print -quit)" ]]
python=$(jq -r .python "$fixture/opt/strata/runtime.json")
[[ "$python" == "$fixture/opt/strata/venvs/venv."*/bin/python && -x "$python" ]]
"$python" -c 'import sys; assert sys.version_info.major == 3'
[[ -L "$fixture/usr/local/bin/strata" && -L "$fixture/usr/local/bin/strata-launch" ]]
grep -Fxq "strata-source|Niko1221/Strata|main|$var_lxc_pinned_commit" "$fixture/clones"
grep -Fxq "strata-ggml|ggml-org/llama.cpp|master|$var_lxc_ggml_commit" "$fixture/clones"
grep -q 'ubuntu2404/x86_64 /  amd64' "$fixture/repo"
grep -q 'cuda-nvcc-12-8 cuda-cudart-dev-12-8 libcublas-dev-12-8 cuda-nvrtc-dev-12-8' "$fixture/packages"
grep -q -- '-DCMAKE_CUDA_ARCHITECTURES=89.*-DSTRATA_PORTABLE=ON' "$fixture/builds"
grep -qx jq "$fixture/dependencies"
jq -e '.port == 80 and .lazy_load and .idle_unload_s == 300 and (.args | index("131072")) != null and (.args | index("int8")) != null and (.args | index("32768")) != null' "$fixture/etc/strata/config.json" > /dev/null
grep -qx "ExecCondition=$fixture/opt/strata/bin/strata-launch --check-data" "$fixture/etc/systemd/system/strata.service"
[[ -z "$(command find "$fixture/var/lib/strata" -type f -print)" ]]
printf 'PASS pinned source/ggml, CUDA toolkit/build and empty port-80 configuration\n'

rc=0
python3 "$fixture/opt/strata/bin/strata-launch" --check-data > "$fixture/data-check" 2>&1 || rc=$?
[[ "$rc" == 1 ]]
grep -q 'awaiting administrator' "$fixture/data-check"
rc=0
python3 "$fixture/opt/strata/bin/strata-engine-guard" > "$fixture/admission-check" 2>&1 || rc=$?
[[ "$rc" == 75 ]]
grep -q 'bounded --resident-budget-gib' "$fixture/admission-check"
printf 'PASS generated launcher waits for data; admission guard refuses unbounded execution\n'

# File-presence fixtures exercise the gate only, never launch a model or server.
config="$fixture/etc/strata/config.json"
pack=$(jq -r '.args[1]' "$config")
native=$(jq -r '.args[3]' "$config")
command mkdir -p "$pack/tokenizer"
for path in "$pack"/{index.txt,dense.bin,tokenizer/vocab.json,tokenizer/merges.txt,tokenizer/token_type.json} "$native" "${native/00001-of/00002-of}"; do
  printf data > "$path"
done
rc=0
python3 "$fixture/opt/strata/bin/strata-launch" --check-data > "$fixture/data-check" 2>&1 || rc=$?
[[ "$rc" == 1 ]]
printf data > "${native/00001-of/00003-of}"
python3 "$fixture/opt/strata/bin/strata-launch" --check-data
printf '' > "$pack/dense.bin"
rc=0
python3 "$fixture/opt/strata/bin/strata-launch" --check-data > "$fixture/data-check" 2>&1 || rc=$?
[[ "$rc" == 1 ]]
printf '{"reserve_ram_gib":8,"min_free_ram_gib":1000000000,"min_free_vram_mib":8192}\n' > "$fixture/etc/strata/admission.json"
rc=0
python3 "$fixture/opt/strata/bin/strata-engine-guard" --resident-budget-gib 16 > "$fixture/admission-check" 2>&1 || rc=$?
[[ "$rc" == 75 ]]
grep -q 'RAM admission refused' "$fixture/admission-check"
printf 'PASS launcher requires all nonempty shards/pack files; RAM admission refuses before engine execution\n'

for failure in clone head build deploy; do
  setup_case "install-fail-$failure"
  case "$failure" in
    clone)
      export fail_clone=strata-ggml
      expected=22
      ;;
    head)
      export wrong_head=strata-source
      expected=250
      ;;
    build)
      export fail_build=1 STD=silent_stub
      expected=31
      ;;
    deploy)
      export fail_deploy=1
      expected=28
      ;;
  esac
  run_hook install_script
  [[ "$rc" == "$expected" ]]
  [[ -z "$(command find "$fixture/opt/strata-builds" "$fixture/opt/strata/venvs" -mindepth 1 -print -quit)" ]]
  [[ ! -e "$HOME/.strata" ]]
  printf 'PASS install %s failure removes build and unpublished Python environment\n' "$failure"
done

for scenario in current forced inactive source-pin ggml-pin arch clone-fail head-mismatch build-fail deploy-fail restart-fail malformed-runtime; do
  setup_case "update-$scenario"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$fixture/opt/strata/bin/strata"
  chmod 755 "$fixture/opt/strata/bin/strata"
  printf '%s\n' "$var_lxc_pinned_commit" > "$HOME/.strata"
  previous_python="$fixture/opt/strata/venvs/venv.previous/bin/python"
  command mkdir -p "${previous_python%/python}"
  command ln -s "$(command -v python3)" "$previous_python"
  jq -n --arg source "$var_lxc_pinned_commit" --arg ggml "$var_lxc_ggml_commit" --arg python "$previous_python" \
    '{source_commit:$source,ggml_commit:$ggml,python:$python,cuda_arch:"89",cuda:"12.8",portable:true}' > "$fixture/opt/strata/runtime.json"
  command mkdir -p "$fixture/var/lib/strata/models"
  for path in etc/strata/config.json etc/strata/admission.json etc/systemd/system/strata.service opt/strata/bin/strata-launch opt/strata/bin/strata-engine-guard var/lib/strata/models/local.gguf; do
    printf administrator-owned > "$fixture/$path"
  done
  sha256sum "$fixture/etc/strata/"* "$fixture/etc/systemd/system/strata.service" "$fixture/opt/strata/bin/strata-"* "$fixture/var/lib/strata/models/local.gguf" > "$fixture/before"
  sha256sum "$fixture/opt/strata/bin/strata" "$fixture/opt/strata/runtime.json" "$HOME/.strata" > "$fixture/runtime-before"
  case "$scenario" in
    forced) export FORCE_DEPLOY=1 ;;
    inactive) export FORCE_DEPLOY=1 inactive=3 ;;
    source-pin) export var_lxc_pinned_commit=1111111111111111111111111111111111111111 ;;
    ggml-pin) export var_lxc_ggml_commit=2222222222222222222222222222222222222222 ;;
    arch) export var_lxc_cuda_arch=86 ;;
    clone-fail) export FORCE_DEPLOY=1 fail_clone=strata-ggml ;;
    head-mismatch) export FORCE_DEPLOY=1 wrong_head=strata-source ;;
    build-fail) export FORCE_DEPLOY=1 fail_build=1 STD=silent_stub ;;
    deploy-fail) export FORCE_DEPLOY=1 fail_deploy=1 ;;
    restart-fail) export FORCE_DEPLOY=1 fail_start=1 ;;
    malformed-runtime) printf '{invalid' > "$fixture/opt/strata/runtime.json" ;;
  esac
  run_hook update_script
  [[ ! -d "$fixture/opt/strata-builds" || -z "$(command find "$fixture/opt/strata-builds" -mindepth 1 -print -quit)" ]]
  [[ "$(command find "$fixture/opt/strata/venvs" -mindepth 1 -maxdepth 1 -type d | wc -l)" == 1 ]]
  sha256sum -c "$fixture/before" > /dev/null
  grep -qx jq "$fixture/dependencies"
  case "$scenario" in
    current)
      [[ "$rc" == 0 && ! -s "$fixture/clones" && ! -s "$fixture/services" ]]
      sha256sum -c "$fixture/runtime-before" > /dev/null
      ;;
    clone-fail | head-mismatch | build-fail)
      expected=250
      [[ "$scenario" != clone-fail ]] || expected=22
      [[ "$scenario" != build-fail ]] || expected=31
      [[ "$rc" == "$expected" && ! -s "$fixture/services" ]]
      sha256sum -c "$fixture/runtime-before" > /dev/null
      ;;
    malformed-runtime) [[ "$rc" == 250 && ! -s "$fixture/clones" && ! -s "$fixture/services" ]] ;;
    deploy-fail)
      [[ "$rc" == 28 && -x "$previous_python" ]]
      sha256sum -c "$fixture/runtime-before" > /dev/null
      ;;
    restart-fail)
      [[ "$rc" == 32 && ! -e "$previous_python" ]]
      python=$(jq -r .python "$fixture/opt/strata/runtime.json")
      [[ -x "$python" ]]
      run_hook update_script
      [[ "$rc" == 32 && ! -e "$python" ]]
      [[ "$(command find "$fixture/opt/strata/venvs" -mindepth 1 -maxdepth 1 -type d | wc -l)" == 1 ]]
      [[ -z "$(command find "$fixture/opt/strata-builds" -mindepth 1 -print -quit)" ]]
      ;;
    *)
      [[ "$rc" == 0 && "$(< "$HOME/.strata")" == "$var_lxc_pinned_commit" ]]
      jq -e --arg source "$var_lxc_pinned_commit" --arg ggml "$var_lxc_ggml_commit" --arg arch "$var_lxc_cuda_arch" \
        '.source_commit == $source and .ggml_commit == $ggml and .cuda_arch == $arch' "$fixture/opt/strata/runtime.json" > /dev/null
      if [[ "$scenario" == inactive ]]; then [[ ! -s "$fixture/services" ]]; else [[ "$(< "$fixture/services")" == $'stop strata\nstart strata' ]]; fi
      [[ ! -e "$previous_python" ]]
      python=$(jq -r .python "$fixture/opt/strata/runtime.json")
      [[ -x "$python" ]]
      "$python" -c 'import sys; assert sys.version_info.major == 3'
      # A second real rebuild must not accumulate old runtime environments.
      export FORCE_DEPLOY=1
      run_hook update_script
      [[ "$rc" == 0 && ! -e "$python" ]]
      [[ "$(command find "$fixture/opt/strata/venvs" -mindepth 1 -maxdepth 1 -type d | wc -l)" == 1 ]]
      [[ -z "$(command find "$fixture/opt/strata-builds" -mindepth 1 -print -quit)" ]]
      ;;
  esac
  printf 'PASS update %s preserves administrator files and expected runtime/service state\n' "$scenario"
done
