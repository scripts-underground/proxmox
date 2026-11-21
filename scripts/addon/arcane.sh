#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: summoningpixels
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/getarcaneapp/arcane

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Arcane"

# Bundle-consumed configuration (var_addon_* is baked into update/uninstall
# bundles at install time — hooks may reference these directly)
var_addon_install_path="${var_addon_install_path:-/opt/arcane}"
var_addon_compose_file="${var_addon_compose_file:-${var_addon_install_path}/compose.yaml}"
var_addon_env_file="${var_addon_env_file:-${var_addon_install_path}/.env}"
var_addon_proj_dir="${var_addon_proj_dir:-/etc/arcane/projects}"
var_addon_builds_dir="${var_addon_builds_dir:-/etc/arcane/builds}"
var_addon_compose_url="${var_addon_compose_url:-https://raw.githubusercontent.com/getarcaneapp/arcane/refs/heads/main/docker/examples/compose.basic.yaml}"
var_addon_env_url="${var_addon_env_url:-https://raw.githubusercontent.com/getarcaneapp/arcane/refs/heads/main/.env.example}"
var_addon_default_port="${var_addon_default_port:-3552}"

function install_script() {
  if [[ "$OS_FAMILY" != "debian" && "$OS_FAMILY" != "alpine" ]]; then
    msg_error "Unsupported OS: ${OS_TYPE} (Debian/Ubuntu and Alpine only)"
    return 1
  fi
  if [[ ! "$var_addon_default_port" =~ ^[0-9]{1,5}$ ]] || ((10#$var_addon_default_port < 1 || 10#$var_addon_default_port > 65535)); then
    msg_error "Invalid Arcane HTTP port: ${var_addon_default_port}"
    return 65
  fi
  if [[ -e "$var_addon_compose_file" || -L "$var_addon_compose_file" || -e "$var_addon_env_file" || -L "$var_addon_env_file" ]]; then
    msg_error "Arcane compose or environment path is already occupied; preserve it and use explicit adoption."
    return 65
  fi
  # First anchor source-derived defaults when the install root itself is relative.
  [[ "$var_addon_compose_file" != "$var_addon_install_path/compose.yaml" ]] || var_addon_compose_file=$(addon_resolve_path "$var_addon_compose_file") || return $?
  [[ "$var_addon_env_file" != "$var_addon_install_path/.env" ]] || var_addon_env_file=$(addon_resolve_path "$var_addon_env_file") || return $?
  # Bind relative selections once to the project, not the install caller's cwd.
  var_addon_install_path=$(addon_resolve_path "$var_addon_install_path") || return $?
  [[ "$var_addon_compose_file" == /* ]] || var_addon_compose_file="$var_addon_install_path/$var_addon_compose_file"
  [[ "$var_addon_env_file" == /* ]] || var_addon_env_file="$var_addon_install_path/$var_addon_env_file"
  var_addon_compose_file=$(addon_resolve_path "$var_addon_compose_file") || return $?
  var_addon_env_file=$(addon_resolve_path "$var_addon_env_file") || return $?
  if [[ "$var_addon_compose_file" == "$var_addon_env_file" || -e "$var_addon_compose_file" || -L "$var_addon_compose_file" || -e "$var_addon_env_file" || -L "$var_addon_env_file" ]]; then
    msg_error "Arcane compose or environment path is already occupied; preserve it and use explicit adoption."
    return 65
  fi

  if ! command -v docker &> /dev/null; then
    msg_info "Installing Docker"
    if [[ "$OS_FAMILY" == "alpine" ]]; then
      $STD apk add --no-cache docker docker-cli-compose
      $STD rc-update add docker default
      $STD rc-service docker start
    else
      DOCKER_SKIP_UPDATES=true setup_docker
    fi
    msg_ok "Installed Docker"
  fi
  if ! docker compose version &> /dev/null; then
    msg_error "Docker Compose plugin is not available. Please install it before running this script. Exiting."
    exit 1
  fi
  addon_compose_require --no-interpolate --no-env-resolution --no-path-resolution || return $?
  msg_ok "Docker $(docker --version | cut -d' ' -f3 | tr -d ',') and Docker Compose are available"

  msg_info "Creating install directory"
  addon_install_begin "$var_addon_install_path" "arcane:$var_addon_install_path"
  msg_ok "Created ${var_addon_install_path}"

  ensure_dependencies openssl
  local encryption_key
  encryption_key=$(openssl rand -hex 16)

  # Newly created binds start with Arcane's default identity; after native
  # configuration resolution they receive the selected runtime identity instead.
  # Existing directories are never chowned, including when access is refused.
  local projects_created=0 builds_created=0
  msg_info "Creating stacks directory"
  if [[ ! -e "$var_addon_proj_dir" ]]; then
    mkdir -p "$var_addon_proj_dir"
    chown 65532:65532 "$var_addon_proj_dir"
    projects_created=1
  fi
  msg_ok "Created ${var_addon_proj_dir}"

  msg_info "Creating builds directory"
  if [[ ! -e "$var_addon_builds_dir" ]]; then
    mkdir -p "$var_addon_builds_dir"
    chown 65532:65532 "$var_addon_builds_dir"
    builds_created=1
  fi
  msg_ok "Created ${var_addon_builds_dir}"

  msg_info "Preparing Docker Compose and environment files"
  mkdir -p "$(dirname "$var_addon_compose_file")" "$(dirname "$var_addon_env_file")"
  local compose_stage env_stage prepare_status install_project
  compose_stage=$(mktemp -d "$(dirname "$var_addon_compose_file")/.arcane-compose.XXXXXXXX")
  if env_stage=$(mktemp -d "$(dirname "$var_addon_env_file")/.arcane-env.XXXXXXXX"); then :; else
    prepare_status=$?
    rm -rf -- "$compose_stage"
    return "$prepare_status"
  fi
  _arcane_bind_access() {
    local model=$1 identity uid gid groups socket path
    # Arcane's root entrypoint drops to both PUID/PGID when supplied, otherwise
    # 65532:65532. A nonroot explicit Docker user remains that user. Named image
    # accounts cannot be resolved from Compose alone and are reported as unknown.
    if identity=$(jq -ce '
      def trim: tostring | gsub("^\\s+|\\s+$"; "");
      def id: if test("^[+]?[0-9]+$") and (tonumber <= 4294967295) then tonumber else error("invalid runtime identity") end;
      .services.arcane as $s |
      (($s.environment.PUID // "") | trim) as $puid |
      (($s.environment.PGID // "") | trim) as $pgid |
      (if $puid == "" or $pgid == "" then [65532,65532] else [($puid | id),($pgid | id)] end) as $requested |
      (($s.user // "0:0") | trim) as $user |
      if ($user | test("^(0+|root)(:.*)?$")) or $user == "" then {ids:$requested,groups:[],socket_group:true}
      elif ($user | test("^[0-9]+:[0-9]+$")) then
        {ids:($user | split(":") | map(id)),groups:(($s.group_add // []) | map(trim | id))}
      else error("unresolved image runtime user: " + $user) end
    ' "$model"); then :; else
      msg_error "Cannot establish Arcane runtime UID/GID from the prepared configuration"
      return 65
    fi
    uid=$(jq -r '.ids[0]' <<< "$identity") || return $?
    gid=$(jq -r '.ids[1]' <<< "$identity") || return $?
    groups=$(jq -r '.groups | join(",")' <<< "$identity") || return $?
    # The root entrypoint replaces supplementary groups with its Docker socket
    # group. Bind metadata supplies the host-side equivalent of that group.
    if [[ "$(jq -r '.socket_group // false' <<< "$identity")" == true ]]; then
      socket=$(jq -r '.services.arcane as $s | ($s.environment.DOCKER_HOST // "unix:///var/run/docker.sock") as $host |
        $s.volumes[]? | select(.type == "bind" and ("unix://" + .target) == $host) | .source' "$model") || return $?
      if [[ -n "$socket" && -S "$socket" ]]; then groups=$(stat -Lc %g -- "$socket") || return $?; fi
    fi
    local identity_package=util-linux probe_uid probe_gid
    [[ "$OS_FAMILY" != alpine ]] || identity_package=setpriv
    probe_uid=$(id -u) || return $?
    probe_gid=$(id -g) || return $?
    # BusyBox supplies setpriv without UID/GID/group switching. Probe harmless
    # child commands, not its name/version, and verify both consumed group modes.
    ensure_dependencies --capability "$identity_package" -- setpriv --reuid="$probe_uid" --regid="$probe_gid" --clear-groups sh -c : || return $?
    ensure_dependencies --capability "$identity_package" -- setpriv --reuid="$probe_uid" --regid="$probe_gid" --groups="$probe_gid" sh -c : || return $?
    local -a group_args=(--clear-groups)
    [[ -z "$groups" ]] || group_args=(--groups="$groups")
    [[ "$projects_created" == 0 ]] || chown "$uid:$gid" "$var_addon_proj_dir" || return $?
    [[ "$builds_created" == 0 ]] || chown "$uid:$gid" "$var_addon_builds_dir" || return $?
    for path in "$var_addon_proj_dir" "$var_addon_builds_dir"; do
      # Check the mounted directory itself, not host-only ancestors which are
      # absent inside the container. No root-only test or metadata repair.
      if (cd -- "$path" && setpriv --reuid="$uid" --regid="$gid" "${group_args[@]}" sh -c 'test -d . && test -w . && test -x .'); then :; else
        msg_error "Arcane runtime ${uid}:${gid} cannot write/traverse directory: ${path}"
        return 73
      fi
    done
  }
  # Native Compose owns YAML and environment interpretation. No incomplete
  # transport or invalid source is published into either selected live path.
  if curl -fsSL "$var_addon_compose_url" -o "$compose_stage/source.yaml" &&
    curl -fsSL "$var_addon_env_url" -o "$env_stage/runtime.env" &&
    [[ -s "$compose_stage/source.yaml" && -s "$env_stage/runtime.env" ]] &&
    sed -i -e "s|^ARCANE_APP_URL=.*|ARCANE_APP_URL=http://localhost:${var_addon_default_port}|" \
      -e "s|^ARCANE_ENCRYPTION_KEY=.*|ARCANE_ENCRYPTION_KEY=${encryption_key}|" "$env_stage/runtime.env" &&
    addon_compose_source --project-directory "$var_addon_install_path" --env-file "$env_stage/runtime.env" -f "$compose_stage/source.yaml" > "$compose_stage/source.json" &&
    jq -e --arg port "$var_addon_default_port" \
      --arg projects "$var_addon_proj_dir" --arg builds "$var_addon_builds_dir" --arg env "$var_addon_env_file" --arg original "$var_addon_install_path/.env" '
      .services.arcane.ports |= map(if .target == 3552 then .published = $port else . end) |
      .services.arcane.environment.ARCANE_ENCRYPTION_KEY = "${ARCANE_ENCRYPTION_KEY}" |
      .services.arcane.environment.ARCANE_PROJECTS_DIRECTORY = $projects |
      .services.arcane.environment.ARCANE_APP_URL = "${ARCANE_APP_URL}" |
      .services.arcane.volumes |= map(
        if .source == "/host/path/to/projects" then .source = $projects | .target = $projects
        elif .source == "/host/path/to/builds" then .source = $builds else . end) |
      .services.arcane.env_file = (((.services.arcane.env_file // []) | map(
        if .path == ".env" or .path == "./.env" or .path == $original then .path = $env else . end)) + [{path: $env, required: true}] | unique_by(.path))
    ' "$compose_stage/source.json" > "$compose_stage/compose.json" &&
    chmod 600 "$env_stage/runtime.env" "$compose_stage/compose.json" &&
    jq --arg live "$var_addon_env_file" --arg env "$env_stage/runtime.env" '(.services.arcane.env_file[] | select(.path == $live) | .path) = $env' "$compose_stage/compose.json" > "$compose_stage/validation.json" &&
    docker compose --project-directory "$var_addon_install_path" --env-file "$env_stage/runtime.env" -f "$compose_stage/validation.json" config -q &&
    docker compose --project-directory "$var_addon_install_path" --env-file "$env_stage/runtime.env" -f "$compose_stage/validation.json" config --format json > "$compose_stage/runtime.json" &&
    install_project=$(jq -er '.name | select(type == "string" and test("^[a-z0-9][a-z0-9_-]*$"))' "$compose_stage/runtime.json") &&
    _arcane_bind_access "$compose_stage/runtime.json" &&
    addon_install_publish_file "$env_stage/runtime.env" "$var_addon_env_file" "$var_addon_install_path" "arcane:$var_addon_install_path" &&
    addon_install_publish_file "$compose_stage/compose.json" "$var_addon_compose_file" "$var_addon_install_path" "arcane:$var_addon_install_path"; then
    rm -rf -- "$compose_stage" "$env_stage"
  else
    prepare_status=$?
    # Publication never replaces occupied names. Retire only this preparation's
    # own inodes if a later publication step fails; preserve foreign files.
    if [[ "$var_addon_env_file" -ef "$env_stage/runtime.env" ]]; then rm -f -- "$var_addon_env_file"; fi
    if [[ "$var_addon_compose_file" -ef "$compose_stage/compose.json" ]]; then rm -f -- "$var_addon_compose_file"; fi
    rm -rf -- "$compose_stage" "$env_stage"
    return "$prepare_status"
  fi
  msg_ok "Prepared Docker Compose and environment files"

  msg_info "Starting ${APP}"
  addon_install_expose "$var_addon_install_path" "arcane:$var_addon_install_path" "$install_project"
  $STD docker compose --project-name "$install_project" --project-directory "$var_addon_install_path" --env-file "$var_addon_env_file" -f "$var_addon_compose_file" up -d
  addon_install_complete "$var_addon_install_path" "arcane:$var_addon_install_path"
  msg_ok "Started ${APP}"
}

function post_install_script() {
  echo ""
  msg_ok "${APP} installed successfully"
  echo -e "${INFO}${YW}Web UI:${CL} ${BGN}http://${LOCAL_IP}:${var_addon_default_port}${CL}"
  echo -e "${INFO}${YW}Login:${CL} ${GN}arcane${CL} / ${GN}arcane-admin${CL} (you'll be prompted to change the password on first access)"
  echo -e "${INFO}${YW}Update:${CL} update-${APP_SLUG}   ${YW}Uninstall:${CL} uninstall-${APP_SLUG}"
}

function update_script() {
  var_addon_install_path=$(addon_resolve_path "$var_addon_install_path") || return $?
  [[ "$var_addon_compose_file" == /* ]] || var_addon_compose_file="$var_addon_install_path/$var_addon_compose_file"
  [[ "$var_addon_env_file" == /* ]] || var_addon_env_file="$var_addon_install_path/$var_addon_env_file"
  local -a compose_env=()
  [[ ! -e "$var_addon_env_file" ]] || compose_env=(--env-file "$var_addon_env_file")
  local install_state install_project
  local -a compose_project=()
  addon_install_status install_state "$var_addon_install_path" "arcane:$var_addon_install_path" || return $?
  if [[ "$install_state" != absent ]]; then
    addon_install_consumer_identity install_project "$var_addon_install_path" "arcane:$var_addon_install_path" || return $?
    compose_project=(--project-name "$install_project")
  fi
  if [[ ! -f "$var_addon_compose_file" ]]; then
    msg_error "No ${APP} installation found (${var_addon_compose_file} missing)"
    exit 1
  fi

  msg_info "Pulling latest ${APP} image"
  $STD docker compose "${compose_project[@]}" --project-directory "$var_addon_install_path" "${compose_env[@]}" -f "$var_addon_compose_file" pull
  msg_ok "Pulled latest image"

  msg_info "Restarting ${APP}"
  $STD docker compose "${compose_project[@]}" --project-directory "$var_addon_install_path" "${compose_env[@]}" -f "$var_addon_compose_file" up -d --remove-orphans
  msg_ok "Restarted ${APP}"
  msg_ok "Updated successfully"
  exit
}

function uninstall_script() {
  msg_info "Uninstalling ${APP}"
  var_addon_install_path=$(addon_resolve_path "$var_addon_install_path") || return $?
  [[ "$var_addon_compose_file" == /* ]] || var_addon_compose_file="$var_addon_install_path/$var_addon_compose_file"
  [[ "$var_addon_env_file" == /* ]] || var_addon_env_file="$var_addon_install_path/$var_addon_env_file"
  local -a compose_env=()
  [[ ! -e "$var_addon_env_file" ]] || compose_env=(--env-file "$var_addon_env_file")

  local install_state install_project
  local -a compose_project=()
  addon_install_status install_state "$var_addon_install_path" "arcane:$var_addon_install_path" || return $?
  if [[ "$install_state" == prepared || "$install_state" == safe || "$install_state" == cleaned ]]; then
    addon_install_cleanup "$var_addon_install_path" "arcane:$var_addon_install_path" || return $?
    msg_ok "${APP} incomplete installation has been cleaned; unlisted data is retained"
    return 0
  fi
  if [[ "$install_state" != absent ]]; then
    addon_install_consumer_identity install_project "$var_addon_install_path" "arcane:$var_addon_install_path" || return $?
    compose_project=(--project-name "$install_project")
  fi
  if [[ ! -f "$var_addon_compose_file" ]]; then
    msg_error "No ${APP} installation found (${var_addon_compose_file} missing)"
    return 1
  fi
  msg_info "Stopping and removing Docker containers"
  $STD docker compose "${compose_project[@]}" --project-directory "$var_addon_install_path" "${compose_env[@]}" -f "$var_addon_compose_file" down --volumes --remove-orphans
  msg_ok "Stopped and removed Docker containers"

  if [[ "$install_state" != absent ]]; then
    addon_install_teardown_complete "$var_addon_install_path" "arcane:$var_addon_install_path"
    addon_install_cleanup "$var_addon_install_path" "arcane:$var_addon_install_path"
  else
    # Legacy installs have no fresh-attempt receipt. Successful native teardown
    # admits their selected files, never recursive authority over the root.
    rm -f -- "$var_addon_compose_file" "$var_addon_env_file"
    if [[ -d "$var_addon_install_path" && ! -L "$var_addon_install_path" ]]; then
      local child
      child=$(find "$var_addon_install_path" -mindepth 1 -maxdepth 1 -print -quit)
      if [[ -n "$child" ]]; then msg_warn "Unlisted Arcane contents retained: $var_addon_install_path"; else rmdir -- "$var_addon_install_path"; fi
    fi
  fi
  msg_ok "${APP} has been uninstalled"
}

# Addons run inside arbitrary containers that may lack curl — ensure the
# transport before sourcing the framework (everything else is bootstrapped
# by install.func from this point on)
if ! command -v curl > /dev/null 2>&1; then
  if [[ -f /etc/alpine-release ]]; then
    apk update &> /dev/null && apk add --no-cache curl &> /dev/null
  else
    apt-get update &> /dev/null && apt-get install -y curl &> /dev/null
  fi
fi
command -v curl > /dev/null 2>&1 || {
  echo "FATAL: curl is required and could not be installed" >&2
  exit 1
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/addon_lxc") --script-id arcane -- "$@"
