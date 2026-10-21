#!/usr/bin/env bash
# Offline release designation, backend selection and update preservation checks.
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
cp() { scratch_paths "$@" && command cp "$@"; }
rm() { scratch_paths "$@" && command rm "$@"; }
ln() { scratch_paths "$@" && command ln "$@"; }
msg_info() { :; }
msg_ok() { :; }
msg_error() { :; }
header_info() { :; }
check_container_storage() { :; }
check_container_resources() { :; }
id() { return 1; }
useradd() { :; }
chown() { :; }
ldconfig() { printf 'ldconfig\n' >> "$fixture/packages"; }
apt() { printf '%s\n' "$*" >> "$fixture/packages"; }
install() {
  local -a paths=()
  while (($#)); do
    case "$1" in
      -d) shift ;;
      -m | -o | -g) shift 2 ;;
      *)
        paths+=("$1")
        shift
        ;;
    esac
  done
  scratch_paths "${paths[@]}"
  command mkdir -p "${paths[@]}"
}
find() {
  scratch_paths "$1"
  if [[ "$1" == "$fixture/opt/intel/oneapi" ]]; then
    printf '%s/intel/runtime/lib\n' "$fixture/opt"
  else
    command find "$@"
  fi
}
setup_deb822_repo() { printf '%s\n' "$*" > "$fixture/repo"; }
setup_hwaccel() { export HWACCEL_VENDOR="$vendor"; }
get_system_arch() { printf '%s\n' "$test_arch"; }
get_latest_github_release() {
  [[ "$1" == ggml-org/llama.cpp && "$2" == false ]]
  printf 'v0.7.0\n'
}
check_for_gh_release() {
  [[ "$1" == llama-cpp && "$2" == ggml-org/llama.cpp ]]
  printf '%s\n' "$3" > "$fixture/pin"
  export CHECK_UPDATE_RELEASE=v0.7.0
  return "$check_status"
}
systemctl() {
  [[ "$1" != is-active ]] || return "$inactive"
  printf '%s\n' "$*" >> "$fixture/services"
}
fetch_and_deploy_gh_release() {
  scratch_paths "$5" "$HOME"
  [[ "$HOME" != "$fixture/home" && "$2" == ggml-org/llama.cpp && "$var_appversion" == "$4" && "$FORCE_DEPLOY" == 1 ]]
  printf '%s|%s|%s|%s\n' "$1" "$3" "$4" "$6" >> "$fixture/fetch"
  [[ "$fail_asset" != "$1" ]] || return 250
  command mkdir -p "$5"
  case "$1" in
    llama-cpp-designation)
      [[ "$3" == singlefile && "$6" == nightly-tag.txt && "$USE_ORIGINAL_FILENAME" == true ]]
      printf '%s\n' "$descriptor" > "$5/nightly-tag.txt"
      printf '%s' "$stable_marker" > "$HOME/.$1"
      ;;
    llama-cpp)
      [[ "$3" == prebuild && "$4" == b11669 && "$CLEAN_INSTALL" == 1 ]]
      command chmod 700 "$5"
      printf hidden-runtime > "$5/.release"
      printf new-binary > "$5/llama-server"
      command chmod 755 "$5/llama-server"
      printf new-library > "$5/libllama.so"
      printf '%s' "$binary_marker" > "$HOME/.$1"
      ;;
    llama-cpp-cudart)
      [[ "$3" == prebuild && "$4" == b11669 && "$CLEAN_INSTALL" == 0 ]]
      command touch "$5/libcudart.so.12" "$5/libcublas.so.12" "$5/libcublasLt.so.12"
      printf '%s' "$binary_marker" > "$HOME/.$1"
      ;;
    *) return 98 ;;
  esac
}
export -f scratch_paths cp rm ln msg_info msg_ok msg_error header_info check_container_storage check_container_resources
export -f id useradd chown ldconfig apt install find setup_deb822_repo setup_hwaccel get_system_arch
export -f check_for_gh_release systemctl fetch_and_deploy_gh_release
export -f get_latest_github_release

