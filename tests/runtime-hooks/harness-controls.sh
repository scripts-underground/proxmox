#!/usr/bin/env bash
# runtime-hooks-contract: fixture case-asserted
# Negative controls for the shared role/retirement owner, not app qualification.
# shellcheck disable=SC2034
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/harness.sh"
systemd-detect-virt --vm --quiet || exit 1
: "${TMPDIR:?disk-backed TMPDIR required}"
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
work=$(mktemp -d "$TMPDIR/runtime-hooks-owner-controls.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT
failures=0
script_type=unknown
status=0
runtime_hooks_main > "$work/type-output" 2>&1 || status=$?
check "$status" 65 'harness rejects undeclared script profiles'
for declaration in missing wrong-profile addon-start invalid; do
  printf '#!/usr/bin/env bash\n' > "$work/contract-probe.sh"
  case "$declaration" in
    wrong-profile) printf '# runtime-hooks-contract: fixture case-asserted\n' >> "$work/contract-probe.sh" ;;
    addon-start) printf '# runtime-hooks-contract: addon start-on-success\n' >> "$work/contract-probe.sh" ;;
    invalid) printf '# runtime-hooks-contract: addon unknown\n' >> "$work/contract-probe.sh" ;;
  esac
  cat >> "$work/contract-probe.sh" << 'PROBE'
source "$1/tests/lib/runtime-hooks/harness.sh"
app=fixture script_type=addon
variants=() hook_paths=()
runtime_hooks_main
PROBE
  status=0
  bash "$work/contract-probe.sh" "$ROOT" > "$work/contract-$declaration-output" 2>&1 || status=$?
  check "$status" 65 "direct harness rejects activation declaration/$declaration"
