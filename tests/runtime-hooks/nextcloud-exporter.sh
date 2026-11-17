#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/addon-release.sh"
app=nextcloud-exporter
release_app=$app release_mode=binary release_asset=nextcloud-exporter_2_amd64.deb
variants+=(fresh uninstall)
hook_paths=('/usr/bin/nextcloud-exporter' 'package-bin/nextcloud-exporter')
eval "$(declare -f runtime_hooks_variant | sed '1s/runtime_hooks_variant/release_variant/')"
runtime_hooks_variant() {
  release_variant
  [[ "$variant" != uninstall ]] || role=uninstall
}
addon_release_setup() {
  mkdir -p "$c/package-bin"
  printf '#!/usr/bin/env bash\nprintf "old binary\\n"\n' > "$c/local/bin/custom-nextcloud"
  chmod 0755 "$c/local/bin/custom-nextcloud"
  printf 'var_addon_bin_path=/usr/local/bin/custom-nextcloud\nvar_addon_default_port=19205\nvar_addon_config_path=%q\n' "$c/external/nextcloud.env" > "$c/context.sh"
  printf '\nfixture-token\n\n\n\n' > "$c/stdin"
}
runtime_hooks_model() {
  addon_release_model
  _deploy_release_deb() {
    cat "$1" > "$c/package-consumer"
    printf '#!/usr/bin/env bash\nprintf "selected v2.0.0\\n"\n' > "$c/package-bin/nextcloud-exporter"
    chmod 0755 "$c/package-bin/nextcloud-exporter"
  }
  dpkg() { :; }
}
addon_release_consumer_assert() { check "$("$c/local/bin/custom-nextcloud")" 'selected v2.0.0' "$app selected package reaches configured binary"; }
eval "$(declare -f runtime_hooks_assert | sed '1s/runtime_hooks_assert/release_assert/')"
runtime_hooks_assert() {
  if [[ "$role" == install ]]; then
    addon_release_consumer_assert
    check "$(stat -c %a "$c/external/nextcloud.env")" 600 "$app private credential file"
    check "$(grep -c '^NEXTCLOUD_LISTEN_ADDRESS=":19205"$' "$c/external/nextcloud.env")" 1 "$app custom listener reaches config"
  elif [[ "$role" == uninstall ]]; then
    check "$(test -e "$c/local/bin/custom-nextcloud" && printf present || printf absent)" absent "$app removes addon-owned binary override"
  else release_assert; fi
}
runtime_hooks_main "$@"
