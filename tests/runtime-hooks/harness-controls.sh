#!/usr/bin/env bash
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
printf 'RUNTIME_HOOKS_RESULT failures=%s\n' "$failures"
[[ "$failures" == 0 ]]
