#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/addon-release.sh"
app=copyparty
release_app=copyparty-sfx.py release_mode=singlefile release_asset=copyparty-sfx.py
variants=(checker no-update selected stock unset managed-download custom custom-same-version custom-checker custom-download custom-mode custom-owner custom-marker custom-publish)
runtime_hooks_variant() {
  case "$variant" in
    checker) fault=checker ;;
    unset) fault=unset-source ;;
    managed-download | custom-checker | custom-download | custom-mode | custom-owner | custom-marker | custom-publish) fault=$variant ;;
  esac
}
runtime_hooks_model() {
  addon_release_model
  [[ "$APP_FAULT" != unset-source ]] || unset var_addon_src_url
  curl_download() {
    if [[ "$2" == https://operator.invalid/copyparty.py ]]; then
      printf '%s\n' "$2" >> "$c/downloads"
      printf 'partial download\n' > "$1"
      [[ "$APP_FAULT" != custom-download ]] || return 22
      printf '#!/usr/bin/env bash\nprintf "operator build 42\\n"\n' > "$1"
    else
      [[ "$APP_FAULT" != managed-download ]] || {
        printf partial > "$1"
        return 22
      }
      addon_release_download "$@"
    fi
  }
  # Exercise the old direct-to-live curl path in the red control as well.
  curl() {
    if [[ " $* " == *' https://operator.invalid/copyparty.py '* ]]; then
      local out=''
      while (($#)); do
        if [[ "$1" == -o ]]; then
          out=$2
          shift
        fi
        shift
      done
      curl_download "$out" https://operator.invalid/copyparty.py
    else
      [[ "$APP_FAULT" != custom-checker ]] || return 17
      addon_release_curl "$@"
    fi
  }
  chmod() {
    [[ "$APP_FAULT" != custom-mode || "${!#}" != *'.copyparty-update.'* ]] || return 32
    command chmod "$@"
  }
  chown() {
    [[ "$APP_FAULT" != custom-owner || "${!#}" != *'.copyparty-update.'* ]] || return 31
  }
  mv() {
    [[ "$APP_FAULT" != custom-publish || "${!#}" != "$var_addon_bin_path" ]] || return 33
    command mv "$@"
  }
  rm() {
    [[ "$APP_FAULT" != custom-marker || "${!#}" != "$HOME/.copyparty-sfx.py" ]] || return 34
    command rm "$@"
  }
}
addon_release_setup() {
  printf 'var_addon_bin_path=%q\n' '/usr/local/bin/operator copyparty.py' > "$c/context.sh"
  if [[ "$variant" == custom* ]]; then
    printf 'var_addon_src_url=https://operator.invalid/copyparty.py\n' >> "$c/context.sh"
  elif [[ "$variant" == stock ]]; then
    printf 'var_addon_src_url=https://github.com/9001/copyparty/releases/latest/download/copyparty-sfx.py\n' >> "$c/context.sh"
  fi
  printf '#!/usr/bin/env bash\nprintf "old operator binary\\n"\n' > "$c/local/bin/operator copyparty.py"
  chmod 0751 "$c/local/bin/operator copyparty.py"
  [[ "$variant" != custom-same-version ]] || printf '2.0.0\n' > "$c/home/.copyparty-sfx.py"
}
addon_release_consumer_assert() {
  local desired='selected v2.0.0'
  [[ "$variant" != custom* ]] || desired='operator build 42'
  check "$("$c/local/bin/operator copyparty.py")" "$desired" "$app/$variant executable consumer"
}
runtime_hooks_expected() {
  case "$fault" in
    checker) expected=17 ;;
    managed-download) expected=250 ;;
    custom-download) expected=22 ;;
    custom-mode) expected=32 ;;
    custom-owner) expected=31 ;;
    custom-marker) expected=34 ;;
    custom-publish) expected=33 ;;
  esac
}
runtime_hooks_assert() {
  check "$(find "$c/local/bin" -maxdepth 1 -name '.copyparty-update.*' | wc -l)" 0 "$app/$variant removes only its owned stage"
  if [[ "$expected" != 0 || "$variant" == no-update ]]; then
    check "$("$c/local/bin/operator copyparty.py")" 'old operator binary' "$app/$variant old executable retained"
    check "$(stat -c %a "$c/local/bin/operator copyparty.py")" 751 "$app/$variant old executable mode retained"
  else addon_release_consumer_assert; fi
  if [[ "$variant" == custom* ]]; then
    check "$(stat -c %s "$c/requests")" 0 "$app/$variant custom source makes no GitHub version claim"
    if [[ "$expected" == 0 || "$fault" == custom-publish ]]; then
      check "$(test -e "$c/home/.copyparty-sfx.py" && printf present || printf absent)" absent "$app/$variant custom source cannot leave a managed version claim"
    else
      check "$(cat "$c/home/.copyparty-sfx.py")" 1.0.0 "$app/$variant failed preparation retains previous managed version"
    fi
    check "$(grep -q 'version is operator-managed' "$c/output" && printf present || printf absent)" present "$app/$variant identifies operator-managed version"
    check "$(grep -c '^https://operator.invalid/copyparty.py$' "$c/downloads" || true)" 1 "$app/$variant saved custom source is used"
  elif [[ "$expected" == 0 && "$variant" != no-update ]]; then
    check "$(grep -c '/releases/tags/v2.0.0$' "$c/requests" || true)" 1 "$app/$variant binds selected raw tag"
    check "$(grep -c '/releases/latest$' "$c/requests" || true)" 1 "$app/$variant never resolves latest twice"
    check "$(cat "$c/home/.copyparty-sfx.py")" 2.0.0 "$app/$variant publishes selected release marker"
  elif [[ "$variant" != no-update ]]; then
    check "$(cat "$c/home/.copyparty-sfx.py")" 1.0.0 "$app/$variant failed managed update retains release marker"
  fi
}
runtime_hooks_retry_assert() {
  addon_release_consumer_assert
  if [[ "$variant" == custom* ]]; then
    check "$(test -e "$c/home/.copyparty-sfx.py" && printf present || printf absent)" absent "$app/$variant custom retry cannot leave a managed version claim"
  fi
}
runtime_hooks_main "$@"