done
c="$work/case" app=fixture mode=no variant=dangling rc=0 pending_key=fixture
status=0
(
  env() { return 97; }
  runtime_hooks_invoke unknown none "$work/output" "$work/build.log" "$work/errors.log"
) || status=$?
check "$status" 65 'harness rejects unknown roles before execution'
mkdir -p "$c/aliases"
ln -s "$c/missing-update" "$c/aliases/update"
ln -s "$c/missing-uninstall" "$c/aliases/uninstall"
# The shared assertion must diagnose both links, even after targets disappeared.
prior_failures=$failures
runtime_hooks_uninstall_assert > "$work/alias-output" 2>&1
observed=$((failures - prior_failures))
failures=$prior_failures
check "$observed" 2 'harness detects both dangling aliases after successful uninstall'
rm "$c/aliases/update" "$c/aliases/uninstall"
runtime_hooks_uninstall_assert > "$work/removed-output" 2>&1
check "$failures" "$prior_failures" 'harness accepts actual alias retirement'
# Inspect the same source-declared defaults used by cold app commands. Mapping
# coordinates must not depend on whether a path is literal or a shell fallback.
script_type=addon app=filebrowser role=update pending_key=file-browser
c="$work/defaults"
hook_paths=(/usr/local libexec /opt applications)
runtime_hooks_prepare
defaults=$(bash -c 'source "$1/hooks.sh"; printf "%s\n" "$var_addon_bin_path" "$var_addon_dist_path"' defaults "$c")
check "$defaults" "$c/libexec/bin/filebrowser
$c/applications/filebrowser-dist" 'harness maps source-declared parameter default paths'
check "$(grep -cF "$c/etc/systemd/system/filebrowser.service" "$c/source.sh")" 2 'harness retains literal path mapping'
c="$work/exact-defaults"
hook_paths=(/usr/local/bin/filebrowser bin/custom-filebrowser)
runtime_hooks_prepare
defaults=$(bash -c 'source "$1/hooks.sh"; printf "%s\n" "$var_addon_bin_path"' defaults "$c")
check "$defaults" "$c/bin/custom-filebrowser" 'harness maps exact-file defaults at the closing parameter brace'
status=0
python3 -B "$ROOT/tests/lib/framework_fixture.py" "$ROOT" --audit > "$work/framework-audit" 2>&1 || status=$?
check "$status" 0 'app fixtures do not hand-roll install framework APIs'
status=0
python3 -B - "$ROOT" "$work" << 'PY' || status=$?
from pathlib import Path
import sys
sys.path.insert(0,str(Path(sys.argv[1])/'tests/lib'))
from framework_fixture import minimal_install_models
root=Path(sys.argv[2])/'audit-control'
(root/'tests').mkdir(parents=True)
(root/'tests/new-app.sh').write_text('printf "setup_lxc() { :; }" > install.func\n')
assert minimal_install_models(root)==['new-app.sh']
(root/'tests/keyword-form.sh').write_text('printf "function pkg_install { :; }" > install.func\n')
assert minimal_install_models(root)==['keyword-form.sh','new-app.sh']
PY
check "$status" 0 'framework audit rejects another incomplete app stub'
python3 -B "$ROOT/tests/lib/framework_fixture.py" "$ROOT" --explicit-platform > "$work/install-probe.sh"
platform=$(env -i PATH="$PATH" TMPDIR="$TMPDIR" INIT_SYSTEM=openrc OS_FAMILY=alpine bash -ec '
  _INSTALL_DEFER_BOOTSTRAP=1
  source "$1"
  _bootstrap
  detect_os
  declare -F svc_prepare_uninstall pkg_clean >/dev/null
  printf "%s/%s" "$OS_FAMILY" "$INIT_SYSTEM"
' fixture "$work/install-probe.sh")
check "$platform" alpine/openrc 'complete framework fixture retains explicit platform matrix inputs'
source "$ROOT/tests/lib/service-fixture.sh"
fixture_service_state stop "$work/service-state"
check "$(cat "$work/service-state")" stopped 'service fixture records stop'
printf '#!/usr/bin/env bash\nprintf new-consumer\n' > "$work/executable"
fixture_service_state restart "$work/service-state" bash "$work/executable" > "$work/service-consumer"
check "$(cat "$work/service-state")" running 'service fixture records restart activation'
check "$(cat "$work/service-consumer")" new-consumer 'service fixture restart consumes published executable'
fixture_service_state stop "$work/service-state"
status=0
fixture_service_state restart "$work/service-state" bash -c 'exit 47' || status=$?
check "$status" 47 'service fixture preserves activation failure'
check "$(cat "$work/service-state")" stopped 'service fixture does not declare failed activation running'
printf running > "$work/service-state"
status=0
fixture_service_state restart "$work/service-state" bash -c 'exit 47' || status=$?
check "$status" 47 'service fixture preserves failed replacement status for a running unit'
check "$(cat "$work/service-state")" stopped 'service fixture stops the old consumer before a failed restart'
mkdir -p "$c/app"
for contract in missing-recovery stopped-start partial-start restored-running retained-stopped unverified-stopped; do
  printf 'old code\n' > "$c/app/code"
  : > "$c/services"
  initial=active expected_bad=0
  case "$contract" in stopped-start | retained-stopped) initial=inactive ;; esac
  runtime_hooks_recovery_setup fixture "$initial" "$c/app"
  case "$contract" in
    missing-recovery)
      runtime_hooks_recovery_service stop fixture
      expected_bad=1
      ;;
    stopped-start)
      runtime_hooks_recovery_service start fixture
      expected_bad=1
      ;;
    partial-start)
      runtime_hooks_recovery_service stop fixture
      printf 'partial code\n' > "$c/app/code"
      runtime_hooks_recovery_service start fixture
      expected_bad=1
      ;;
    restored-running)
      runtime_hooks_recovery_service stop fixture
      runtime_hooks_recovery_service start fixture
      ;;
    unverified-stopped)
      runtime_hooks_recovery_service stop fixture
      printf 'partial code\n' > "$c/app/code"
      ;;
  esac
  prior_failures=$failures
  runtime_hooks_failure_services_assert > "$work/$contract-output" 2>&1
  observed=$((failures - prior_failures))
  failures=$prior_failures
  check "$((observed > 0))" "$expected_bad" "harness recovery contract/$contract"
done
if ! declare -F runtime_hooks_event runtime_hooks_event_count runtime_hooks_completed_assert runtime_hooks_observe_commands > /dev/null; then
  check missing present 'harness provides lossless attempt-bound observation APIs'