setup_case() {
  fixture="$work/$1"
  command mkdir -p "$fixture"/{home,stages,opt/llama-cpp,etc/systemd/system,etc/ld.so.conf.d,var/lib/llama-cpp/models,var/cache/llama-cpp,usr/local/bin}
  sed -n '/^function install_script() {/,/^}/p; /^function update_script() {/,/^}/p' "$ROOT/scripts/lxc/llama-cpp.sh" |
    # Rewrite each original root once; the fixture prefix can itself contain /var.
    sed -E "s#/(opt|etc|var|usr)/#$fixture/\1/#g" > "$fixture/hooks"
  # Reject any unmapped absolute system root before invoking either hook.
  if sed -e "s#$work/#SCRATCH/#g" -e 's#/dev/null#NULL#g' -e 's#"\$[[:alnum:]_]*"/#VARIABLE/#g' "$fixture/hooks" |
    grep -nE "(^|[[:space:]=\"'(])/[[:alnum:]_]"; then
    exit 99
  fi
  export fixture HOME="$fixture/home" TMPDIR="$fixture/stages" STD=''
  export var_lxc_backend=auto var_lxc_release=latest var_lxc_models_max=4 var_lxc_port=80
  export vendor=none test_arch=amd64 descriptor=b11669 stable_marker=0.7.0 binary_marker=b11669
  export fail_asset=none check_status=0 inactive=0
  unset var_appversion
  : > "$fixture/services"
  : > "$fixture/packages"
  : > "$fixture/fetch"
}
run_hook() {
  rc=0
  export hook=$1
  before_metadata=$(stat -c '%a:%u:%g' "$fixture/opt/llama-cpp")
  bash -euo pipefail -c 'source "$fixture/hooks"; "$hook"' > "$fixture/output" 2>&1 || rc=$?
  after_metadata=$(stat -c '%a:%u:%g' "$fixture/opt/llama-cpp")
  [[ "$after_metadata" == "$before_metadata" ]] || {
    printf 'FAIL %s target metadata=%s expected=%s\n' "$hook" "$after_metadata" "$before_metadata"
    exit 1
  }
}

for spec in 'none amd64 cpu' 'intel amd64 vulkan' 'amd arm64 vulkan' 'nvidia amd64 cuda' 'nvidia arm64 cpu'; do
  read -r wanted_vendor wanted_arch expected <<< "$spec"
  setup_case "auto-$wanted_vendor-$wanted_arch"
  export vendor=$wanted_vendor test_arch=$wanted_arch
  run_hook install_script
  [[ "$rc" == 0 && "$(< "$fixture/var/lib/llama-cpp/.backend")" == "$expected" ]]
  [[ "$(< "$HOME/.llama-cpp")" == 0.7.0 && -L "$fixture/usr/local/bin/llama-server" ]]
  [[ "$(< "$fixture/opt/llama-cpp/.release")" == hidden-runtime ]]
  grep -qx LLAMA_ARG_PORT=80 "$fixture/etc/llama-cpp.env"
  grep -qx LLAMA_ARG_MODELS_MAX=4 "$fixture/etc/llama-cpp.env"
  grep -qx LLAMA_ARG_MODELS_AUTOLOAD=true "$fixture/etc/llama-cpp.env"
  [[ -z "$(command find "$fixture/var/lib/llama-cpp/models" -type f -print)" ]]
  printf 'PASS auto %s %s selects %s and creates an empty port-80 four-instance router\n' "$vendor" "$test_arch" "$expected"
done

for backend in cpu vulkan cuda sycl; do
  setup_case "explicit-$backend"
  export var_lxc_backend=$backend var_lxc_release=v0.7.0
  run_hook install_script
  [[ "$rc" == 0 ]]
  case "$backend" in
    cpu) suffix=ubuntu-x64 ;;
    vulkan) suffix=ubuntu-vulkan-x64 ;;
    cuda) suffix=ubuntu-cuda-12.8-x64 ;;
    sycl)
      suffix=ubuntu-sycl-fp16-x64
      grep -q 'intel-oneapi-compiler-dpcpp-cpp-runtime-2026.1.*intel-oneapi-mkl-sycl-blas-2026.1.*intel-oneapi-dnnl-2026.0' "$fixture/packages"
      grep -q 'https://apt.repos.intel.com/oneapi all main amd64' "$fixture/repo"
      [[ -s "$fixture/etc/ld.so.conf.d/llama-cpp-sycl.conf" ]]
      ;;
  esac
  grep -Fxq "llama-cpp|prebuild|b11669|llama-b11669-bin-$suffix.tar.gz" "$fixture/fetch"
  printf 'PASS explicit %s uses its designated binary asset and runtime\n' "$backend"
