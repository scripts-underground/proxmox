#!/usr/bin/env bash
# runtime-hooks-contract: addon intent-preserving
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/addon-release.sh"
app=nextcloud-exporter
release_app=$app release_mode=binary release_asset=nextcloud-exporter_2_amd64.deb
variants+=(fresh uninstall owned-uninstall changed-uninstall download stopped-download package-intact package-partial relocate-intact relocate-partial mode rename stop stopped-selected missing alias-hard alias-symbolic alias-lexical)
hook_paths=('/usr/bin/nextcloud-exporter' 'package-bin/nextcloud-exporter')
eval "$(declare -f runtime_hooks_variant | sed '1s/runtime_hooks_variant/release_variant/')"
runtime_hooks_variant() {
  release_variant
  case "$variant" in *uninstall) role=uninstall ;; esac
  case "$variant" in stopped-download) fault=download ;; package-* | relocate-* | stop | mode | rename) fault=$variant ;; esac
}
runtime_hooks_expected() {
  case "$fault" in checker) expected=17 ;; package-*) expected=43 ;; relocate-* | mode | rename) expected=44 ;; stop) expected=47 ;; esac
}
addon_release_setup() {
  mkdir -p "$c/package-bin"
  printf '#!/usr/bin/env bash\nprintf "old binary\\n"\n' > "$c/local/bin/custom-nextcloud"
  chmod 0755 "$c/local/bin/custom-nextcloud"
  printf 'var_addon_bin_path=%q\nvar_addon_default_port=19205\nvar_addon_config_path=%q\n' "$c/local/bin/custom-nextcloud" "$c/external/nextcloud.env" > "$c/context.sh"
  printf '\nfixture-token\n\n\n\n' > "$c/stdin"
  case "$variant" in
    alias-*)
      printf '#!/usr/bin/env bash\nprintf "old binary\\n"\n' > "$c/package-bin/nextcloud-exporter"
      chmod 0755 "$c/package-bin/nextcloud-exporter"
      rm "$c/local/bin/custom-nextcloud"
      case "$variant" in
        alias-hard) ln "$c/package-bin/nextcloud-exporter" "$c/local/bin/custom-nextcloud" ;;
        alias-symbolic) ln -s "$c/package-bin/nextcloud-exporter" "$c/local/bin/custom-nextcloud" ;;
        alias-lexical)
          ln -s "$c/package-bin/nextcloud-exporter" "$c/local/bin/custom-nextcloud"
          printf 'var_addon_bin_path=%q\n' "$c/package-bin/./nextcloud-exporter" >> "$c/context.sh"
          ;;
      esac
      ;;
    owned-uninstall | changed-uninstall)
      # Establish publication through the real owner, independently of bundle
      # generation. A legacy refresh never calls this publisher.
      cp "$c/local/bin/custom-nextcloud" "$c/payload/owned-bin"
      local custody_status=0
      (
        source "$ROOT/misc/core.func"
        source "$ROOT/misc/addon_lxc.func"
        addon_init "$app"
        _addon_private_state_path() { printf -v "$1" '%s' "$c/executable-custody/$APP_SLUG"; }
        mkdir -m 0700 "$c/executable-custody"
        addon_publish_executable "$c/payload/owned-bin" "$c/local/bin/custom-nextcloud"
      ) > "$c/custody-setup.log" 2>&1 || custody_status=$?
      printf '%s\n' "$custody_status" > "$c/custody-status"
      [[ "$variant" != changed-uninstall ]] || printf 'operator replacement\n' > "$c/local/bin/custom-nextcloud"
      ;;
  esac
  if [[ "$role" == update ]]; then
    printf 'operator credential\n' > "$c/external/nextcloud.env"
    chmod 0600 "$c/external/nextcloud.env"
    printf 'operator unit\n' > "$c/etc/systemd/system/custom-nextcloud.service"
    printf 'var_addon_service=custom-nextcloud\n' >> "$c/context.sh"
    local initial=active
    [[ "$variant" != stopped-* ]] || initial=inactive
    runtime_hooks_recovery_setup custom-nextcloud "$initial" "$c/local/bin/custom-nextcloud" "$c/external/nextcloud.env" "$c/etc/systemd/system/custom-nextcloud.service"
  fi
  [[ "$variant" != missing ]] || rm "$c/local/bin/custom-nextcloud"
  if [[ "$variant" == missing ]]; then cp "$c/payload/consumer" "$c/package-bin/nextcloud-exporter"; fi
}
runtime_hooks_model() {
  addon_release_model
  _deploy_release_deb() {
    [[ "$APP_FAULT" != package-intact ]] || return 43
    cat "$1" > "$c/package-consumer"
    printf '#!/usr/bin/env bash\nprintf "selected v2.0.0\\n"\n' > "$c/package-bin/nextcloud-exporter"
    chmod 0755 "$c/package-bin/nextcloud-exporter"
    if [[ "$APP_FAULT" == package-partial ]]; then
      printf 'partial unit\n' > "$c/etc/systemd/system/custom-nextcloud.service"
      return 43
    fi
    if [[ -f "$c/recovery-service" ]]; then printf 'usable unit\n' > "$c/etc/systemd/system/custom-nextcloud.service"; fi
    printf '%s\n' "$APP_FAULT" >> "$c/package-completed"
  }
  install() {
    [[ "$APP_FAULT" != relocate-intact ]] || return 44
    if [[ "$APP_FAULT" == relocate-partial ]]; then
      printf 'partial executable\n' > "${!#}"
      return 44
    fi
    command install "$@"
  }
  chmod() {
    [[ "$APP_FAULT" != mode || "${!#}" != *'.addon-executable.'* ]] || return 44
    command chmod "$@"
  }
  mv() {
    [[ "$APP_FAULT" != rename || "$*" != *'.addon-executable.'* ]] || return 44
    command mv "$@"
  }
  _addon_executable_path() { _addon_private_state_path "$1" "$c/executable-custody"; }
  systemctl() {
    [[ "$APP_FAULT/$1" != stop/stop ]] || return 47
    if [[ -f "$c/recovery-service" ]]; then
      if [[ "$1" == start ]]; then
        [[ "$(cat "$c/etc/systemd/system/custom-nextcloud.service")" != 'partial unit' && -x "$c/local/bin/custom-nextcloud" ]] || return 49
        "$c/local/bin/custom-nextcloud" > "$c/active-consumer"
      fi
      runtime_hooks_recovery_service "$@"
    else
      printf '%s\n' "$*" >> "$c/services"
      if [[ "$1" == show ]]; then printf 'LoadState=loaded\nActiveState=active\nUnitFileState=enabled\n'; fi
    fi
  }
  curl_download() {
    [[ "$APP_FAULT" != download ]] || return 22
    addon_release_download "$@"
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
    if [[ "$variant" == *-uninstall ]]; then
      check "$(cat "$c/custody-status")" 0 "$app establishes real independent publication custody"
    fi
    if [[ "$variant" == owned-uninstall ]]; then
      check "$(test -e "$c/local/bin/custom-nextcloud" && printf present || printf absent)" absent "$app removes positively published override"
    else
      check "$(test -e "$c/local/bin/custom-nextcloud" && printf present || printf absent)" present "$app preserves legacy or changed custom executable"
    fi
  else
    case "$variant" in checker | no-update | selected) release_assert ;; esac
    check "$(cat "$c/external/nextcloud.env")" 'operator credential' "$app/$variant credentials retained"
    if [[ "$expected" != 0 && "$variant" != package-partial ]]; then
      check "$("$c/local/bin/custom-nextcloud")" 'old binary' "$app/$variant publication failure preserves complete old binary"
    fi
    case "$variant" in alias-*)
      check "$(test "$c/local/bin/custom-nextcloud" -ef "$c/package-bin/nextcloud-exporter" && printf same || printf different)" same "$app/$variant preserves inode aliases"
      ;;
    esac
    if [[ "$variant" == missing ]]; then
      check "$(cat "$c/active-consumer" 2> /dev/null || true)" 'selected v2.0.0' "$app missing custom copy is repaired through package and unit"
    fi
    if [[ "$variant" == stopped-selected ]]; then
      check "$(cat "$c/recovery-state")" inactive "$app successful update leaves initially stopped service stopped"
      check "$(wc -l < "$c/recovery-starts")" 0 "$app successful update never starts initially stopped service"
    fi
  fi
}
runtime_hooks_retry_assert() {
  addon_release_consumer_assert
  if [[ "$variant" != stopped-* ]]; then
    check "$(cat "$c/active-consumer")" 'selected v2.0.0' "$app/$variant retry reaches active executable consumer"
    check "$(cat "$c/etc/systemd/system/custom-nextcloud.service")" 'usable unit' "$app/$variant package retry repairs usable unit"
    check "$(tail -n1 "$c/package-completed")" none "$app/$variant cold retry completes fresh package work"
  fi
  if [[ "$variant" == stopped-download ]]; then
    check "$(cat "$c/recovery-state")" inactive "$app retry leaves initially stopped service stopped"
    check "$(wc -l < "$c/recovery-starts")" 0 "$app retry never starts initially stopped service"
  fi
}
runtime_hooks_more_cases() (
  source "$ROOT/misc/addon_lxc.func"
  msg_warn() { printf '%s\n' "$*" >> "$c/notices"; }
  APP_SLUG=$app
  c="$work/executable-owner"
  mkdir -p "$c/state" "$c/bin"
  chmod 0700 "$c/state"
  _addon_executable_path() { printf -v "$1" '%s' "$c/state/$APP_SLUG"; }
  printf 'old\n' > "$c/bin/selected"
  printf 'new\n' > "$c/source"
  addon_publish_executable "$c/source" "$c/bin/selected"
  check "$(cat "$c/bin/selected")" new 'executable owner publishes complete selected bytes'
  check "$(stat -c %a "$c/state/$app")" 600 'executable custody is private data'
  local record
  record=$(sha256sum "$c/state/$app")
  local status=0
  addon_remove_executable "$c/bin/foreign" || status=$?
  check "$status" 65 'executable custody refuses another selected destination'
  check "$(sha256sum "$c/state/$app")" "$record" 'destination refusal preserves custody'
  printf 'operator edit\n' > "$c/bin/selected"
  addon_remove_executable "$c/bin/selected"
  check "$(cat "$c/bin/selected")" 'operator edit' 'executable owner preserves edited inode contents'
  addon_publish_executable "$c/source" "$c/bin/selected"
  chmod 0644 "$c/state/$app"
  status=0
  addon_remove_executable "$c/bin/selected" || status=$?
  check "$status" 69 'executable custody rejects unsafe record metadata'
  check "$(cat "$c/bin/selected")" new 'unsafe custody never deletes executable'
  chmod 0600 "$c/state/$app"
  printf 'malformed\0' > "$c/state/$app"
  status=0
  addon_publish_executable "$c/source" "$c/bin/selected" || status=$?
  check "$status" 65 'publisher refuses malformed previous custody'
  check "$(cat "$c/bin/selected")" new 'malformed custody never changes executable'
  rm "$c/state/$app"
  addon_publish_executable "$c/source" "$c/bin/selected"
  printf 'next\n' > "$c/source"
  mv() {
    [[ "$*" != *'.addon-executable.'* ]] || return 44
    command mv "$@"
  }
  status=0
  addon_publish_executable "$c/source" "$c/bin/selected" || status=$?
  check "$status" 44 'failed executable rename preserves original status'
  check "$(cat "$c/bin/selected")" new 'failed rename retains complete old consumer'
  addon_remove_executable "$c/bin/selected"
  check "$(test -e "$c/bin/selected" && printf present || printf absent)" absent 'failed rename retains positive old-copy custody'
  mv() {
    command mv "$@" || return $?
    [[ "$*" != *'.addon-executable.'* ]] || return 44
  }
  status=0
  addon_publish_executable "$c/source" "$c/bin/selected" || status=$?
  check "$status" 44 'post-rename interruption remains a failed publication'
  check "$(cat "$c/bin/selected")" next 'post-rename candidate is complete'
  addon_remove_executable "$c/bin/selected"
  check "$(test -e "$c/bin/selected" && printf present || printf absent)" absent 'prepublished custody survives post-rename interruption'
  check "$(find "$c/bin" -name '.addon-executable.*' | wc -l)" 0 'publisher retires only its exact executable stages'
  printf 'RUNTIME_EXECUTABLE_OWNER_FAILURES=%s\n' "$failures"
  [[ "$failures" == 0 ]]
)
runtime_hooks_main "$@"
