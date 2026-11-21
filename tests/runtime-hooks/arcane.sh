#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/harness.sh"
app=arcane script_type=addon
runtime_hooks_observed_commands=(docker)
variants=(fresh custom-identity partial-identity numeric-user projects-denied builds-denied identity-invalid unsupported occupied invalid-port old-compose download env-download invalid-compose env-publish-failure publish-failure update optional-env pull-failure uninstall down-failure missing)
hook_paths=()
runtime_hooks_variant() {
  case "$variant" in
    custom-identity | partial-identity | numeric-user | projects-denied | builds-denied | identity-invalid | unsupported | occupied | invalid-port | old-compose | download | env-download | invalid-compose | env-publish-failure | publish-failure) role=install fault=$variant ;;
    pull-failure) fault=pull ;;
    uninstall) role=uninstall ;;
    down-failure) role=uninstall fault=down ;;
  esac
}
runtime_hooks_setup() {
  mkdir -p "$c/opt/arcane" "$c/external/selected files" "$c/etc/arcane/projects" "$c/etc/arcane/builds"
  printf 'var_addon_compose_file=%q\nvar_addon_env_file=%q\nvar_addon_default_port=%q\n' "$c/external/selected files/stack.json" "$c/external/selected files/private.env" "$([[ "$variant" == invalid-port ]] && printf invalid || printf 13552)" > "$c/context.sh"
  if [[ "$role" != install || "$variant" == occupied ]]; then
    printf '{"services":{"arcane":{"image":"operator-arcane"}}}\n' > "$c/external/selected files/stack.json"
    printf 'operator secret\n' > "$c/external/selected files/private.env"
  fi
  [[ "$variant" != missing ]] || rm "$c/external/selected files/stack.json"
  [[ "$variant" != optional-env ]] || rm "$c/external/selected files/private.env"
  printf 'foreign compose\n' > "$c/external/selected files/foreign.yaml"
  [[ ! -f "$c/external/selected files/stack.json" ]] || cp "$c/external/selected files/stack.json" "$c/selected-before"
  printf 'operator project\n' > "$c/etc/arcane/projects/data"
  printf 'operator build\n' > "$c/etc/arcane/builds/data"
  : > "$c/docker"
  : > "$c/ownership"
  : > "$c/dependencies"
  : > "$c/access"
  stat -c '%u:%g:%a' "$c/etc/arcane/projects" "$c/etc/arcane/builds" > "$c/metadata-before"
}
runtime_hooks_model() {
  [[ "$APP_FAULT" != unsupported ]] || OS_FAMILY=arch
  ensure_dependencies() { printf '%s\n' "$*" >> "$c/dependencies"; }
  chown() { printf '%s\n' "$*" >> "$c/ownership"; }
  setpriv() {
    printf '%s\n' "$PWD" >> "$c/access"
    printf '%s\0' "$@" >> "$c/access-argv"
    [[ "$APP_FAULT" != projects-denied || "$PWD" != "$var_addon_proj_dir" ]] || return 1
    [[ "$APP_FAULT" != builds-denied || "$PWD" != "$var_addon_builds_dir" ]] || return 1
  }
  mv() {
    [[ "$APP_FAULT" != publish-failure || "${!#}" != "$var_addon_compose_file" ]] || return 41
    command mv "$@"
  }
  ln() {
    [[ "$APP_FAULT" != env-publish-failure || "${!#}" != "$var_addon_env_file" ]] || return 42
    [[ "$APP_FAULT" != publish-failure || "${!#}" != "$var_addon_compose_file" ]] || return 41
    command ln "$@"
  }
  curl() {
    local out='' url=''
    while (($#)); do
      case "$1" in
        -o)
          out=$2
          shift
          ;;
        https:*) url=$1 ;;
      esac
      shift
    done
    if [[ "$url" == *env.example ]]; then
      printf 'ARCANE_APP_URL=https://your-domain.com\nARCANE_ENCRYPTION_KEY=placeholder\nARCANE_PORT=3552\n' > "$out"
      [[ "$APP_FAULT" != env-download ]] || return 23
    else
      printf '%s\n' '{"name":"arcane","services":{"arcane":{"image":"getarcaneapp/manager:latest","ports":[{"target":3552,"published":"3552"}],"environment":["ARCANE_ENCRYPTION_KEY=placeholder","ARCANE_PROJECTS_DIRECTORY=/host/path/to/projects","OPERATOR","EXPRESSION=${OPERATOR_VALUE:-a=b}"],"volumes":[{"type":"bind","source":"/host/path/to/projects","target":"/host/path/to/projects"},{"type":"bind","source":"/host/path/to/builds","target":"/builds"}]}}}' > "$out"
      [[ "$APP_FAULT" != download ]] || return 22
    fi
  }
  docker() {
    printf '%s\n' "$*" >> "$c/docker"
    if [[ "$*" == 'compose config --help' ]]; then
      [[ "$APP_FAULT" == old-compose ]] || printf '      --no-env-resolution  Retain env_file\n      --no-interpolate  Retain expressions\n      --no-path-resolution  Retain relative paths\n'
      return 0
    fi
    [[ "$APP_FAULT" != old-compose || " $* " != *' --no-env-resolution '* ]] || return 16
    [[ "$1 ${2:-}" != 'container inspect' ]] || return 1
    [[ "$APP_FAULT" != pull || " $* " != *' pull '* ]] || return 47
    [[ "$APP_FAULT" != down || " $* " != *' down '* ]] || return 48
    [[ "$APP_FAULT" != invalid-compose || " $* " != *' config '* ]] || return 49
    [[ "$APP_FAULT" != up-failure || " $* " != *' up '* ]] || return 52
    if [[ "$*" == *'--format json'* ]]; then
      local file=''
      while (($#)); do
        [[ "$1" != -f ]] || {
          file=$2
          shift
        }
        shift
      done
      case "$APP_FAULT" in
        custom-identity) jq '.services.arcane.environment |= (if type == "array" then . + ["PUID=1234","PGID=2345"] else . + {PUID:"1234",PGID:"2345"} end)' "$file" ;;
        partial-identity) jq '.services.arcane.environment |= (if type == "array" then . + ["PUID=1234"] else . + {PUID:"1234"} end)' "$file" ;;
        numeric-user) jq '.services.arcane.user = "1234:2345"' "$file" ;;
        identity-invalid) jq '.services.arcane.environment |= (if type == "array" then . + ["PUID=invalid","PGID=2345"] else . + {PUID:"invalid",PGID:"2345"} end)' "$file" ;;
        *) jq '.name = (.name // "arcane")' "$file" ;;
      esac
    fi
  }
}
runtime_hooks_expected() {
  case "$variant" in
    unsupported) expected=1 ;;
    occupied | invalid-port) expected=65 ;;
    download) expected=22 ;;
    env-download) expected=23 ;;
    missing) expected=1 ;;
    pull-failure) expected=47 ;;
    down-failure) expected=48 ;;
    invalid-compose) expected=49 ;;
    old-compose) expected=69 ;;
    publish-failure) expected=41 ;;
    env-publish-failure) expected=42 ;;
    projects-denied | builds-denied) expected=73 ;;
    identity-invalid) expected=65 ;;
  esac
}
runtime_hooks_assert() {
  local file="$c/external/selected files/stack.json" env="$c/external/selected files/private.env"
  if [[ "$role" == install ]]; then
    check "$(stat -c '%u:%g:%a' "$c/etc/arcane/projects" "$c/etc/arcane/builds")" "$(cat "$c/metadata-before")" "$app/$variant existing directory metadata is unchanged"
  fi
  case "$variant" in
    fresh | custom-identity | partial-identity | numeric-user | projects-denied | builds-denied)
      local uid=65532 gid=65532
      if [[ "$variant" == custom-identity || "$variant" == numeric-user ]]; then uid=1234 gid=2345; fi
      check "$(grep -xcF -- "$c/etc/arcane/projects" "$c/access" || true)" 1 "$app/$variant selected project access is checked"
      if [[ "$variant" != projects-denied ]]; then
        check "$(grep -xcF -- "$c/etc/arcane/builds" "$c/access" || true)" 1 "$app/$variant selected build access is checked"
      fi
      if [[ -f "$c/access-argv" ]]; then
        check "$(tr '\0' '\n' < "$c/access-argv" | grep -xcF -- "--reuid=$uid" || true)" "$(wc -l < "$c/access")" "$app/$variant native access uses configured runtime UID"
        check "$(tr '\0' '\n' < "$c/access-argv" | grep -xcF -- "--regid=$gid" || true)" "$(wc -l < "$c/access")" "$app/$variant native access uses configured runtime GID"
      fi
      ;;
  esac
  if [[ "$variant" == fresh ]]; then
    for flag in --no-interpolate --no-env-resolution --no-path-resolution; do
      check "$(grep -Fc -- "$flag" "$c/docker" || true)" 1 "$app publication retains native source semantics: $flag"
    done
    check "$(jq -r '.services.arcane.ports[0].published' "$file" 2> /dev/null || true)" 13552 "$app fresh configured listener reaches compose consumer"
    check "$(sed -n 's/^ARCANE_ENCRYPTION_KEY=//p' "$env" | tr -d '\n' | wc -c)" 32 "$app fresh upstream encryption setting receives generated secret"
    check "$(jq -r '.services.arcane.environment.ARCANE_ENCRYPTION_KEY' "$file" 2> /dev/null || true)" '${ARCANE_ENCRYPTION_KEY}' "$app compose retains operator environment interpolation"
    check "$(stat -c %a "$file")" 600 "$app secret-bearing compose is private"
    check "$(stat -c %a "$env")" 600 "$app selected runtime environment is private"
    check "$(jq -r '.services.arcane.volumes[] | select(.target=="/builds") | .source' "$file" 2> /dev/null || true)" "$c/etc/arcane/builds" "$app selected build bind reaches compose consumer"
    check "$(jq -r '.services.arcane.environment.ARCANE_PROJECTS_DIRECTORY' "$file" 2> /dev/null || true)" "$c/etc/arcane/projects" "$app selected projects directory reaches runtime"
    check "$(jq -r '.services.arcane.env_file[0].path' "$file" 2> /dev/null || true)" "$env" "$app explicit environment reaches runtime, not only interpolation"
    check "$(jq -r '.services.arcane.environment | has("OPERATOR") and .OPERATOR == null' "$file" 2> /dev/null || true)" true "$app bare-key environment retains native inheritance"
    check "$(jq -r '.services.arcane.environment.EXPRESSION' "$file" 2> /dev/null || true)" '${OPERATOR_VALUE:-a=b}' "$app environment assignment keeps equals and interpolation"
  fi
  case "$variant" in
    unsupported | occupied | invalid-port) check "$(stat -c %s "$c/docker")" 0 "$app/$variant refuses before Docker effects" ;;
    projects-denied | builds-denied | identity-invalid | old-compose | download | env-download | invalid-compose | env-publish-failure | publish-failure)
      check "$(test -e "$file" && printf present || printf absent)" absent "$app/$variant incomplete preparation never publishes compose"
      check "$(test -e "$env" && printf present || printf absent)" absent "$app/$variant incomplete preparation never publishes environment"
      if [[ "$variant" == projects-denied || "$variant" == builds-denied || "$variant" == identity-invalid ]]; then
        check "$(grep -c ' up ' "$c/docker" || true)" 0 "$app/$variant refusal precedes startup"
      fi
      if [[ "$variant" == old-compose ]]; then
        check "$(stat -c %s "$c/dependencies")" 0 "$app capability refusal precedes dependency/configuration effects"
      fi
      ;;
    update | optional-env | pull-failure | uninstall | down-failure)
      runtime_hooks_compose_assert "$file" "$([[ "$variant" == optional-env ]] || printf '%s' "$env")" "$([[ "$variant" == update || "$variant" == optional-env ]] && printf 2 || printf 1)"
      check "$(grep -Fc -- "-f $file" "$c/docker" || true)" "$([[ "$variant" == update || "$variant" == optional-env ]] && printf 2 || printf 1)" "$app/$variant all compose operations select configured file"
      if [[ "$variant" != optional-env ]]; then
        check "$(grep -Fc -- "--env-file $env" "$c/docker" || true)" "$([[ "$variant" == update ]] && printf 2 || printf 1)" "$app/$variant all compose operations select configured env"
      fi
      ;;
  esac
  if [[ "$variant" == optional-env ]]; then
    check "$(grep -Fc -- '--env-file' "$c/docker" || true)" 0 "$app missing optional legacy environment is not required"
  fi
  if [[ "$variant" == down-failure ]]; then
    runtime_hooks_retained_file_assert "$file" "$c/selected-before"
  fi
  if [[ "$role" != install && "$variant" != uninstall && "$variant" != optional-env ]]; then
    check "$(stat -c %s "$c/ownership")" 0 "$app/$variant maintenance never recursively takes operator data ownership"
    check "$(cat "$env" 2> /dev/null || true)" 'operator secret' "$app/$variant retains operator environment"
  fi
  check "$(cat "$c/etc/arcane/projects/data")" 'operator project' "$app/$variant retains external project data"
  check "$(cat "$c/etc/arcane/builds/data")" 'operator build' "$app/$variant retains external build data"
  check "$(cat "$c/external/selected files/foreign.yaml")" 'foreign compose' "$app/$variant retains unrelated external file"
  if [[ "$variant" == uninstall ]]; then
    check "$(test -e "$file" && printf present || printf absent)" absent "$app successful teardown retires only selected compose"
    check "$(test -e "$env" && printf present || printf absent)" absent "$app successful teardown retires only selected environment"
  fi
  check "$(find "$c/external/selected files" -maxdepth 1 -name '.arcane-*' | wc -l)" 0 "$app/$variant retires exact preparation stages"
}
runtime_hooks_retry_needed() { return 1; }
runtime_hooks_more_cases() {
  local install_status uninstall_status
  for mode in no yes; do
    for variant in download publish-failure up-failure exposed-missing renamed-project; do
      c="$work/arcane-partial-$mode-$variant"
      role=install fault=$variant
      [[ "$variant" != exposed-missing ]] || fault=up-failure
      [[ "$variant" != renamed-project ]] || fault=up-failure
      mkdir -p "$c/opt" "$c/local/bin" "$c/home"
      : > "$c/services"
      runtime_hooks_setup
      runtime_hooks_prepare
      install_status=0
      runtime_hooks_invoke install "$fault" "$c/output" "$c/build.log" "$c/errors.log" || install_status=$?
      check "$install_status" "$([[ "$variant" == download ]] && printf 22 || { [[ "$variant" == publish-failure ]] && printf 41 || printf 52; })" "$app/$variant install fails at intended phase"
      printf 'operator root data\n' > "$c/opt/arcane/operator"
      if [[ "$variant" == exposed-missing ]]; then rm "$c/external/selected files/stack.json"; fi
      if [[ "$variant" == renamed-project ]]; then
        jq '.name = "operator-other-project"' "$c/external/selected files/stack.json" > "$c/renamed.json"
        cat "$c/renamed.json" > "$c/external/selected files/stack.json"
      fi
      : > "$c/docker"
      uninstall_status=0
      runtime_hooks_invoke uninstall none "$c/uninstall-output" "$c/uninstall.log" "$c/uninstall-errors.log" || uninstall_status=$?
      check "$uninstall_status" "$([[ "$variant" == exposed-missing ]] && printf 1 || printf 0)" "$app/$variant cold bounded uninstall recovery"
      check "$(cat "$c/opt/arcane/operator")" 'operator root data' "$app/$variant operator root data retained"
      if [[ "$variant" == exposed-missing ]]; then
        check "$(test -x "$c/local/sbin/uninstall" && printf present || printf absent)" present "$app/$variant ambiguous exposure retains recovery command"
        check "$(test -f "$c/external/selected files/private.env" && printf present || printf absent)" present "$app/$variant ambiguous exposure preserves env"
      else
        if [[ "$variant" == renamed-project ]]; then
          check "$(jq -r '.name' "$c/external/selected files/stack.json" 2> /dev/null || true)" operator-other-project "$app/$variant edited model retained"
          check "$(grep -Fc -- '--project-name arcane' "$c/docker" || true)" 1 "$app/$variant teardown targets original exposed project, not edited name"
        else
          check "$(test -e "$c/external/selected files/stack.json" && printf present || printf absent)" absent "$app/$variant selected model retired"
        fi
        check "$(test -e "$c/external/selected files/private.env" && printf present || printf absent)" absent "$app/$variant selected environment retired"
        check "$(test -e "$c/local/sbin/uninstall" && printf present || printf absent)" absent "$app/$variant successful recovery retires commands"
        check "$(test -e "$c/addon-install-attempts/arcane" && printf present || printf absent)" absent "$app/$variant successful footer retires install custody"
      fi
      check "$(grep -c ' down ' "$c/docker" || true)" "$([[ "$variant" == up-failure || "$variant" == renamed-project ]] && printf 1 || printf 0)" "$app/$variant native teardown only after possible exposure with valid manifest"
    done
  done
}
runtime_hooks_main "$@"