done

for backend in cuda sycl unknown; do
  setup_case "unsupported-$backend"
  export var_lxc_backend=$backend test_arch=arm64
  run_hook install_script
  [[ "$rc" == 65 && ! -s "$fixture/fetch" ]]
done
printf 'PASS unsupported backend/architecture combinations fail before downloading\n'

for pin in latest v0.7.0; do
  setup_case "install-mismatched-$pin"
  export var_lxc_release=$pin stable_marker=0.6.0
  run_hook install_script
  [[ "$rc" == 250 && ! -e "$fixture/opt/llama-cpp/llama-server" && ! -s "$fixture/services" ]]
done
printf 'PASS latest and pinned installs reject a descriptor from another stable release\n'

for scenario in success inactive current check-error descriptor-fail binary-fail cudart-fail invalid-descriptor stable-mismatch binary-mismatch; do
  setup_case "update-$scenario"
  printf old-binary > "$fixture/opt/llama-cpp/llama-server"
  chmod 755 "$fixture/opt/llama-cpp/llama-server"
  printf cuda > "$fixture/var/lib/llama-cpp/.backend"
  printf custom > "$fixture/etc/llama-cpp.env"
  printf custom-preset > "$fixture/etc/llama-cpp-models.ini"
  printf custom-unit > "$fixture/etc/systemd/system/llama-cpp.service"
  printf model-data > "$fixture/var/lib/llama-cpp/models/local.gguf"
  printf 0.6.0 > "$HOME/.llama-cpp"
  export var_appversion=v0.7.0
  case "$scenario" in
    inactive) export inactive=3 ;;
    current) export check_status=1 ;;
    check-error) export check_status=22 ;;
    descriptor-fail) export fail_asset=llama-cpp-designation ;;
    binary-fail) export fail_asset=llama-cpp ;;
    cudart-fail) export fail_asset=llama-cpp-cudart ;;
    invalid-descriptor) export descriptor=invalid ;;
    stable-mismatch) export stable_marker=0.6.0 ;;
    binary-mismatch) export binary_marker=b11111 ;;
  esac
  sha256sum "$fixture/etc/llama-cpp.env" "$fixture/etc/llama-cpp-models.ini" "$fixture/etc/systemd/system/llama-cpp.service" "$fixture/var/lib/llama-cpp/models/local.gguf" > "$fixture/before"
  run_hook update_script
  sha256sum -c "$fixture/before" > /dev/null
  case "$scenario" in
    success | inactive)
      [[ "$rc" == 0 && "$(< "$HOME/.llama-cpp")" == 0.7.0 && "$(< "$fixture/opt/llama-cpp/llama-server")" == new-binary ]]
      [[ "$(< "$fixture/opt/llama-cpp/.release")" == hidden-runtime ]]
      [[ "$(< "$fixture/pin")" == v0.7.0 ]]
      if [[ "$scenario" == success ]]; then [[ "$(< "$fixture/services")" == $'stop llama-cpp\nstart llama-cpp' ]]; else [[ ! -s "$fixture/services" ]]; fi
      ;;
    *)
      expected_rc=250
      [[ "$scenario" != current ]] || expected_rc=0
      [[ "$scenario" != check-error ]] || expected_rc=22
      [[ "$rc" == "$expected_rc" && ! -s "$fixture/services" && "$(< "$HOME/.llama-cpp")" == 0.6.0 && "$(< "$fixture/opt/llama-cpp/llama-server")" == old-binary ]]
      ;;
  esac
  printf 'PASS update %s preserves configuration/model data and expected runtime/service state\n' "$scenario"
done
