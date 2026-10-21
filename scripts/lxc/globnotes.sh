#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2026 scripts-underground.org
# Author: Alex Indigo (alexindigo)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/alexindigo/globnotes

# shellcheck disable=SC2034
APP="Globnotes"
var_tags="${var_tags:-notes;markdown}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_lxc_globnotes_index_path="${var_lxc_globnotes_index_path:-${GLOBNOTES_INDEX_PATH:-}}"
# Host install input survives cold transport, but is not an update policy.
var_lxc_globnotes_initial_release="${var_lxc_globnotes_initial_release:-${var_appversion:-latest}}"

function install_script() {
  # These definitions deliberately live inside each hook: only that hook is
  # transported by declare -f. No script-global helper crosses the bundle.
  gn_path() {
    local LC_ALL=C
    [[ "$1" == /* && "$1" != *[[:cntrl:]]* ]] || return 65
    printf '%s' "$1" | iconv -f UTF-8 -t UTF-8 > /dev/null || return 65
    realpath -m -- "$1"
  }
  gn_separate() {
    [[ "$1" != "$2" && "$1" != "$2/"* && "$2" != "$1/"* ]]
  }
  gn_roots() {
    local notes=$1 state=$2 cache=$3 fixed
    [[ "$notes" != / && "$state" != / && "$cache" != / ]] || return 65
    gn_separate "$notes" "$cache" && gn_separate "$state" "$cache" || return 65
    if [[ "$state" != "$notes/.globnotes" ]]; then gn_separate "$notes" "$state" || return 65; fi
    for fixed in /opt/globnotes /opt/globnotes-builds /etc/globnotes /var/lib/globnotes/tmp; do
      gn_separate "$notes" "$fixed" && gn_separate "$state" "$fixed" && gn_separate "$cache" "$fixed" || return 65
    done
    for fixed in "$notes" "$state"; do
      [[ "$fixed" != "$cache.candidate."* && "$fixed" != "$cache.retired."* ]] || return 65
    done
  }
  gn_env_line() {
    local value=$2
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//\$/\\\$}
    value=${value//\`/\\\`}
    printf '%s="%s"\n' "$1" "$value"
  }
  gn_directory() {
    local path=$1
    if [[ ! -e "$path" ]]; then
      # Create only missing components. Existing mounts and their metadata belong
      # to the operator, even when they are not writable by this account.
      local parent
      parent=$(dirname -- "$path") || return $?
      [[ -d "$parent" ]] || gn_directory "$parent" || return $?
      mkdir -m 750 -- "$path" || return $?
      chown globnotes:globnotes -- "$path" || return $?
    fi
    runuser -u globnotes -- test -r "$path" && runuser -u globnotes -- test -w "$path" && runuser -u globnotes -- test -x "$path" || {
      msg_error "Give the globnotes account read/write/traverse access to $path inside the LXC; existing mount ownership was preserved."
      return 77
    }
  }
  gn_revision() {
    local tag=$1 encoded response raw_ref object kind sha i seen='|'
    encoded=$(jq -nr --arg tag "$tag" '$tag|@uri') || return $?
    local -a headers=(-H 'Accept: application/vnd.github+json')
    [[ -z "${GITHUB_TOKEN:-}" ]] || headers+=(-H "Authorization: Bearer $GITHUB_TOKEN")
    response=$(curl -fsSL --connect-timeout 15 --max-time 60 "${headers[@]}" "https://api.github.com/repos/alexindigo/globnotes/git/ref/tags/$encoded") || return $?
    raw_ref=$(jq -er .ref <<< "$response") || return 250
    [[ "$raw_ref" == "refs/tags/$tag" ]] || return 250
    for ((i = 0; i < 12; i++)); do
      object=$(jq -ce '.object | select(type=="object")' <<< "$response") || return 250
      kind=$(jq -er .type <<< "$object") || return 250
      sha=$(jq -er .sha <<< "$object") || return 250
      [[ "$sha" =~ ^[0-9a-f]{40}$ && "$seen" != *"|$sha|"* ]] || return 250
      [[ "$kind" != commit ]] || {
        printf '%s\n' "$sha" || return $?
        return 0
      }
      [[ "$kind" == tag ]] || return 250
      seen+="$sha|"
      response=$(curl -fsSL --connect-timeout 15 --max-time 60 "${headers[@]}" "https://api.github.com/repos/alexindigo/globnotes/git/tags/$sha") || return $?
    done
    return 250
  }
  gn_release() {
    local file=$1 tag=$2
    jq -e --arg tag "$tag" '
      (.id|type)=="number" and .id>0 and (.id|floor)==.id and
      (.published_at|type)=="string" and (.published_at|length)>0 and
      .url==("https://api.github.com/repos/alexindigo/globnotes/releases/"+(.id|tostring)) and
      .draft==false and .prerelease==false and .tag_name==$tag' "$file" > /dev/null || return 250
    [[ "$tag" =~ ^v?[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || return 250
  }
  gn_download() {
    local selected=$1 tag revision again pin line build_pin='' runtime_pin='' arch actual
    _gh_release_json alexindigo/globnotes "$selected" '' "$stage/selected.json" || return $?
    tag=$(jq -er .tag_name "$stage/selected.json") || return 250
    gn_release "$stage/selected.json" "$tag" || return $?
    revision=$(gn_revision "$tag") || return $?
    # Both helper marker outputs belong to this operation's private HOME.
    HOME="$stage/helper-home" var_appversion='' fetch_and_deploy_gh_release globnotes alexindigo/globnotes tarball "$tag" "$stage/source" '' '' "$stage/deployed.json" || return $?
    gn_release "$stage/deployed.json" "$tag" || return $?
    again=$(gn_revision "$tag") || return $?
    [[ "$revision" == "$again" && $(< "$stage/source/VERSION") == "${tag#v}" ]] || return 250
    [[ ! -e "$stage/source/runtime" && ! -L "$stage/source/runtime" ]] || return 65
    while IFS= read -r line || [[ -n "$line" ]]; do
      if [[ "$line" == FROM*denoland/deno:* ]]; then
        if [[ "$line" =~ ^FROM[[:space:]]+--platform=\$BUILDPLATFORM[[:space:]]+denoland/deno:([0-9]+\.[0-9]+\.[0-9]+)[[:space:]]+AS[[:space:]]+build$ && -z "$build_pin" ]]; then
          build_pin=${BASH_REMATCH[1]}
        elif [[ "$line" =~ ^FROM[[:space:]]+denoland/deno:alpine-([0-9]+\.[0-9]+\.[0-9]+)$ && -z "$runtime_pin" ]]; then
          runtime_pin=${BASH_REMATCH[1]}
        else return 65; fi
      fi
    done < "$stage/source/Dockerfile"
    [[ -n "$build_pin" && "$build_pin" == "$runtime_pin" ]] || return 65
    pin=$build_pin
    arch=$(get_system_arch dpkg x86_64 aarch64) || return $?
    [[ "$arch" == x86_64 || "$arch" == aarch64 ]] || return 65
    HOME="$stage/helper-home" var_appversion='' fetch_and_deploy_gh_release deno denoland/deno prebuild "v$pin" "$stage/source/runtime" "deno-$arch-unknown-linux-gnu.zip" || return $?
    chmod 755 "$stage/source/runtime/deno" || return $?
    actual=$("$stage/source/runtime/deno" --version) || return $?
    [[ "${actual%%$'\n'*}" == "deno $pin (stable)" || "${actual%%$'\n'*}" == "deno $pin (stable, release, $arch-unknown-linux-gnu)" ]] || return 250
    gn_env_line GLOBNOTES_REVISION "$revision" > "$stage/source/runtime/release.env" || return $?
    release_version=${tag#v}
    release_revision=$revision
  }
  gn_build() {
    local released_lock_hash after_lock_hash
    released_lock_hash=$(sha256sum "$stage/source/deno.lock") || return $?
    released_lock_hash=${released_lock_hash%% *}
    chown -R globnotes:globnotes -- "$stage/source" || return $?
    chmod 755 "$stage" || return $?
    install -d -o globnotes -g globnotes -m 750 "$stage/build-home" "$stage/build-tmp" || return $?
    (
      cd "$stage/source" || return $?
      $STD runuser -u globnotes -- env -i PATH="$stage/source/runtime:/usr/bin:/bin" HOME="$stage/build-home" TMPDIR="$stage/build-tmp" DENO_DIR="$candidate_cache" deno install --frozen || return $?
      $STD runuser -u globnotes -- env -i PATH="$stage/source/runtime:/usr/bin:/bin" HOME="$stage/build-home" TMPDIR="$stage/build-tmp" DENO_DIR="$candidate_cache" deno task build:client || return $?
      $STD runuser -u globnotes -- env -i PATH="$stage/source/runtime:/usr/bin:/bin" HOME="$stage/build-home" TMPDIR="$stage/build-tmp" DENO_DIR="$candidate_cache" deno cache server/main.ts || return $?
    ) || return $?
    after_lock_hash=$(sha256sum "$stage/source/deno.lock") || return $?
    [[ "${after_lock_hash%% *}" == "$released_lock_hash" ]] || return 250
    [[ -s "$stage/source/client/dist/index.html" ]] || return 250
    chown -R root:root -- "$stage/source" || return $?
    # Deno's auto node_modules and startup HTML stamping are writable; source,
    # runtime and notices remain root-owned. Cache is independently writable.
    chown -R globnotes:globnotes -- "$stage/source/node_modules" || return $?
    chown globnotes:globnotes -- "$stage/source/client/dist/index.html" || return $?
    chmod -R a+rX -- "$stage/source" || return $?
    # Deno atomically records approved dynamic imports in generation-owned
    # metadata. The published lock and application root stay read-only.
    install -d -o globnotes -g globnotes -m 750 "$stage/source/runtime/dependency-lock" || return $?
    install -o globnotes -g globnotes -m 600 "$stage/source/deno.lock" "$stage/source/runtime/dependency-lock/deno.lock" || return $?
    printf '%s  deno.lock\n' "$released_lock_hash" > "$stage/source/runtime/released-lock.sha256" || return $?
    chmod 644 "$stage/source/runtime/released-lock.sha256" || return $?
  }
  gn_health() {
    local host=$1 port=$2 prefix=$3 body i
    case "$host" in 0.0.0.0) host=127.0.0.1 ;; ::) host='[::1]' ;; *:*) host="[$host]" ;; esac
    for ((i = 0; i < 30; i++)); do
      if body=$(curl -fsS --connect-timeout 2 --max-time 5 "http://$host:$port$prefix/_/api/config"); then
        if jq -e --arg version "$release_version" --arg revision "$release_revision" '.version==$version and .revision==$revision' <<< "$body" > /dev/null; then return 0; fi
      fi
      sleep 1 || return $?
    done
    return 22
  }

  local notes state cache=/var/cache/globnotes stage candidate_cache marker_stage='' release_version release_revision status=0
  notes=$(gn_path /var/lib/globnotes/notes) || return $?
  state=$(gn_path "${var_lxc_globnotes_index_path:-$notes/.globnotes}") || return $?
  gn_roots "$notes" "$state" "$cache" || {
    msg_error 'State, notes, cache and installer paths must not overlap'
    return 65
  }
  [[ ! -e /opt/globnotes && ! -L /opt/globnotes && ! -e /etc/globnotes/env ]] || return 65
  $STD apt install -y --no-install-recommends ca-certificates curl jq unzip || return $?
  if ! id globnotes > /dev/null 2>&1; then
    useradd --system --user-group --home-dir /var/lib/globnotes --no-create-home --shell /usr/sbin/nologin globnotes || return $?
  fi
  gn_directory "$notes" || return $?
  gn_directory "$state" || return $?
  gn_directory "$cache" || return $?
  gn_directory /var/lib/globnotes/tmp || return $?
  install -d -m 755 /opt/globnotes-builds || return $?
  stage=$(mktemp -d /opt/globnotes-builds/install.XXXXXX) || return $?
  mkdir -m 700 "$stage/helper-home" || return $?
  candidate_cache=$cache
  gn_download "${var_appversion:-$var_lxc_globnotes_initial_release}" || status=$?
  if [[ "$status" == 0 ]]; then gn_build || status=$?; fi
  if [[ "$status" == 0 ]]; then
    install -d -m 750 -o root -g globnotes /etc/globnotes || return $?
    {
      gn_env_line GLOBNOTES_HOST 0.0.0.0 || return $?
      gn_env_line GLOBNOTES_PORT 80 || return $?
      gn_env_line GLOBNOTES_PATH "$notes" || return $?
      gn_env_line DENO_DIR "$cache" || return $?
      gn_env_line TMPDIR /var/lib/globnotes/tmp || return $?
      gn_env_line HOME /var/lib/globnotes || return $?
      [[ -z "$var_lxc_globnotes_index_path" ]] || gn_env_line GLOBNOTES_INDEX_PATH "$state" || return $?
    } > /etc/globnotes/env || return $?
    chmod 640 /etc/globnotes/env || return $?
    chown root:globnotes /etc/globnotes/env || return $?
    mv -T -- "$stage/source" /opt/globnotes || return $?
    cat > /etc/systemd/system/globnotes.service << 'UNIT' || return $?
[Unit]
Description=Globnotes native Deno notes server
After=network.target

[Service]
Type=exec
User=globnotes
Group=globnotes
WorkingDirectory=/opt/globnotes
EnvironmentFile=/etc/globnotes/env
EnvironmentFile=/opt/globnotes/runtime/release.env
ExecStart=/opt/globnotes/runtime/deno run --unstable-worker-options --cached-only --lock=/opt/globnotes/runtime/dependency-lock/deno.lock --allow-net --allow-read --allow-write --allow-env server/main.ts
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
KillMode=control-group
TimeoutStopSec=60
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT
    systemctl daemon-reload || return $?
    systemctl enable --now globnotes || status=$?
    if [[ "$status" == 0 ]]; then gn_health 0.0.0.0 80 '' || status=$?; fi
    if [[ "$status" == 0 ]]; then
      # The real marker may be on a different filesystem from /opt. Allocate
      # beside it so publication is a rename, never mv's cross-device copy.
      marker_stage=$(mktemp "$HOME/.globnotes.XXXXXX") || status=$?
      if [[ "$status" == 0 ]]; then printf '%s\n' "$release_version" > "$marker_stage" || status=$?; fi
      if [[ "$status" == 0 ]]; then mv -T -- "$marker_stage" "$HOME/.globnotes" || status=$?; fi
    fi
    if [[ "$status" != 0 ]]; then systemctl stop globnotes || msg_error 'Failed fresh service retained; inspect globnotes.service'; fi
  fi
  local cleanup_status=0
  if [[ -n "$marker_stage" && -e "$marker_stage" ]]; then rm -f -- "$marker_stage" || cleanup_status=$?; fi
  _deploy_remove_owned_trees "$stage" || cleanup_status=$?
  [[ "$status" != 0 ]] || status=$cleanup_status
  return "$status"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${INFO}${YW}Open http://${IP}/ and complete the first-run setup wizard.${CL}"
  echo -e "${INFO}${YW}Notes: /var/lib/globnotes/notes; operator environment: /etc/globnotes/env.${CL}"
  echo -e "${INFO}${YW}Back up notes and the complete application-state directory, including authentication and plugins.${CL}"
}

function update_script() {
  # Keep this hook independently cold-contained. The install bundle does not
  # transport update_script (and the update bundle does not transport install).
  gn_path() {
    local LC_ALL=C
    [[ "$1" == /* && "$1" != *[[:cntrl:]]* ]] || return 65
    printf '%s' "$1" | iconv -f UTF-8 -t UTF-8 > /dev/null || return 65
    realpath -m -- "$1"
  }
  gn_separate() { [[ "$1" != "$2" && "$1" != "$2/"* && "$2" != "$1/"* ]]; }
  gn_roots() {
    local notes=$1 state=$2 cache=$3 fixed
    [[ "$notes" != / && "$state" != / && "$cache" != / ]] || return 65
    gn_separate "$notes" "$cache" && gn_separate "$state" "$cache" || return 65
    if [[ "$state" != "$notes/.globnotes" ]]; then gn_separate "$notes" "$state" || return 65; fi
    for fixed in /opt/globnotes /opt/globnotes-builds /etc/globnotes /var/lib/globnotes/tmp; do
      gn_separate "$notes" "$fixed" && gn_separate "$state" "$fixed" && gn_separate "$cache" "$fixed" || return 65
    done
    for fixed in "$notes" "$state"; do
      [[ "$fixed" != "$cache.candidate."* && "$fixed" != "$cache.retired."* ]] || return 65
    done
  }
  gn_env_line() {
    local value=$2
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//\$/\\\$}
    value=${value//\`/\\\`}
    printf '%s="%s"\n' "$1" "$value"
  }
  gn_revision() {
    local tag=$1 encoded response raw_ref object kind sha i seen='|'
    encoded=$(jq -nr --arg tag "$tag" '$tag|@uri') || return $?
    local -a headers=(-H 'Accept: application/vnd.github+json')
    [[ -z "${GITHUB_TOKEN:-}" ]] || headers+=(-H "Authorization: Bearer $GITHUB_TOKEN")
    response=$(curl -fsSL --connect-timeout 15 --max-time 60 "${headers[@]}" "https://api.github.com/repos/alexindigo/globnotes/git/ref/tags/$encoded") || return $?
    raw_ref=$(jq -er .ref <<< "$response") || return 250
    [[ "$raw_ref" == "refs/tags/$tag" ]] || return 250
    for ((i = 0; i < 12; i++)); do
      object=$(jq -ce '.object | select(type=="object")' <<< "$response") || return 250
      kind=$(jq -er .type <<< "$object") || return 250
      sha=$(jq -er .sha <<< "$object") || return 250
      [[ "$sha" =~ ^[0-9a-f]{40}$ && "$seen" != *"|$sha|"* ]] || return 250
      [[ "$kind" != commit ]] || {
        printf '%s\n' "$sha" || return $?
        return 0
      }
      [[ "$kind" == tag ]] || return 250
      seen+="$sha|"
      response=$(curl -fsSL --connect-timeout 15 --max-time 60 "${headers[@]}" "https://api.github.com/repos/alexindigo/globnotes/git/tags/$sha") || return $?
    done
    return 250
  }
  gn_release() {
    local file=$1 tag=$2
    jq -e --arg tag "$tag" '
      (.id|type)=="number" and .id>0 and (.id|floor)==.id and
      (.published_at|type)=="string" and (.published_at|length)>0 and
      .url==("https://api.github.com/repos/alexindigo/globnotes/releases/"+(.id|tostring)) and
      .draft==false and .prerelease==false and .tag_name==$tag' "$file" > /dev/null || return 250
    [[ "$tag" =~ ^v?[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || return 250
  }
  gn_download() {
    local tag=$CHECK_UPDATE_RELEASE revision again pin line build_pin='' runtime_pin='' arch actual
    revision=$(gn_revision "$tag") || return $?
    HOME="$stage/helper-home" var_appversion='' fetch_and_deploy_gh_release globnotes alexindigo/globnotes tarball "$tag" "$stage/source" '' '' "$stage/deployed.json" || return $?
    gn_release "$stage/deployed.json" "$tag" || return $?
    again=$(gn_revision "$tag") || return $?
    [[ "$revision" == "$again" && $(< "$stage/source/VERSION") == "${tag#v}" ]] || return 250
    [[ ! -e "$stage/source/runtime" && ! -L "$stage/source/runtime" ]] || return 65
    while IFS= read -r line || [[ -n "$line" ]]; do
      if [[ "$line" == FROM*denoland/deno:* ]]; then
        if [[ "$line" =~ ^FROM[[:space:]]+--platform=\$BUILDPLATFORM[[:space:]]+denoland/deno:([0-9]+\.[0-9]+\.[0-9]+)[[:space:]]+AS[[:space:]]+build$ && -z "$build_pin" ]]; then
          build_pin=${BASH_REMATCH[1]}
        elif [[ "$line" =~ ^FROM[[:space:]]+denoland/deno:alpine-([0-9]+\.[0-9]+\.[0-9]+)$ && -z "$runtime_pin" ]]; then
          runtime_pin=${BASH_REMATCH[1]}
        else return 65; fi
      fi
    done < "$stage/source/Dockerfile"
    [[ -n "$build_pin" && "$build_pin" == "$runtime_pin" ]] || return 65
    pin=$build_pin
    arch=$(get_system_arch dpkg x86_64 aarch64) || return $?
    [[ "$arch" == x86_64 || "$arch" == aarch64 ]] || return 65
    HOME="$stage/helper-home" var_appversion='' fetch_and_deploy_gh_release deno denoland/deno prebuild "v$pin" "$stage/source/runtime" "deno-$arch-unknown-linux-gnu.zip" || return $?
    chmod 755 "$stage/source/runtime/deno" || return $?
    actual=$("$stage/source/runtime/deno" --version) || return $?
    [[ "${actual%%$'\n'*}" == "deno $pin (stable)" || "${actual%%$'\n'*}" == "deno $pin (stable, release, $arch-unknown-linux-gnu)" ]] || return 250
    gn_env_line GLOBNOTES_REVISION "$revision" > "$stage/source/runtime/release.env" || return $?
    release_version=${tag#v}
    release_revision=$revision
  }
  gn_build() {
    local released_lock_hash after_lock_hash
    released_lock_hash=$(sha256sum "$stage/source/deno.lock") || return $?
    released_lock_hash=${released_lock_hash%% *}
    chown -R globnotes:globnotes -- "$stage/source" || return $?
    chmod 755 "$stage" || return $?
    install -d -o globnotes -g globnotes -m 750 "$stage/build-home" "$stage/build-tmp" || return $?
    (
      cd "$stage/source" || return $?
      $STD runuser -u globnotes -- env -i PATH="$stage/source/runtime:/usr/bin:/bin" HOME="$stage/build-home" TMPDIR="$stage/build-tmp" DENO_DIR="$candidate_cache" deno install --frozen || return $?
      $STD runuser -u globnotes -- env -i PATH="$stage/source/runtime:/usr/bin:/bin" HOME="$stage/build-home" TMPDIR="$stage/build-tmp" DENO_DIR="$candidate_cache" deno task build:client || return $?
      $STD runuser -u globnotes -- env -i PATH="$stage/source/runtime:/usr/bin:/bin" HOME="$stage/build-home" TMPDIR="$stage/build-tmp" DENO_DIR="$candidate_cache" deno cache server/main.ts || return $?
    ) || return $?
    after_lock_hash=$(sha256sum "$stage/source/deno.lock") || return $?
    [[ "${after_lock_hash%% *}" == "$released_lock_hash" ]] || return 250
    [[ -s "$stage/source/client/dist/index.html" ]] || return 250
    chown -R root:root -- "$stage/source" || return $?
    chown -R globnotes:globnotes -- "$stage/source/node_modules" || return $?
    chown globnotes:globnotes -- "$stage/source/client/dist/index.html" || return $?
    chmod -R a+rX -- "$stage/source" || return $?
    install -d -o globnotes -g globnotes -m 750 "$stage/source/runtime/dependency-lock" || return $?
    install -o globnotes -g globnotes -m 600 "$stage/source/deno.lock" "$stage/source/runtime/dependency-lock/deno.lock" || return $?
    printf '%s  deno.lock\n' "$released_lock_hash" > "$stage/source/runtime/released-lock.sha256" || return $?
    chmod 644 "$stage/source/runtime/released-lock.sha256" || return $?
  }
  gn_health() {
    local host=$1 port=$2 prefix=$3 body i
    case "$host" in 0.0.0.0) host=127.0.0.1 ;; ::) host='[::1]' ;; *:*) host="[$host]" ;; esac
    for ((i = 0; i < 30; i++)); do
      if body=$(curl -fsS --connect-timeout 2 --max-time 5 "http://$host:$port$prefix/_/api/config"); then
        if jq -e --arg version "$release_version" --arg revision "$release_revision" '.version==$version and .revision==$revision' <<< "$body" > /dev/null; then return 0; fi
      fi
      sleep 1 || return $?
    done
    return 22
  }
  gn_read_roots() {
    # Only selected public deployment settings leave the probe. Never source
    # operator text, nor print its complete environment (which may hold secrets).
    local file=$1 entry key value
    gn_notes=/var/lib/globnotes/notes
    gn_state=''
    gn_cache=/var/cache/globnotes
    gn_host=0.0.0.0
    # This is the application's absent-variable default. Fresh installation
    # separately persists its explicit standard-port choice of 80.
    gn_port=8080
    gn_prefix=''
    [[ -r "$file" ]] || return 77
    while IFS= read -r -d '' entry; do
      key=${entry%%=*}
      value=${entry#*=}
      case "$key" in
        GLOBNOTES_PATH) gn_notes=$value ;;
        GLOBNOTES_INDEX_PATH) gn_state=$value ;;
        DENO_DIR) gn_cache=$value ;;
        GLOBNOTES_HOST) gn_host=$value ;;
        GLOBNOTES_PORT) gn_port=$value ;;
        GLOBNOTES_PATH_PREFIX) gn_prefix=$value ;;
      esac
    done < "$file" || return $?
    gn_notes=$(gn_path "$gn_notes") || return $?
    gn_state=$(gn_path "${gn_state:-$gn_notes/.globnotes}") || return $?
    gn_cache=$(gn_path "$gn_cache") || return $?
    gn_roots "$gn_notes" "$gn_state" "$gn_cache" || return 65
    [[ "$gn_port" =~ ^[0-9]{1,5}$ && "$gn_host" != *[[:cntrl:]]* && -n "$gn_host" ]] || return 65
    ((10#$gn_port > 0 && 10#$gn_port <= 65535)) || return 65
    [[ -z "$gn_prefix" || ("$gn_prefix" == /* && "$gn_prefix" != */ && "$gn_prefix" != *[[:cntrl:]]*) ]] || return 65
  }
  gn_stopped() {
    local active pid group tasks
    active=$(systemctl show globnotes.service --property=ActiveState --value) || return $?
    pid=$(systemctl show globnotes.service --property=MainPID --value) || return $?
    group=$(systemctl show globnotes.service --property=ControlGroup --value) || return $?
    [[ "$active" == inactive || "$active" == failed ]] && [[ "$pid" == 0 ]] || return 75
    # systemd releases the unit's group after its last process exits. An empty
    # group is quiescent only after both lifecycle and MainPID checks above.
    [[ -n "$group" ]] || return 0
    [[ "$group" == /* && "$group" != *..* ]] || return 65
    if [[ -e "/sys/fs/cgroup$group/cgroup.procs" ]]; then
      tasks=$(< "/sys/fs/cgroup$group/cgroup.procs")
      [[ -z "$tasks" ]] || return 75
    fi
  }
  gn_remove() {
    # Fresh mount containment guard from the existing deployment helper. No
    # sweep of old siblings: only paths allocated by this invocation are passed.
    _deploy_remove_owned_trees "$1"
  }
  gn_movable() {
    local mount
    [[ -r /proc/self/mountinfo ]] || return 252
    while read -r _ _ _ _ mount _; do
      mount=${mount//\\040/ }
      mount=${mount//\\011/$'\t'}
      mount=${mount//\\012/$'\n'}
      mount=${mount//\\134/$'\\'}
      [[ "$mount" != "$1" && "$mount" != "$1/"* ]] || return 65
    done < /proc/self/mountinfo
  }

  render_header || return $?
  check_container_storage || return $?
  check_container_resources || return $?
  [[ -x /opt/globnotes/runtime/deno && -f /opt/globnotes/runtime/release.env && -f /etc/globnotes/env && -f "$HOME/.globnotes" ]] || {
    msg_error 'This updater requires a native-Deno installation created by this script'
    return 65
  }
  local stage candidate_cache='' retired_cache='' retired_code='' marker_stage='' release_version release_revision
  local gn_notes gn_state gn_cache gn_host gn_port gn_prefix notes state cache host port prefix
  local active pid group process_group configured_tag cache_parent due=0 status=0 cleanup_status=0 was_running=0
  local code_retired=0 code_published=0 cache_retired=0 cache_published=0 marker_published=0
  stage=$(mktemp -d /opt/globnotes-builds/update.XXXXXX) || return $?
  mkdir -m 700 "$stage/helper-home" || return $?
  gn_preflight() {
    local cache_device parent_device code_device stage_device
    # This transient command never starts the app or writes its data. Match the
    # unit's ordered EnvironmentFile sources and let systemd parse their syntax.
    systemd-run --quiet --wait --pipe --collect --property=User=globnotes \
      --property=EnvironmentFile=/etc/globnotes/env \
      --property=EnvironmentFile=/opt/globnotes/runtime/release.env /usr/bin/env -0 > "$stage/configured.env0" || return $?
    # The build later opens traversal on its stage. Keep the complete probe
    # output root-private even then; only whitelisted roots enter shell values.
    chmod 600 "$stage/configured.env0" || return $?
    gn_read_roots "$stage/configured.env0" || return $?
    notes=$gn_notes
    state=$gn_state
    cache=$gn_cache
    host=$gn_host
    port=$gn_port
    prefix=$gn_prefix
    active=$(systemctl show globnotes.service --property=ActiveState --value) || return $?
    case "$active" in active) was_running=1 ;; inactive | failed) ;; *) return 75 ;; esac
    if [[ "$was_running" == 1 ]]; then
      pid=$(systemctl show globnotes.service --property=MainPID --value) || return $?
      group=$(systemctl show globnotes.service --property=ControlGroup --value) || return $?
      [[ "$pid" =~ ^[1-9][0-9]*$ && -r "/proc/$pid/environ" && "$group" == /* ]] || return 75
      [[ "/proc/$pid/exe" -ef /opt/globnotes/runtime/deno ]] || return 75
      process_group=$(< "/proc/$pid/cgroup")
      [[ "$process_group" == "0::$group" ]] || return 75
      gn_read_roots "/proc/$pid/environ" || return $?
      [[ "$notes" == "$gn_notes" && "$state" == "$gn_state" && "$cache" == "$gn_cache" ]] || {
        msg_error 'Configured persistent roots differ from the running service. Apply the operator configuration explicitly before updating; no data was relocated.'
        return 65
      }
    fi
    # The cache root itself must be a movable directory on its parent's filesystem.
    [[ -d "$cache" && ! -L "$cache" && ! -L /opt/globnotes ]] || return 65
    cache_parent=$(dirname -- "$cache") || return $?
    cache_device=$(stat -c %d -- "$cache") || return $?
    parent_device=$(stat -c %d -- "$cache_parent") || return $?
    code_device=$(stat -c %d /opt/globnotes) || return $?
    stage_device=$(stat -c %d "$stage") || return $?
    [[ "$cache_device" == "$parent_device" && "$code_device" == "$stage_device" ]] || return 65
    gn_movable "$cache" || return $?
    gn_movable /opt/globnotes || return $?
    _gh_release_json alexindigo/globnotes "${var_appversion:-latest}" '' "$stage/selected.json" || return $?
    configured_tag=$(jq -er .tag_name "$stage/selected.json") || return 250
    gn_release "$stage/selected.json" "$configured_tag" || return $?
    # Public checker status1 is a successful no-op; other nonzero statuses fail.
    if check_for_gh_release globnotes alexindigo/globnotes "$configured_tag"; then
      due=1
    else
      local check_status=$?
      [[ "$check_status" == 1 ]] || return "$check_status"
    fi
  }
  gn_preflight || status=$?
  if [[ "$status" != 0 ]]; then
    gn_remove "$stage" || msg_error "Failed preflight ($status); retained $stage"
    return "$status"
  fi
  if [[ "$due" == 0 ]]; then
    release_revision=$(gn_revision "$configured_tag") || status=$?
    if [[ "$status" == 0 ]]; then
      [[ $(< /opt/globnotes/VERSION) == "${configured_tag#v}" ]] &&
        grep -Fxq "GLOBNOTES_REVISION=\"$release_revision\"" /opt/globnotes/runtime/release.env || status=250
    fi
    gn_remove "$stage" || cleanup_status=$?
    [[ "$status" != 0 ]] || status=$cleanup_status
    return "$status"
  fi
  status=0
  gn_download || status=$?
  if [[ "$status" == 0 ]]; then
    cp -a -- "$HOME/.globnotes" "$stage/old-marker" || status=$?
  fi
  if [[ "$status" == 0 ]]; then
    candidate_cache=$(mktemp -d "$cache.candidate.XXXXXX") || status=$?
  fi
  if [[ "$status" == 0 ]]; then
    retired_cache=$(mktemp -d "$cache.retired.XXXXXX") || status=$?
  fi
  if [[ "$status" == 0 ]]; then
    retired_code="$stage/retired-code"
    systemctl stop globnotes || status=$?
    if [[ "$status" == 0 ]]; then gn_stopped || status=$?; fi
    # Copy only after all old cache writers have stopped. Reflink/copy gives
    # mutable SQLite/cache metadata independent inodes, never hardlinks.
    if [[ "$status" == 0 ]]; then cp -a --reflink=auto -- "$cache/." "$candidate_cache/" || status=$?; fi
    if [[ "$status" == 0 ]]; then chown globnotes:globnotes "$candidate_cache" || status=$?; fi
    if [[ "$status" == 0 ]]; then gn_build || status=$?; fi
    if [[ "$status" == 0 ]]; then mv -T -- /opt/globnotes "$retired_code" && code_retired=1 || status=$?; fi
    if [[ "$status" == 0 ]]; then mv -T -- "$stage/source" /opt/globnotes && code_published=1 || status=$?; fi
    if [[ "$status" == 0 ]]; then mv -T -- "$cache" "$retired_cache" && cache_retired=1 || status=$?; fi
    if [[ "$status" == 0 ]]; then mv -T -- "$candidate_cache" "$cache" && cache_published=1 || status=$?; fi
    if [[ "$status" == 0 ]]; then systemctl start globnotes || status=$?; fi
    if [[ "$status" == 0 ]]; then gn_health "$host" "$port" "$prefix" || status=$?; fi
    if [[ "$status" == 0 ]]; then marker_stage=$(mktemp "$HOME/.globnotes.XXXXXX") || status=$?; fi
    if [[ "$status" == 0 ]]; then printf '%s\n' "$release_version" > "$marker_stage" || status=$?; fi
    if [[ "$status" == 0 ]]; then mv -T -- "$marker_stage" "$HOME/.globnotes" && marker_published=1 || status=$?; fi
    if [[ "$status" != 0 ]]; then
      local restore_status=0
      systemctl stop globnotes || restore_status=$?
      if [[ "$restore_status" == 0 ]]; then gn_stopped || restore_status=$?; fi
      if [[ "$restore_status" == 0 && "$code_published" == 1 ]]; then mv -T -- /opt/globnotes "$stage/failed-code" || restore_status=$?; fi
      if [[ "$restore_status" == 0 && "$code_retired" == 1 ]]; then mv -T -- "$retired_code" /opt/globnotes || restore_status=$?; fi
      if [[ "$restore_status" == 0 && "$cache_published" == 1 ]]; then mv -T -- "$cache" "$candidate_cache" || restore_status=$?; fi
      if [[ "$restore_status" == 0 && "$cache_retired" == 1 ]]; then mv -T -- "$retired_cache" "$cache" || restore_status=$?; fi
      if [[ "$restore_status" == 0 && "$marker_published" == 1 ]]; then mv -T -- "$stage/old-marker" "$HOME/.globnotes" || restore_status=$?; fi
      if [[ "$restore_status" == 0 && "$was_running" == 1 ]]; then systemctl start globnotes || restore_status=$?; fi
      if [[ "$restore_status" != 0 ]]; then
        msg_error "Update failed ($status); recovery incomplete ($restore_status). Retained $stage, $candidate_cache, $retired_cache; marker stage: $marker_stage."
        return "$status"
      fi
    elif [[ "$was_running" == 0 ]]; then
      # Validate a previously stopped deployment briefly, then restore its state.
      systemctl stop globnotes || status=$?
      if [[ "$status" == 0 ]]; then gn_stopped || status=$?; fi
    fi
  fi
  # Cleanup is checked and limited to this operation. Once health+marker succeed,
  # retire old code/cache immediately; a cleanup fault remains a pending update.
  if [[ -n "$marker_stage" && -e "$marker_stage" ]]; then rm -f -- "$marker_stage" || cleanup_status=$?; fi
  if [[ -n "$retired_code" && -e "$retired_code" ]]; then gn_remove "$retired_code" || cleanup_status=$?; fi
  if [[ -n "$retired_cache" && -e "$retired_cache" ]]; then gn_remove "$retired_cache" || cleanup_status=$?; fi
  if [[ -n "$candidate_cache" && -e "$candidate_cache" ]]; then gn_remove "$candidate_cache" || cleanup_status=$?; fi
  if [[ "$cleanup_status" == 0 ]]; then gn_remove "$stage" || cleanup_status=$?; fi
  if [[ "$cleanup_status" != 0 ]]; then msg_error "Owned update artifacts retained at $stage / $retired_cache / $candidate_cache / $marker_stage (cleanup=$cleanup_status)"; fi
  [[ "$status" != 0 ]] || status=$cleanup_status
  return "$status"
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
