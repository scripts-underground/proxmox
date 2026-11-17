#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/addon-release.sh"
app=prometheus-paperless-ngx-exporter
release_app=prom-paperless-exp release_mode=binary release_asset=prometheus-paperless-exporter_2_amd64.deb
variants+=(uninstall)
eval "$(declare -f runtime_hooks_variant | sed '1s/runtime_hooks_variant/release_variant/')"
runtime_hooks_variant() {
  release_variant
  [[ "$variant" != uninstall ]] || role=uninstall
}
addon_release_setup() {
  : > "$c/local/bin/prometheus-paperless-exporter"
  printf 'var_addon_bin_path=/usr/local/bin/prometheus-paperless-exporter\n' > "$c/context.sh"
  mkdir -p "$c/etc/prometheus-paperless-ngx-exporter" "$c/etc/systemd/system"
  printf 'operator unit and drop-in contract\n' > "$c/etc/systemd/system/$app.service"
  printf 'foreign marker\n' > "$c/home/.foreign"
}
runtime_hooks_model() {
  addon_release_model
  dpkg() { :; }
}
eval "$(declare -f runtime_hooks_assert | sed '1s/runtime_hooks_assert/release_assert/')"
runtime_hooks_assert() {
  if [[ "$role" == uninstall ]]; then
    check "$(test -e "$c/home/.prom-paperless-exp" && printf present || printf absent)" absent "$app removes actual release marker"
    check "$(cat "$c/home/.foreign")" 'foreign marker' "$app retains unrelated release marker"
  else
    release_assert
    check "$(cat "$c/etc/systemd/system/$app.service")" 'operator unit and drop-in contract' "$app update preserves operator service"
  fi
}
addon_release_consumer_assert() { check "$(cat "$c/package-consumer")" 'selected v2.0.0' "$app selected package consumer"; }
runtime_hooks_main "$@"
