#!/usr/bin/env bash
# Run sorted regular members in separate processes, validating their terminal result.
source "$(dirname "${BASH_SOURCE[0]}")/contract.sh"
runtime_hooks_aggregate() {
  local directory=$1 output member status summary count total=0 failures=0
  local -a members=()
  while IFS= read -r -d '' member; do members+=("$member"); done < <(find "$directory" -maxdepth 1 -type f -name '*.sh' -print0 | LC_ALL=C sort -z)
  if ((${#members[@]} == 0)); then
    printf 'Runtime hooks: refusing empty member directory\n' >&2
    return 1
  fi
  output=$(mktemp "${TMPDIR:?disk-backed TMPDIR required}/runtime-hooks-output.XXXXXXXX")
  for member in "${members[@]}"; do
    total=$((total + 1))
    status=0
    if runtime_hooks_contract_read "$member" > "$output" 2>&1; then
      bash "$member" > "$output" 2>&1 || status=$?
    else
      status=$?
    fi
    cat "$output"
    count=$(grep -Ec '^RUNTIME_HOOKS_RESULT failures=[0-9]+$' "$output" || true)
    summary=$(tail -n 1 "$output")
    if [[ "$status" != 0 || "$count" != 1 || "$summary" != 'RUNTIME_HOOKS_RESULT failures=0' ]]; then
      failures=$((failures + 1))
      printf 'MEMBER FAIL %s status=%s summary=%s\n' "${member##*/}" "$status" "$summary"
    else
      printf 'MEMBER PASS %s\n' "${member##*/}"
    fi
  done
  rm -f -- "$output"
  printf '%s member(s); %s failure(s); runtime hooks aggregate\n' "$total" "$failures"
  [[ "$failures" == 0 ]]
}
