#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/addon-release.sh"
app=birdnet-go
script_type=lxc
release_app=birdnet release_mode=prebuild release_asset=birdnet-go-linux-amd64-fixture.tar.gz
variants=(fresh selected no-update clean pending checker download runtime library missing-binary missing-library missing)
hook_paths=()
runtime_hooks_variant() {
  case "$variant" in checker | download | runtime | library) fault=$variant ;; esac
}
runtime_hooks_expected() {
  [[ "$fault" != checker ]] || expected=17
  [[ "$fault" != library ]] || expected=77
  case "$variant" in missing-binary | missing-library) expected=1 ;; esac
  [[ "$variant" != missing ]] || expected=1
}
runtime_hooks_model() {
  addon_release_model
  if [[ -f "$c/clean" ]]; then CLEAN_INSTALL=1 UPDATE_FORCE=1 FORCE_DEPLOY=1; fi
  apt() { :; }
  ldconfig() { :; }
  get_system_arch() { printf 'amd64\n'; }
  curl_download() {
    [[ "$APP_FAULT" != download ]] || return 22
    addon_release_download "$@"
  }
  cp() {
    if [[ "$APP_FAULT" == library && "$1" == -r && "$2" == /opt/birdnet/libtensorflowlite_c.so ]]; then return 77; fi
    command cp "$@"
  }
  systemctl() {
    if [[ "$1" == start && "$APP_FAULT" == runtime ]]; then
      printf 'failed-start %s\n' "${!#}" >> "$c/services"
      return 51
    fi
    printf '%s\n' "$*" >> "$c/services"
  }
}
runtime_hooks_setup() {
  : > "$c/requests"
  : > "$c/downloads"
  mkdir -p "$c/opt/birdnet/data/clips" "$c/payload/data" "$c/local/lib"
  printf 'saved database\n' > "$c/opt/birdnet/data/birdnet.db"
  printf 'saved audio\n' > "$c/opt/birdnet/data/clips/owl.wav"
  printf 'incoming defaults\n' > "$c/payload/data/birdnet.db"
  stat -c '%i' "$c/opt/birdnet/data" > "$c/data-inode"
  printf '#!/bin/sh\nprintf "new-birdnet\\n"\n' > "$c/payload/birdnet-go"
  printf '#!/bin/sh\nprintf "old-birdnet\\n"\n' > "$c/local/bin/birdnet-go"
  printf 'new TFLite\n' > "$c/payload/libtensorflowlite_c.so"
  printf 'new ONNX\n' > "$c/payload/libonnxruntime.so"
  printf 'old TFLite\n' > "$c/local/lib/libtensorflowlite_c.so"
  printf 'old ONNX\n' > "$c/local/lib/libonnxruntime.so"
  chmod 0755 "$c/payload/birdnet-go" "$c/local/bin/birdnet-go"
  if [[ "$variant" == no-update || "$variant" == clean || "$variant" == pending || "$variant" == missing-binary || "$variant" == missing-library ]]; then
    printf '2.0.0\n' > "$c/home/.birdnet"
  else printf '1.0.0\n' > "$c/home/.birdnet"; fi
  if [[ "$variant" == clean ]]; then
    : > "$c/clean"
    printf 'stale code\n' > "$c/opt/birdnet/obsolete"
  fi
  if [[ "$variant" == pending ]]; then
    printf 'interrupted\n' > "$c/state/birdnet-go"
    rm "$c/local/bin/birdnet-go"
  fi
  [[ "$variant" != missing-binary ]] || rm "$c/local/bin/birdnet-go"
  [[ "$variant" != missing-library ]] || rm "$c/local/lib/libtensorflowlite_c.so"
  [[ "$variant" != missing ]] || {
    mv "$c/opt/birdnet" "$c/absent-birdnet"
    rm "$c/local/bin/birdnet-go"
  }
}
runtime_hooks_assert() {
  [[ "$variant" != missing ]] || return 0
  check "$(cat "$c/opt/birdnet/data/birdnet.db" 2> /dev/null || true)" 'saved database' "$app/$variant database retained"
  check "$(cat "$c/opt/birdnet/data/clips/owl.wav" 2> /dev/null || true)" 'saved audio' "$app/$variant recording retained"
  check "$(stat -c '%i' "$c/opt/birdnet/data" 2> /dev/null || true)" "$(cat "$c/data-inode")" "$app/$variant data directory stays in place"
  if [[ "$variant" == checker || "$variant" == no-update ]]; then
    check "$(stat -c %s "$c/downloads")" 0 "$app/$variant no deployment"
    check "$(stat -c %s "$c/services")" 0 "$app/$variant no service effects"
  elif [[ "$rc" == 0 ]]; then
    check "$("$c/local/bin/birdnet-go" 2> /dev/null || true)" new-birdnet "$app/$variant executable consumer"
    check "$(cat "$c/local/lib/libtensorflowlite_c.so" 2> /dev/null || true)" 'new TFLite' "$app/$variant deployed TFLite consumer"
    check "$(cat "$c/local/lib/libonnxruntime.so" 2> /dev/null || true)" 'new ONNX' "$app/$variant deployed ONNX consumer"
    if [[ "$role" == update && "$variant" != clean && "$variant" != pending ]]; then
      check "$(grep -c '/releases/latest$' "$c/requests" || true)" 1 "$app one release selection"
      check "$(grep -c '/releases/tags/v2.0.0$' "$c/requests" || true)" 1 "$app selected raw tag deployed"
    fi
  fi
  if [[ "$variant" == clean ]]; then check "$(test -e "$c/opt/birdnet/obsolete" && printf present || printf absent)" absent "$app clean removes obsolete code"; fi
}
runtime_hooks_retry_needed() { [[ "$expected" != 0 && "$variant" != missing ]]; }
runtime_hooks_retry_assert() {
  check "$("$c/local/bin/birdnet-go")" new-birdnet "$app retry restores executable"
  check "$(cat "$c/opt/birdnet/data/birdnet.db")" 'saved database' "$app retry retains database"
  check "$(tail -1 "$c/services")" 'start birdnet' "$app retry starts service"
}
runtime_hooks_main "$@"
