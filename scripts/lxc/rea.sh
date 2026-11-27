#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2026 scripts-underground.org
# Author: Alex Indigo (alexindigo)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/morluto/rea

# shellcheck disable=SC2034 # Used by the bootstrap.
APP="REA"
var_tags="${var_tags:-reverse-engineering;tools}"
var_hostname="${var_hostname:-rea}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-64}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"
var_lxc_rea_commit="${var_lxc_rea_commit:-ded199abcde611a0ba4739ecb536e0ede0075670}"
var_lxc_rea_version="${var_lxc_rea_version:-6.4.0}"
var_lxc_node_version="${var_lxc_node_version:-24.18.0}"
var_lxc_npm_version="${var_lxc_npm_version:-11.16.0}"
var_lxc_ghidra_version="${var_lxc_ghidra_version:-12.1.4}"
var_lxc_ghidra_date="${var_lxc_ghidra_date:-20260921}"
var_lxc_jadx_version="${var_lxc_jadx_version:-0.7.1}"
var_lxc_apktool_version="${var_lxc_apktool_version:-3.0.3}"
var_lxc_node_sha256="${var_lxc_node_sha256:-55aa7153f9d88f28d765fcdad5ae6945b5c0f98a36881703817e4c450fa76742}"
var_lxc_ghidra_sha256="${var_lxc_ghidra_sha256:-ddac49f903da9d5bac833e5cc79395098b9c33cfd3279be5f31bd00387d2d4db}"
var_lxc_jadx_sha256="${var_lxc_jadx_sha256:-6e5eacf500b64292bfb73c49797c1958f6ee44646e43e868039ae7feb573ff75}"
var_lxc_apktool_sha256="${var_lxc_apktool_sha256:-dbf930b076c6b9be08d57c449cacefc3bdd6b71ebd59b3066fc0e1f5b14f9423}"

