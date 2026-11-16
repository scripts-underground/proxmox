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
printf 'RUNTIME_HOOKS_RESULT failures=%s\n' "$failures"
[[ "$failures" == 0 ]]
