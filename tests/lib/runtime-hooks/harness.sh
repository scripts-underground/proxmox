#!/usr/bin/env bash
# App files declare script_type (lxc/addon), app, variants, hook_paths, and
# runtime_hooks_model/setup/assert/retry_assert callbacks, then call runtime_hooks_main.
# Callbacks share the current case variables; models run only in the cold child.
# These inputs/outputs are consumed by the sourced producers and callbacks.
# shellcheck disable=SC2034,SC2154
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/../../..")
source "$ROOT/tests/lib/runtime-hooks/contract.sh"

check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}

# External-effect models opt in by command, never by application name. Events
# describe completed model work, not native package/build or service proof.
runtime_hooks_event() {
  python3 -B - "$c/events.jsonl" "${APP_ATTEMPT:-1}" "${INIT_SYSTEM:-unknown}" "$@" << 'PY'
import json,sys
path,attempt,manager,phase,command,cwd,*argv=sys.argv[1:]
with open(path,'a') as f:
    f.write(json.dumps(dict(attempt=int(attempt),manager=manager,phase=phase,command=command,cwd=cwd,argv=argv))+'\n')
PY
}
runtime_hooks_event_count() {
  python3 -B - "$c/events.jsonl" "${observation_attempt:-1}" "$@" << 'PY'
import json,sys
from pathlib import Path
path,attempt,phase,command,cwd,*argv=sys.argv[1:]
rows=[json.loads(line) for line in Path(path).read_text().splitlines()] if Path(path).exists() else []
print(sum(row['attempt']==int(attempt) and row['phase']==phase and row['command']==command and row['cwd']==cwd and row['argv']==argv for row in rows))
PY
}
runtime_hooks_completed_assert() {
  local count
  count=$(runtime_hooks_event_count complete "$@")
  check "$((count > 0))" 1 "$app/$variant attempt ${observation_attempt:-1} completes $1 with exact inputs"
}
runtime_hooks_compose_assert() {
  local file=$1 env=$2 expected=$3 observed
  observed=$(
    python3 -B - "$c/events.jsonl" "$observation_attempt" "$file" "$env" << 'PY'
import json,sys
from pathlib import Path
path,attempt,file,env=sys.argv[1:]
rows=[json.loads(line) for line in Path(path).read_text().splitlines()] if Path(path).exists() else []
calls=[row['argv'] for row in rows if row['attempt']==int(attempt) and row['phase']=='enter' and row['command']=='docker' and row['argv'][0]=='compose' and any(action in row['argv'] for action in ('pull','up','down'))]
def operand(args,flag):
    indexes=[i for i,arg in enumerate(args) if arg==flag]
    return args[indexes[0]+1] if len(indexes)==1 and indexes[0]+1<len(args) else None
print(len(calls) if all(operand(args,'-f')==file and (operand(args,'--env-file')==env if env else '--env-file' not in args) for args in calls) else -1)
PY
  )
  check "$observed" "$expected" "$app/$variant attempt $observation_attempt exact Compose file/environment operands"
}
runtime_hooks_retained_file_assert() {
  check "$(cmp -s -- "$1" "$2" && printf preserved || printf changed)" preserved "$app/$variant failed teardown retains exact selected file"
}
runtime_hooks_observed_call() {
  local command=$1 status=0 selected=${runtime_hooks_selected_service:-} action unit
  shift
  runtime_hooks_event enter "$command" "$PWD" "$@"
  case "$command" in
    systemctl | rc-service)
      if [[ "$command" == systemctl ]]; then
        [[ "$INIT_SYSTEM" == systemd ]] || return 65
        action=$1 unit=${!#}
      else
        [[ "$INIT_SYSTEM" == openrc ]] || return 65
        local -a operands=("$@")
        [[ "${operands[0]}" != --ifstarted ]] || operands=("${operands[@]:1}")
        unit=${operands[0]} action=${operands[1]}
      fi
      [[ ! -f "$c/recovery-service" ]] || selected=$(cat "$c/recovery-service")
      case "$action" in
        show | is-active | status | start | restart | try-restart | stop | enable | disable | reload)
          [[ -z "$selected" || "${unit%.service}" == "${selected%.service}" ]] || return 65
          ;;
      esac
      ;;
  esac
  "runtime_hooks_observed_$command" "$@"
  status=$?
  [[ "$status" != 0 ]] || runtime_hooks_event complete "$command" "$PWD" "$@"
  return "$status"
}
runtime_hooks_observe_commands() {
  local command
  for command in "${runtime_hooks_observed_commands[@]}"; do
    [[ "$command" =~ ^[a-zA-Z_][a-zA-Z0-9_-]*$ ]] || return 65
    declare -F "$command" > /dev/null || return 65
    eval "$(declare -f "$command" | sed "1s/$command/runtime_hooks_observed_$command/")"
    eval "$command() { runtime_hooks_observed_call $command \"\$@\"; }"
  done
}

