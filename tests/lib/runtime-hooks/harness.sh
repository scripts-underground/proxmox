#!/usr/bin/env bash
# App files declare app, variants, hook_paths (source/fixture-relative pairs), and
# runtime_hooks_model/setup/assert/retry_assert callbacks, then call runtime_hooks_main.
# Callbacks share the current case variables; models run only in the cold child.
# App files declare the three inputs before calling runtime_hooks_main.
# shellcheck disable=SC2154
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/../../..")

check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}

runtime_hooks_child() {
  c="$APP_FIXTURE"
  mount --bind "$c/opt" /opt
  mount --bind "$c/local" /usr/local
  mount --bind "$c/cache" /var/cache
  mount --bind "$c/state" /var/lib/scripts-underground/update-pending
  # shellcheck source=/dev/null
  source <(sed "s|/var/lib/scripts-underground/maintenance-locks|$c/maintenance-locks|g" "$ROOT/misc/core.func")
  source "$ROOT/misc/error_handler.func"
  source "$ROOT/misc/tools.func"
  load_functions
  source "$c/hooks.sh"
  header_info() { :; }
  check_container_storage() { :; }
  export LXC_REQUIRED_CPU=0 LXC_REQUIRED_RAM=0
  cleanup_lxc() { :; }
  ensure_dependencies() { :; }
  getent() { return 0; }
  chown() { :; }
  setup_postgresql() { printf '%s\n' "${PG_VERSION:-unset}" >> "$c/db-major-calls"; }
  systemctl() { printf '%s\n' "$*" >> "$c/services"; }
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
  catch_errors
  if [[ "$APP_ROLE" == install ]]; then install_script; else run_update_script; fi
}

runtime_hooks_invoke() {
  local invoke_role=$1 invoke_fault=$2 output=$3 build_log=$4 errors_log=$5
  env -i PATH="$PATH" HOME="$c/home" TMPDIR="$TMPDIR" APP_FIXTURE="$c" APP_CASE="$app" APP_ROLE="$invoke_role" APP_FAULT="$invoke_fault" APP="$app" NSAPP="$app" LOCAL_IP=10.20.30.40 VERBOSE="$mode" BUILD_LOG="$build_log" DEBUG_LOGFILE="$errors_log" MAINTENANCE_REFERENCES="$MAINTENANCE_REFERENCES" \
    unshare -m --propagation private -- bash "$0" --child < /dev/null > "$output" 2>&1
}

runtime_hooks_main() {
  systemd-detect-virt --vm --quiet || exit 1
  : "${TMPDIR:?disk-backed TMPDIR required}" "${MAINTENANCE_REFERENCES:?immutable source metadata required}"
  case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
  if [[ "${1:-}" == --child ]]; then
    runtime_hooks_child
    exit
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
      python3 - "$ROOT/scripts/lxc/$app.sh" "$c" "${hook_paths[@]}" << 'PY'
import pathlib,re,subprocess,sys
p=pathlib.Path(sys.argv[1]);c=pathlib.Path(sys.argv[2])
# Use the same native declare-f boundary as real bundles; heredoc braces are data.
hooks=subprocess.check_output(['bash','-c','curl() { :; }; source "$1"; declare -f install_script update_script','hook-source',str(p)],text=True)
mapping={'/etc':str(c/'etc'),'/root':str(c/'root')}
mapping.update((key,str(c/value)) for key,value in zip(sys.argv[3::2],sys.argv[4::2],strict=True))
pattern=r'(?<![A-Za-z0-9_./-])('+ '|'.join(re.escape(k) for k in sorted(mapping,key=len,reverse=True))+r')(?=/|[\s"\x27]|$)';hooks=re.sub(pattern,lambda m:mapping[m[0]],hooks);(c/'hooks.sh').write_text(hooks)
PY
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
        check "$(test -f "$c/state/$app" && printf present || printf absent)" "$([[ "$expected" == 0 ]] && printf absent || printf present)" "$app/$variant pending flag reflects actual outcome"
      fi
      if [[ "$rc" != 0 ]]; then check "$(grep -Ec '^(start|reload|restart)|--now' "$c/services" || true)" 0 "$app/$variant failure never starts dependent services"; fi
      runtime_hooks_assert
      if runtime_hooks_retry_needed; then
        retry=0
        runtime_hooks_invoke update none "$c/retry-output" "$c/retry.log" "$c/retry-errors.log" || retry=$?
        check "$retry" 0 "$app/$variant cold pending retry succeeds"
        check "$(test -f "$c/state/$app" && printf present || printf absent)" absent "$app/$variant successful retry clears pending flag"
        check "$(cat "$c/external/database")" 'old PostgreSQL data' "$app/$variant retry preserves installed DB bytes"
        runtime_hooks_retry_assert
      fi
    done
  done
  printf '%s failure(s); original cold hooks/helpers/files/config readers; external build/runtime/DB/service models\n' "$failures"
  printf 'RUNTIME_HOOKS_RESULT failures=%s\n' "$failures"
  [[ "$failures" == 0 ]]
}

runtime_hooks_expected() { :; }
runtime_hooks_retry_needed() { [[ "$role" == update && "$expected" != 0 ]]; }
runtime_hooks_retry_assert() { :; }
runtime_hooks_configuration_assert() {
  if [[ "$role" == update ]]; then
    after=$(sha256sum "$c/opt/$app/.env" 2> /dev/null) || after=missing
    check "${after%% *}" "$env_before" "$app/$variant complete existing configuration retained"
  fi
}
