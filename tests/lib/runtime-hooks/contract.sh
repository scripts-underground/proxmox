#!/usr/bin/env bash
# One data-only declaration reader for discovery and direct cold-hook admission.
# shellcheck disable=SC2034
runtime_hooks_contract_read() {
  local _rh_file=$1 _rh_line _rh_count=0 _rh_profile='' _rh_activation=''
  runtime_hooks_contract_profile='' runtime_hooks_activation=''
  if [[ ! -f "$_rh_file" || ! -r "$_rh_file" ]]; then
    printf 'Runtime hooks: cannot read activation contract: %s\n' "$_rh_file" >&2
    return 65
  fi
  while IFS= read -r _rh_line || [[ -n "$_rh_line" ]]; do
    [[ "$_rh_line" == '# runtime-hooks-contract:'* ]] || continue
    _rh_count=$((_rh_count + 1))
    if [[ "$_rh_line" =~ ^#\ runtime-hooks-contract:\ ([a-z-]+)\ ([a-z-]+)$ ]]; then
      _rh_profile=${BASH_REMATCH[1]} _rh_activation=${BASH_REMATCH[2]}
    else
      printf 'Runtime hooks: malformed activation contract: %s\n' "$_rh_file" >&2
      return 65
    fi
  done < "$_rh_file"
  if [[ "$_rh_count" != 1 ]]; then
    printf 'Runtime hooks: declare exactly one activation contract: %s\n' "$_rh_file" >&2
    return 65
  fi
  case "$_rh_profile:$_rh_activation" in
    addon:intent-preserving | lxc:intent-preserving | lxc:start-on-success | lxc:package-managed | fixture:case-asserted) ;;
    *)
      printf 'Runtime hooks: invalid activation contract %s/%s: %s\n' "$_rh_profile" "$_rh_activation" "$_rh_file" >&2
      return 65
      ;;
  esac
  runtime_hooks_contract_profile=$_rh_profile runtime_hooks_activation=$_rh_activation
}
