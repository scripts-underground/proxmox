#!/usr/bin/env bash
# runtime-hooks-contract: fixture case-asserted
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/aggregate.sh"
: "${TMPDIR:?disk-backed TMPDIR required}"
work=$(mktemp -d "$TMPDIR/runtime-hooks-controls.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT
failures=0
control() {
  local expected=$1 label=$2 status=0
  runtime_hooks_aggregate "$work/members" > "$work/output" 2>&1 || status=$?
  if [[ "$status" == "$expected" ]]; then
    printf 'CONTROL PASS %s\n' "$label"
  else
    cat "$work/output"
    printf 'CONTROL FAIL %s expected=%s actual=%s\n' "$label" "$expected" "$status"
    failures=$((failures + 1))
  fi
}
mkdir "$work/members"
control 1 'empty directory refuses'
printf '#!/usr/bin/env bash\n# runtime-hooks-contract: fixture case-asserted\nexit 0\n' > "$work/members/probe.sh"
control 1 'zero exit without summary refuses'
printf '#!/usr/bin/env bash\n# runtime-hooks-contract: fixture case-asserted\nprintf "RUNTIME_HOOKS_RESULT failures=0\\n"\nexit 7\n' > "$work/members/probe.sh"
control 1 'failed member cannot claim success'
printf '#!/usr/bin/env bash\n# runtime-hooks-contract: fixture case-asserted\nprintf "RUNTIME_HOOKS_RESULT failures=1\\n"\n' > "$work/members/probe.sh"
control 1 'nonzero summary refuses'
printf '#!/usr/bin/env bash\nprintf "RUNTIME_HOOKS_RESULT failures=0\\n"\n' > "$work/members/probe.sh"
control 1 'undeclared activation contract refuses before successful summary'
printf '#!/usr/bin/env bash\n# runtime-hooks-contract: addon start-on-success\nprintf "RUNTIME_HOOKS_RESULT failures=0\\n"\n' > "$work/members/probe.sh"
control 1 'addon cannot replace intent preservation with start-on-success'
printf '#!/usr/bin/env bash\n# runtime-hooks-contract: lxc unknown\nprintf "RUNTIME_HOOKS_RESULT failures=0\\n"\n' > "$work/members/probe.sh"
control 1 'unknown activation policy refuses'
printf '#!/usr/bin/env bash\n# runtime-hooks-contract: lxc start-on-success\n# runtime-hooks-contract: lxc start-on-success\nprintf "RUNTIME_HOOKS_RESULT failures=0\\n"\n' > "$work/members/probe.sh"
control 1 'duplicate activation declarations refuse'
printf '#!/usr/bin/env bash\n# runtime-hooks-contract: lxc start-on-success\nprintf "RUNTIME_HOOKS_RESULT failures=0\\n"\n' > "$work/members/probe.sh"
control 0 'successful member accepted'
printf '#!/usr/bin/env bash\n# runtime-hooks-contract: fixture case-asserted\nexit 8\n' > "$work/members/another.sh"
control 1 'one failing member fails combined suite'
printf 'RUNTIME_HOOKS_RESULT failures=%s\n' "$failures"
[[ "$failures" == 0 ]]