runtime_hooks_runtime_models() {
  c="$APP_FIXTURE"
  header_info() { :; }
  check_container_storage() { :; }
  cleanup_lxc() { :; }
  ensure_dependencies() { :; }
  get_lxc_ip() { LOCAL_IP=10.20.30.40; }
  pkg_update() { :; }
  pkg_install() { :; }
  getent() { return 0; }
  chown() { :; }
  setup_postgresql() { printf '%s\n' "${PG_VERSION:-unset}" >> "$c/db-major-calls"; }
  systemctl() {
    printf '%s\n' "$*" >> "$c/services"
    if [[ "$1" == show ]]; then printf 'LoadState=loaded\nActiveState=active\nUnitFileState=enabled\n'; fi
  }
  busctl() {
    local selected property=${!#} unit_path
    [[ -f "$c/recovery-service" ]] || return 4
    selected=$(cat "$c/recovery-service")
    selected=${selected%.service}.service
    unit_path="$c/etc/systemd/system/$selected"
    case "$*" in
      *'Manager LoadUnit s '*)
        [[ "$property" == "$selected" ]] || return 4
        printf '{"type":"o","data":["/fixture/selected"]}\n'
        ;;
      *'/fixture/selected org.freedesktop.systemd1.Unit '*)
        case "$property" in
          LoadState) printf '{"type":"s","data":"loaded"}\n' ;;
          FragmentPath) jq -cn --arg path "$unit_path" '{type:"s",data:$path}' ;;
          DropInPaths) printf '{"type":"as","data":[]}\n' ;;
          *) return 4 ;;
        esac
        ;;
      *) return 4 ;;
    esac
  }
  curl_download() {
    [[ "$APP_FAULT" != download ]] || return 22
    if [[ "$1" == *.deb ]]; then printf package > "$1"; else tar -czf "$1" -C "$c" payload; fi
  }
  cp() {
    if [[ "$APP_FAULT" == copy && "${!#}" == /opt/* ]]; then
      case "$*" in *'/deploy-source.'*)
        command cp -a -- "$3" "${!#}"
        return 41
        ;;
      esac
    fi
    command cp "$@"
  }
  runtime_hooks_model
  # Fault injection ends on a cold retry; the guest's init manager does not.
  # Keep the first selected platform independent of APP_FAULT across attempts.
  if [[ -f "$c/fixture-init-system" ]]; then
    IFS= read -r INIT_SYSTEM < "$c/fixture-init-system" || return $?
  elif [[ -n "${INIT_SYSTEM:-}" ]]; then
    printf '%s\n' "$INIT_SYSTEM" > "$c/fixture-init-system"
  fi
  runtime_hooks_observe_commands
}

# Cases opt in with the service's prior state and complete runtime footprint.
# The observer records bytes/links/modes/owners at every start, independently of
# the hook's claim that a deployment or rollback succeeded.
runtime_hooks_recovery_digest() (
  set -o pipefail
  local -a paths=()
  mapfile -d '' -t paths < "$c/recovery-paths"
  tar --sort=name --format=gnu --mtime=@0 -cf - -C / -- "${paths[@]}" | sha256sum
)
runtime_hooks_recovery_setup() {
  printf '%s\n' "$1" > "$c/recovery-service"
  printf '%s\n' "$2" > "$c/recovery-initial"
  printf '%s\n' "$2" > "$c/recovery-state"
  shift 2
  : > "$c/recovery-paths"
  local path service
  service=$(cat "$c/recovery-service")
  service=${service%.service}
  mkdir -p "$c/etc/systemd/system" "$c/etc/init.d"
  for path in "$c/etc/systemd/system/$service.service" "$c/etc/init.d/$service"; do
    [[ -e "$path" ]] || printf 'fixture service input\n' > "$path"
    printf '%s\0' "${path#/}" >> "$c/recovery-paths"
  done
  for path in "$@"; do printf '%s\0' "${path#/}" >> "$c/recovery-paths"; done
  runtime_hooks_recovery_digest > "$c/recovery-before"
  : > "$c/recovery-starts"
}
runtime_hooks_recovery_service() {
  local action=$1 service=${!#} digest
  if [[ "$action" == show ]]; then
    [[ "$service" == "$(cat "$c/recovery-service")" ]] || return 4
    printf 'LoadState=loaded\nActiveState=%s\nUnitFileState=enabled\n' "$(cat "$c/recovery-state")"
    return
  fi
  if [[ "$action" == is-active || "$action" == status ]]; then
    [[ "$service" == "$(cat "$c/recovery-service")" ]] || return 4
    [[ "$(cat "$c/recovery-state")" == active ]] && return 0
    return 3
  fi
  printf '%s %s\n' "$action" "$service" >> "$c/services"
  [[ "$service" == "$(cat "$c/recovery-service")" ]] || return 0
  case "$action" in
    stop) printf 'inactive\n' > "$c/recovery-state" ;;
    start | restart)
      digest=$(runtime_hooks_recovery_digest) || digest=unverified
      printf '%s\n' "$digest" >> "$c/recovery-starts"
      printf 'active\n' > "$c/recovery-state"
      ;;
  esac
}

# A cold retry belongs to the original operation, not to the state left behind
# by the failed attempt. App callbacks still prove their own updated consumer.
runtime_hooks_backup_assert() {
  local root=$1 input=$2 expected_bytes=$3 store
  local -a stores=()
  while IFS= read -r -d '' store; do stores+=("${store%/.manifest}"); done < <(find "$root" -mindepth 2 -maxdepth 2 -type f -name .manifest -print0)
  check "${#stores[@]}" 1 "$app/$variant one operation snapshot survives retries"
  [[ ${#stores[@]} == 1 ]] || return 0
  store=${stores[0]}
  check "$(stat -c %a "$store")" 700 "$app/$variant private backup store"
  check "$(grep -xcF -- "$input" "$store/.manifest" || true)" 1 "$app/$variant backup manifest identifies actual configured input"
  check "$(cat "$store/files$input")" "$expected_bytes" "$app/$variant actual consumed input was backed up"
  check "$(test -e "$c/addon-backup-actions/$app" && printf pending || printf retired)" retired "$app/$variant successful operation retires backup receipt"
}

runtime_hooks_retry_services_assert() {
  [[ -f "$c/recovery-service" ]] || return 0
  local desired
  case "${runtime_hooks_activation:-}" in
    intent-preserving) desired=$(cat "$c/recovery-initial") ;;
    start-on-success) desired=active ;;
    *)
      check "${runtime_hooks_activation:-undeclared}" 'intent-preserving or start-on-success' "$app/$variant service observer requires an explicit activation contract"
      return 0
      ;;
  esac
  check "$(cat "$c/recovery-state")" "$desired" "$app/$variant successful retry satisfies $runtime_hooks_activation activation"
  if [[ "$desired" == active ]]; then
    check "$(($(wc -l < "$c/recovery-starts") > retry_starts_before))" 1 "$app/$variant successful retry performs a fresh activation"
  else
    check "$(wc -l < "$c/recovery-starts")" 0 "$app/$variant successful retry never starts an initially stopped service"
  fi
}
runtime_hooks_failure_services_assert() {
  local starts digest final initial desired=inactive
  starts=$(grep -Ec '^(start|reload|restart)|--now' "$c/services" || true)
  if [[ ! -f "$c/recovery-service" ]]; then
    check "$starts" 0 "$app/$variant failure never starts dependent services"
    return
  fi
  initial=$(cat "$c/recovery-initial")
  final=$(runtime_hooks_recovery_digest) || final=unverified
  if [[ "$initial" == active && "$final" == "$(cat "$c/recovery-before")" && ! -f "$c/recovery-unverified" ]]; then desired=active; fi
  check "$(cat "$c/recovery-state")" "$desired" "$app/$variant failed update preserves safe prior service state"
  check "$starts" "$(wc -l < "$c/recovery-starts")" "$app/$variant no dependent service starts during recovery"
  while IFS= read -r digest; do
    check "$initial" active "$app/$variant recovery never starts an initially stopped service"
    check "$digest" "$(cat "$c/recovery-before")" "$app/$variant recovery starts only positively verified old runtime"
  done < "$c/recovery-starts"
}

# Framework membership and role footers come from the shared producer. This
# adapter never invokes a hook; exec discards the extraction shell's definitions.
runtime_hooks_child() {
  c="$APP_FIXTURE"
  mount --bind "$c/opt" /opt
  mount --bind "$c/local" /usr/local
  mount --bind "$c/cache" /var/cache
  mount --bind "$c/state" /var/lib/scripts-underground/update-pending
  local entry=$APP_ROLE
  [[ "$entry" != install ]] || entry=install-bundle.sh
  if [[ -f "$c/generated" ]]; then exec bash "$c/local/sbin/$entry"; fi
  source "$c/hooks.sh"
  source "$ROOT/misc/bundle.func"
  source "$ROOT/misc/addon_lxc.func"
  NSAPP=$APP_CASE REPO_BASE=https://runtime-hooks.invalid
  if [[ "$script_type" == addon ]]; then addon_init "$app"; fi
  local command hook generated_role
  local -a pipeline=()
  for generated_role in install update uninstall; do
    command="$c/local/sbin/$generated_role" hook="${generated_role}_script"
    [[ "$generated_role" != install ]] || command="$c/local/sbin/install-bundle.sh"
    declare -F "$hook" > /dev/null || continue
    pipeline=()
    case "$generated_role" in
      install)
        if [[ "$script_type" == addon ]]; then
          pipeline=('app_maintenance_begin "$NSAPP" || exit $?' addon_baseline install_script addon_marker_write)
        else pipeline=(install_script); fi
        ;;
      update) pipeline=('run_update_script "$@"') ;;
      uninstall) ;;
      *) return 65 ;;
    esac
    if [[ "$script_type" == addon ]]; then
      ADDON_MARKER_DIR="$c/addons"
      _addon_command_path() { printf '%s/local/sbin/%s\n' "$c" "$1"; }
      _addon_alias_path() { printf '%s/aliases/%s\n' "$c" "$1"; }
    fi
    _bundle_contents "$script_type" "$generated_role" "$hook" "$c/framework" --requirements 0 0 -- "${pipeline[@]}" > "$command"
    chmod 0755 "$command"
  done
  : > "$c/generated"
  exec bash "$c/local/sbin/$entry"
}

runtime_hooks_invoke() {
  local invoke_role=$1 invoke_fault=$2 output=$3 build_log=$4 errors_log=$5
  case "$invoke_role" in install | update | uninstall) ;; *) return 65 ;; esac
  observation_attempt=0
  [[ ! -f "$c/attempt" ]] || read -r observation_attempt < "$c/attempt"
  observation_attempt=$((observation_attempt + 1))
  printf '%s\n' "$observation_attempt" > "$c/attempt"
  env -i PATH="$PATH" HOME="$c/home" TMPDIR="$TMPDIR" APP_ATTEMPT="$observation_attempt" APP_FIXTURE="$c" APP_CASE="$app" APP_ROLE="$invoke_role" APP_FAULT="$invoke_fault" APP="$app" NSAPP="$app" LOCAL_IP=10.20.30.40 VERBOSE="$mode" BUILD_LOG="$build_log" DEBUG_LOGFILE="$errors_log" MAINTENANCE_REFERENCES="$MAINTENANCE_REFERENCES" \
    CASE_ROOT="$c" FAULT="$invoke_fault" RUNTIME_HOOKS_CASE="$(realpath "$0")" unshare -m --propagation private -- bash "$0" --child < "$c/stdin" > "$output" 2>&1
}

runtime_hooks_prepare() {
  mkdir -p "$c/"{opt,local/bin,local/sbin,cache,state,home,etc/systemd/system,payload,external,root,framework,aliases,addons,tmp}
  [[ -f "$c/stdin" ]] || : > "$c/stdin"
  python3 - "$ROOT" "$script_type" "$app" "$c" "${hook_paths[@]}" << 'PY'
import pathlib,re,subprocess,sys,shlex
root=pathlib.Path(sys.argv[1]);kind,app=sys.argv[2:4];c=pathlib.Path(sys.argv[4])
mapping={'/etc':str(c/'etc'),'/root':str(c/'root')}
mapping.update((key,str(c/value)) for key,value in zip(sys.argv[5::2],sys.argv[6::2],strict=True))
pattern=r'(?:(?<![A-Za-z0-9_./-])|(?<=:-))('+ '|'.join(re.escape(k) for k in sorted(mapping,key=len,reverse=True))+r')(?=/|[\s"\x27}]|$)'
text=(root/'scripts'/kind/(app+'.sh')).read_text()
(c/'source.sh').write_text(re.sub(pattern,lambda m:mapping[m[0]],text))
# Native declare-f boundary preserves heredocs and source-declared defaults.
script='curl() { :; }; [[ ! -f "$1/context.sh" ]] || source "$1/context.sh"; source "$1/source.sh"; declare -p APP; for v in ${!var_lxc_@} ${!var_addon_@}; do declare -p "$v"; done; declare -f install_script update_script; declare -f uninstall_script || true'
hooks=subprocess.check_output(['bash','-c',script,'hook-source',str(c)],text=True)
tmpvar='var_addon_tmpdir' if kind=='addon' else 'var_lxc_tmpdir'
hooks+='\n'+tmpvar+'='+shlex.quote(str(c/'tmp'))+'\n'
(c/'hooks.sh').write_text(hooks)
inventory=subprocess.check_output(['bash','-c','source "$1/misc/bundle.func"; _framework_library_inventory "$2"','inventory',str(root),kind],text=True)
names=[line.split()[0] for line in inventory.splitlines()]
for name in names:
    text=(root/'misc'/name).read_text().replace('/var/lib/scripts-underground/maintenance-locks',str(c/'maintenance-locks'))
    if name=='addon_lxc.func':
        text=text.replace('/var/lib/scripts-underground/addons',str(c/'addons'))
        text=text.replace('/var/lib/scripts-underground/addon-service-actions',str(c/'addon-service-actions'))
        text=text.replace('/var/lib/scripts-underground/addon-backup-actions',str(c/'addon-backup-actions'))
        text=text.replace('/var/lib/scripts-underground/addon-teardowns',str(c/'addon-teardowns'))
        text=text.replace('/var/lib/scripts-underground/addon-owned-files',str(c/'addon-owned-files'))
        text=text.replace('/var/lib/scripts-underground/addon-install-attempts',str(c/'addon-install-attempts'))
        text=text.replace('"/etc/', '"'+str(c/'etc')+'/')
    (c/'framework'/name).write_text(text)
# Install external-effect models after normal runtime initialization. The real
# release, pending, locking and role owners remain inlined, not fixture copies.
with (c/'framework'/names[-1]).open('a') as f:
 f.write('\nRUNTIME_HOOKS_MODELS_ONLY=1\nsource "$RUNTIME_HOOKS_CASE"\nunset RUNTIME_HOOKS_MODELS_ONLY\n')
 f.write('eval "$(declare -f load_functions | sed \'1s/load_functions/runtime_hooks_real_load_functions/\')"\n')
 f.write('load_functions() { runtime_hooks_real_load_functions; runtime_hooks_runtime_models; }\n')
PY
  if [[ "$script_type" == addon && "$role" != install ]]; then
    printf 'previous installation\n' > "$c/addons/$pending_key"
    ln -sf "$c/local/sbin/update" "$c/aliases/update"
    ln -sf "$c/local/sbin/uninstall" "$c/aliases/uninstall"
  fi
}

runtime_hooks_main() {
  case "${script_type:-}" in lxc | addon) ;; *)
    printf 'Declare script_type=lxc or addon\n' >&2
    return 65
    ;;
  esac
  runtime_hooks_contract_read "${BASH_SOURCE[1]}" || return $?
  if [[ "$runtime_hooks_contract_profile" != "$script_type" ]]; then
    printf 'Runtime hooks: activation profile %s does not match caller %s\n' "$runtime_hooks_contract_profile" "$script_type" >&2
    return 65
  fi
  [[ "${RUNTIME_HOOKS_MODELS_ONLY:-0}" != 1 ]] || return 0
  systemd-detect-virt --vm --quiet || exit 1
  : "${TMPDIR:?disk-backed TMPDIR required}" "${MAINTENANCE_REFERENCES:?immutable source metadata required}"
  case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
  if [[ "${1:-}" == --child ]]; then
    runtime_hooks_child
    exit
  fi
  pending_key=$app
  if [[ "$script_type" == addon ]]; then
    source "$ROOT/misc/addon_lxc.func"
    addon_init "$app"
    pending_key=$APP_SLUG
  fi
  work=$(mktemp -d "$TMPDIR/runtime-hooks.XXXXXX")
  trap 'rm -rf -- "$work"' EXIT
  failures=0
  for mode in no yes; do
    for variant in "${variants[@]}"; do
      c="$work/$app-$mode-$variant"
      role=update fault=none
      [[ "$variant" != fresh ]] || role=install
      case "$variant" in download | build | copy | runtime) fault="$variant" ;; esac
      runtime_hooks_variant
      mkdir -p "$c/"{opt,local/bin,cache,state,home,etc/systemd/system,payload,external,root}
      printf 'old\n' > "$c/home/.$app"
      for log in services db-major-calls; do : > "$c/$log"; done
      printf 'old PostgreSQL data\n' > "$c/external/database"
      printf 'old credential\n' > "$c/external/credential"
      printf 'new code\n' > "$c/payload/code"
      if [[ "$role" == update ]]; then
        mkdir -p "$c/opt/$app"
        printf 'old code\n' > "$c/opt/$app/code"
        printf 'USER settings\n' > "$c/opt/$app/.env"
      fi
      runtime_hooks_setup
      runtime_hooks_prepare
      env_before=''
      if [[ -f "$c/opt/$app/.env" ]]; then
        env_before=$(sha256sum "$c/opt/$app/.env")
        env_before=${env_before%% *}
      fi
      rc=0
      runtime_hooks_invoke "$role" "$fault" "$c/output" "$c/build.log" "$c/errors.log" || rc=$?
      expected=0
      case "$fault" in download) expected=250 ;; build) expected=52 ;; copy) expected=252 ;; runtime) expected=51 ;; esac
      runtime_hooks_expected
      check "$rc" "$expected" "$app/$mode/$variant cold hook status"
      if [[ "$rc" != "$expected" ]]; then
        python3 - "$c/output" "$app/$variant" << 'PY'
import pathlib,sys
lines=pathlib.Path(sys.argv[1]).read_text().splitlines()
for line in lines:
 if any(word in line for word in ('unbound variable','No such file','exit code','Unknown core','unsupported')): print('DIAG '+sys.argv[2]+' '+line)
for line in lines[-4:]:print('DIAG '+sys.argv[2]+' '+line)
PY
      fi
      check "$(cat "$c/external/database")" 'old PostgreSQL data' "$app/$variant installed DB bytes retained"
      check "$(cat "$c/external/credential")" 'old credential' "$app/$variant external credential retained"
      if [[ "$role" == update ]]; then
        check "$(stat -c %s "$c/db-major-calls")" 0 "$app/$variant no installed DB major provisioning"
        check "$(test -f "$c/state/$pending_key" && printf present || printf absent)" "$([[ "$expected" == 0 ]] && printf absent || printf present)" "$app/$variant pending flag reflects actual outcome"
      fi
      if [[ "$rc" != 0 ]]; then runtime_hooks_failure_services_assert; fi
      runtime_hooks_assert
      if [[ "$rc" == 0 ]]; then
        runtime_hooks_deployment_assert
        if [[ "${runtime_hooks_observe_recovery:-0}" == 1 && "$role" == update && "$variant" != *no-update ]]; then
          retry_starts_before=0
          runtime_hooks_retry_services_assert
        fi
      fi
      if [[ "$script_type" == addon && "$role" == uninstall ]]; then runtime_hooks_uninstall_assert; fi
      if runtime_hooks_retry_needed; then
        if [[ "$script_type" == addon ]]; then command_before=$(sha256sum "$c/local/sbin/update"); fi
        retry=0
        retry_starts_before=0
        [[ ! -f "$c/recovery-starts" ]] || retry_starts_before=$(wc -l < "$c/recovery-starts")
        runtime_hooks_invoke update none "$c/retry-output" "$c/retry.log" "$c/retry-errors.log" || retry=$?
        check "$retry" 0 "$app/$variant cold pending retry succeeds"
        check "$(test -f "$c/state/$pending_key" && printf present || printf absent)" absent "$app/$variant successful retry clears pending flag"
        check "$(cat "$c/external/database")" 'old PostgreSQL data' "$app/$variant retry preserves installed DB bytes"
        runtime_hooks_retry_assert
        runtime_hooks_deployment_assert
        runtime_hooks_retry_services_assert
        if [[ "$script_type" == addon ]]; then check "$(sha256sum "$c/local/sbin/update")" "$command_before" "$app/$variant pending retry uses the same frozen command"; fi
      fi
    done
  done
  runtime_hooks_more_cases
  printf '%s failure(s); original cold hooks/helpers/files/config readers; external build/runtime/DB/service models\n' "$failures"
  printf 'RUNTIME_HOOKS_RESULT failures=%s\n' "$failures"
  [[ "$failures" == 0 ]]
}

runtime_hooks_expected() { :; }
runtime_hooks_variant() { :; }
runtime_hooks_more_cases() { :; }
runtime_hooks_uninstall_assert() {
  local outcome=present
  [[ "$rc" != 0 ]] || outcome=absent
  local path
  for path in "local/sbin/update" "local/sbin/uninstall" aliases/update aliases/uninstall "addons/$pending_key"; do
    check "$({ test -e "$c/$path" || test -L "$c/$path"; } && printf present || printf absent)" "$outcome" "$app/$mode/$variant generated uninstall owns $path retirement"
  done
}
runtime_hooks_retry_needed() { [[ "$role" == update && "$expected" != 0 ]]; }
runtime_hooks_retry_assert() { :; }
runtime_hooks_observed_commands=()
runtime_hooks_deployment_assert() { :; }
runtime_hooks_configuration_assert() {
  if [[ "$role" == update ]]; then
    after=$(sha256sum "$c/opt/$app/.env" 2> /dev/null) || after=missing
    check "${after%% *}" "$env_before" "$app/$variant complete existing configuration retained"
  fi
}