function install_script() {
  if [[ "$OS_TYPE" != debian || "${OS_VERSION%%.*}" != 13 || "$(get_system_arch)" != amd64 || "$(uname -m)" != x86_64 ]]; then
    msg_error "REA requires Debian 13 on amd64"
    return 65
  fi

  msg_info "Installing Dependencies"
  $STD pkg_install openjdk-21-jdk-headless unzip zip xz-utils curl ca-certificates openssh-server procps python3 file git build-essential || return "$?"
  msg_ok "Installed Dependencies"

  if ! id rea > /dev/null 2>&1; then
    useradd --create-home --user-group --shell /bin/bash rea || return "$?"
  fi
  install -d -m 0755 /srv/rea /usr/local/lib || return "$?"
  install -d -o rea -g rea -m 0750 /srv/rea/jobs /srv/rea/cache /srv/rea/tmp || return "$?"
  install -d -o rea -g rea -m 0700 /home/rea/.ssh || return "$?"

  if [[ ! -e /srv/rea/environment.sh && ! -L /srv/rea/environment.sh ]]; then
    cat << 'ENVIRONMENT' > /srv/rea/environment.sh || return "$?"
# Operator settings; the updater does not replace this file.
export GHIDRA_HEADLESS_MAXMEM=1G
export REA_JADX_HEAP_MIB=1024
ENVIRONMENT
  fi

  # The two generated hooks share one application-specific deployment recipe.
  # The root-installed recipe also identifies an installation independently of
  # its active generation, which may be missing after an interrupted deploy.
  cat << 'DEPLOY' > /usr/local/lib/rea-deploy.sh || return "$?"
# shellcheck shell=bash
# Sourced by the generated hooks with their framework functions and pins.
rea_pins() {
  printf '%s\n' "rea=$var_lxc_rea_version" "commit=$var_lxc_rea_commit" \
    "node=$var_lxc_node_version $var_lxc_node_sha256" "npm=$var_lxc_npm_version" \
    "ghidra=$var_lxc_ghidra_version $var_lxc_ghidra_date $var_lxc_ghidra_sha256" \
    "jadx=$var_lxc_jadx_version $var_lxc_jadx_sha256" "apktool=$var_lxc_apktool_version $var_lxc_apktool_sha256"
}

rea_download() {
  local url=$1 path=$2 digest=$3
  # Release deploy helpers do not accept a required caller checksum before extraction.
  $STD curl_with_retry "$url" "$path" '--proto =https --proto-redir =https' || return "$?"
  printf '%s  %s\n' "$digest" "$path" | $STD sha256sum --strict --check
}

rea_deploy() (
  local stage src node ghidra jadx apktool pin
  local base=/srv/rea
  # These guards also apply when a caller (including the quiet wrapper) tests
  # status in a conditional, where Bash disables errexit inside functions.
  install -d -m 0755 "$base/releases" "$base/bin" || return "$?"
  stage=$(mktemp -d "$base/releases/rea.XXXXXXXX") || return "$?"
  # Once current points to this directory, cleanup no longer owns it.
  trap 'if [[ ! "$base/current" -ef "$stage" ]]; then rm -rf -- "$stage"; fi' EXIT
  chmod 0755 "$stage" || return "$?"
  src="$stage/source"
  node="node-v${var_lxc_node_version}-linux-x64"
  ghidra="ghidra_${var_lxc_ghidra_version}_PUBLIC"
  jadx="jadx-headless-mcp-${var_lxc_jadx_version}-all.jar"
  apktool="apktool_${var_lxc_apktool_version}.jar"
  install -d "$stage/bin" "$stage/tools" || return "$?"
  install -d -o rea -g rea "$src" "$stage/runtime" "$stage/pack" || return "$?"

  msg_info "Preparing pinned Node.js and REA source"
  rea_download "https://nodejs.org/dist/v${var_lxc_node_version}/${node}.tar.xz" "$stage/node.tar.xz" "$var_lxc_node_sha256" || return "$?"
  $STD tar -xJf "$stage/node.tar.xz" -C "$stage/tools" || return "$?"
  # Only the fresh private Node prefix can receive the npm install.
  chown -R rea:rea "$stage/tools/$node" || return "$?"
  $STD runuser -u rea -- env PATH="$stage/tools/$node/bin:/usr/bin:/bin" \
    TMPDIR="$base/tmp" npm_config_cache="$base/cache/npm" HUSKY=0 \
    bash -euc '
      prefix=$1 src=$2 commit=$3 version=$4 npm_version=$5 node_version=$6 stage=$7
      [[ $(node --version) == "v$node_version" ]]
      if [[ $(npm --version) != "$npm_version" ]]; then
        npm install --global --ignore-scripts --prefix "$prefix" "npm@$npm_version"
      fi
      [[ $(npm --version) == "$npm_version" ]]
      cd "$src"
      git init --quiet
      git fetch --quiet --depth=1 https://github.com/morluto/rea.git "$commit"
      git checkout --quiet --detach FETCH_HEAD
      [[ $(git rev-parse HEAD) == "$commit" ]]
      [[ $(node -p "require(\"./package.json\").version") == "$version" ]]
      printf "REA source checked: %s; Node=%s; npm=%s\n" "$commit" "$node_version" "$npm_version"
      npm ci
      npm run build:cached
      npm pack --ignore-scripts --pack-destination "$stage/pack"
      npm install --prefix "$stage/runtime" --omit=dev --ignore-scripts "$stage/pack/rea-agents-$version.tgz"
      [[ $(node -p "require(process.argv[1]).version" "$stage/runtime/node_modules/rea-agents/package.json") == "$version" ]]
    ' bash "$stage/tools/$node" "$src" "$var_lxc_rea_commit" "$var_lxc_rea_version" "$var_lxc_npm_version" "$var_lxc_node_version" "$stage" || return "$?"
  msg_ok "Built REA $var_lxc_rea_version from the pinned source"

  msg_info "Preparing pinned Ghidra, JADX and Apktool"
  rea_download "https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_${var_lxc_ghidra_version}_build/${ghidra}_${var_lxc_ghidra_date}.zip" "$stage/ghidra.zip" "$var_lxc_ghidra_sha256" || return "$?"
  $STD unzip -q "$stage/ghidra.zip" -d "$stage/tools" || return "$?"
  rea_download "https://github.com/1013503897/jadx-headless-mcp/releases/download/v${var_lxc_jadx_version}/$jadx" "$stage/tools/$jadx" "$var_lxc_jadx_sha256" || return "$?"
  rea_download "https://github.com/iBotPeaches/Apktool/releases/download/v${var_lxc_apktool_version}/$apktool" "$stage/tools/$apktool" "$var_lxc_apktool_sha256" || return "$?"

  cat <<DEFAULTS > "$stage/defaults.sh" || return "$?"
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
export GHIDRA_INSTALL_DIR="\$release/tools/$ghidra"
export GHIDRA_HEADLESS_MAXMEM=1G
export REA_ANALYSIS_PROVIDER=ghidra
export REA_JADX_MCP_JAR="\$release/tools/$jadx"
export REA_JADX_HEAP_MIB=1024
export REA_APKTOOL_COMMAND="\$release/bin/apktool"
export REA_ROOT="\$release/runtime/node_modules/rea-agents"
export TMPDIR=/srv/rea/tmp
export XDG_CACHE_HOME=/srv/rea/cache
export XDG_DATA_HOME=/srv/rea/cache/xdg-data
export REA_GHIDRA_STARTUP_TIMEOUT_MS=330000
export PATH="\$release/tools/$node/bin:/usr/local/bin:/usr/bin:/bin"
DEFAULTS
  cat <<'LAUNCH_REA' > "$stage/bin/rea" || return "$?"
#!/bin/sh
set -eu
test "$(id -un)" = rea || { echo 'Run this launcher as rea.' >&2; exit 65; }
release=$(dirname "$(dirname "$(readlink -f -- "$0")")")
. "$release/defaults.sh"
. /srv/rea/environment.sh
exec node "$REA_ROOT/scripts/rea.mjs" "$@"
LAUNCH_REA
  cat <<LAUNCH_APKTOOL > "$stage/bin/apktool" || return "$?"
#!/bin/sh
set -eu
test "\$(id -un)" = rea || { echo 'Run this launcher as rea.' >&2; exit 65; }
release=\$(dirname "\$(dirname "\$(readlink -f -- "\$0")")")
export JAVA_HOME=\${JAVA_HOME:-/usr/lib/jvm/java-21-openjdk-amd64}
exec "\$JAVA_HOME/bin/java" -jar "\$release/tools/$apktool" "\$@"
LAUNCH_APKTOOL
  chmod 0755 "$stage/bin/rea" "$stage/bin/apktool" || return "$?"

  msg_info "Checking staged REA and Ghidra as rea"
  $STD runuser -u rea -- "$stage/bin/rea" --help || return "$?"
  # Preserve JSON even if the CLI reports unrelated unsupported providers.
  local doctor_status=0
  runuser -u rea -- "$stage/bin/rea" doctor --provider ghidra --json > "$stage/doctor.json" || doctor_status=$?
  if ! jq -e --arg version "$var_lxc_ghidra_version" '
    ([.providerInspections[] | select(.id == "ghidra" and .available == true and .providerVersion == $version)] | length == 1)
    and ([.checks[] | select(.name | startswith("ghidra-"))] as $checks
      | all(["ghidra-installation", "ghidra-version", "ghidra-headless", "ghidra-java"][];
          . as $name | any($checks[]; .name == $name))
      and all($checks[]; .ok == true))
  ' "$stage/doctor.json" >/dev/null; then
    cat "$stage/doctor.json" >&2
    msg_error "Staged Ghidra checks failed (doctor exit $doctor_status)"
    return 1
  fi

  rea_pins > "$stage/pins" || return "$?"
  rm -rf -- "$src" "$stage/pack" || return "$?"
  rm -f -- "$stage/node.tar.xz" "$stage/ghidra.zip" || return "$?"
  # A single pointer switches the engine/CLI set. Retain previous releases for
  # sessions that are still using them. Never put user data under releases/.
  pin=${stage##*/}
  ln -s "releases/$pin" "$stage/next" || return "$?"
  ln -sfnT ../current/bin/rea "$base/bin/rea" || return "$?"
  ln -sfnT ../current/bin/apktool "$base/bin/apktool" || return "$?"
  mv -Tf -- "$stage/next" "$base/current" || return "$?"
  msg_ok "Installed REA $var_lxc_rea_version and pinned engines"
)
DEPLOY
  # shellcheck source=/dev/null
  source /usr/local/lib/rea-deploy.sh || return "$?"
  rea_deploy || return "$?"

  $STD systemctl enable --now ssh
}

function post_install_script() {
  printf 'Add your SSH public key to /home/rea/.ssh/authorized_keys and verify the container host key.\n'
  printf 'MCP over SSH: ssh -T rea@<container-address> /srv/rea/bin/rea mcp\n'
}

function update_script() {
  if [[ "$OS_TYPE" != debian || "${OS_VERSION%%.*}" != 13 || "$(get_system_arch)" != amd64 || "$(uname -m)" != x86_64 ]]; then
    msg_error "REA requires Debian 13 on amd64"
    return 65
  fi
  if [[ ! -f /usr/local/lib/rea-deploy.sh ]]; then
    msg_error "REA installation recipe not found; install REA first"
    return 1
  fi
  if [[ ! -f /srv/rea/environment.sh ]] || ! id rea > /dev/null 2>&1; then
    msg_error "REA installation is missing its operator environment or account"
    return 1
  fi
  # shellcheck source=/dev/null
  source /usr/local/lib/rea-deploy.sh || return "$?"
  if [[ "${UPDATE_FORCE:-0}" != 1 ]]; then
    if [[ ! -f /srv/rea/current/pins ]]; then
      msg_error "REA active generation is incomplete; run update --clean to repair it"
      return 1
    fi
    local installed selected
    installed=$(cat /srv/rea/current/pins) || return "$?"
    selected=$(rea_pins) || return "$?"
    if [[ "$installed" == "$selected" ]]; then
      $STD runuser -u rea -- /srv/rea/bin/rea --help || return "$?"
      $STD runuser -u rea -- /srv/rea/bin/apktool --version || return "$?"
      msg_ok "REA $var_lxc_rea_version is already installed at the selected pins"
      return 0
    fi
  fi
  check_container_storage || return "$?"
  rea_deploy
}

# shellcheck source=/dev/null
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc") --script-id rea -- "$@"