else
  c="$work/observations" app=fixture variant=observation observation_attempt=1
  mkdir -p "$c"
  APP_ATTEMPT=1 INIT_SYSTEM=systemd
  runtime_hooks_event complete npm "$PWD" ci 'path with spaces' $'line\nbreak' ''
  check "$(runtime_hooks_event_count complete npm "$PWD" ci 'path with spaces' $'line\nbreak' '')" 1 'events preserve complete argument boundaries'
  check "$(runtime_hooks_event_count complete npm "$PWD" ci path with spaces $'line\nbreak' '')" 0 'events reject split path operands'
  observation_attempt=2
  prior_failures=$failures
  runtime_hooks_completed_assert npm "$PWD" ci 'path with spaces' $'line\nbreak' '' > "$work/stale-event" 2>&1
  observed=$((failures - prior_failures)) failures=$prior_failures
  check "$observed" 1 'first-attempt completion cannot satisfy cold retry'
  APP_ATTEMPT=2
  runtime_hooks_event complete npm "$PWD" ci 'path with spaces' $'line\nbreak' ''
  runtime_hooks_completed_assert npm "$PWD" ci 'path with spaces' $'line\nbreak' ''
  runtime_hooks_observed_commands=(systemctl rc-service npm)
  runtime_hooks_selected_service=fixture
  systemctl() { :; }
  rc-service() { :; }
  npm() { return 53; }
  runtime_hooks_observe_commands
  for control in wrong-init wrong-unit failed-build; do
    status=0
    case "$control" in
      wrong-init) rc-service fixture start > "$work/$control" 2>&1 || status=$? ;;
      wrong-unit) systemctl start foreign > "$work/$control" 2>&1 || status=$? ;;
      failed-build) npm ci > "$work/$control" 2>&1 || status=$? ;;
    esac
    check "$status" "$([[ "$control" == failed-build ]] && printf 53 || printf 65)" "observation rejects $control"
  done
  check "$(runtime_hooks_event_count complete npm "$PWD" ci)" 0 'failed build never records successful work'
  check "$(runtime_hooks_event_count enter npm "$PWD" ci)" 1 'failed build still records attempted work'
  npm() { :; }
  systemctl() { :; }
  rc-service() { :; }
  runtime_hooks_observe_commands
  npm ci
  check "$(runtime_hooks_event_count complete npm "$PWD" ci)" 1 'runtime model reload reattaches completion observation'
  observation_attempt=3 APP_ATTEMPT=3
  prior_failures=$failures
  runtime_hooks_completed_assert npm "$PWD" run build > "$work/skipped-build" 2>&1
  observed=$((failures - prior_failures)) failures=$prior_failures
  check "$observed" 1 'skipping required build cannot satisfy successful deployment'
  prior_failures=$failures
  runtime_hooks_completed_assert _deploy_release_deb "$PWD" 'selected package' > "$work/skipped-install" 2>&1
  observed=$((failures - prior_failures)) failures=$prior_failures
  check "$observed" 1 'skipping required package install cannot satisfy successful deployment'
  runtime_hooks_event enter docker "$PWD" compose -f 'selected file' --env-file 'selected env' pull
  runtime_hooks_compose_assert 'selected file' 'selected env' 1
  for control in split-file omitted-env; do
    observation_attempt=$((observation_attempt + 1)) APP_ATTEMPT=$((APP_ATTEMPT + 1))
    case "$control" in
      split-file) runtime_hooks_event enter docker "$PWD" compose -f selected file --env-file 'selected env' pull ;;
      omitted-env) runtime_hooks_event enter docker "$PWD" compose -f 'selected file' pull ;;
    esac
    prior_failures=$failures
    runtime_hooks_compose_assert 'selected file' 'selected env' 1 > "$work/$control" 2>&1
    observed=$((failures - prior_failures)) failures=$prior_failures
    check "$observed" 1 "exact Compose observation rejects $control"
  done
  mkdir "$c/app"
  runtime_hooks_recovery_setup fixture active "$c/app"
  retry_starts_before=0
  runtime_hooks_activation=intent-preserving
  printf inactive > "$c/recovery-state"
  prior_failures=$failures
  runtime_hooks_retry_services_assert > "$work/stopped-retry" 2>&1
  observed=$((failures - prior_failures)) failures=$prior_failures
  check "$((observed > 0))" 1 'successful retry cannot leave originally active service stopped'
  for policy in intent-preserving start-on-success; do
    runtime_hooks_activation=$policy
    for action in stopped started; do
      runtime_hooks_recovery_setup fixture inactive "$c/app"
      retry_starts_before=0 expected_bad=0
      if [[ "$action" == started ]]; then runtime_hooks_recovery_service start fixture; fi
      case "$policy/$action" in intent-preserving/started | start-on-success/stopped) expected_bad=1 ;; esac
      prior_failures=$failures
      runtime_hooks_retry_services_assert > "$work/$policy-$action" 2>&1
      observed=$((failures - prior_failures)) failures=$prior_failures
      check "$((observed > 0))" "$expected_bad" "declared retry activation/$policy/$action"
    done
    runtime_hooks_recovery_setup fixture active "$c/app"
    retry_starts_before=0
    prior_failures=$failures
    runtime_hooks_retry_services_assert > "$work/$policy-stale-start" 2>&1
    observed=$((failures - prior_failures)) failures=$prior_failures
    check "$((observed > 0))" 1 "declared retry activation/$policy requires fresh activation"
    runtime_hooks_recovery_service start fixture
    runtime_hooks_retry_services_assert
  done
  printf 'selected config\n' > "$c/selected-config"
  cp "$c/selected-config" "$c/config-before"
  runtime_hooks_retained_file_assert "$c/selected-config" "$c/config-before"
  rm "$c/selected-config"
  prior_failures=$failures
  runtime_hooks_retained_file_assert "$c/selected-config" "$c/config-before" > "$work/deleted-before-down" 2>&1
  observed=$((failures - prior_failures)) failures=$prior_failures
  check "$observed" 1 'selected config deletion before failed teardown fails retention'
fi
printf 'RUNTIME_HOOKS_RESULT failures=%s\n' "$failures"
[[ "$failures" == 0 ]]
