#!/usr/bin/env bash
# Shared release API/archive models, not checker/deployer substitutes. Each app
# declares its own inputs and setup. Package installation/builds are external
# effects; selection, publication, markers and pending ownership remain real.
# shellcheck disable=SC2034,SC2154
source "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
script_type=addon
variants=(checker no-update selected)
hook_paths=()
runtime_hooks_variant() {
  [[ "$variant" != checker ]] || fault=checker
}
addon_release_model() {
  node() { printf 'v24.0.0\n'; }
  npm() { :; }
  pnpm() { :; }
  yarn() { :; }
  uv() { :; }
  setup_nodejs() { :; }
  setup_go() { :; }
  setup_uv() { :; }
  _deploy_release_deb() {
    # Model only the package-manager effect after real release/asset selection.
    cat "$1" > "$c/package-consumer"
  }
  addon_release_curl() {
    [[ "$APP_FAULT" != checker ]] || return 17
    local out='' format='' url='' tag=v2.0.0 body
    while (($#)); do
      case "$1" in
        -o)
          out=$2
          shift
          ;;
        -w)
          format=$2
          shift
          ;;
        https:*) url=$1 ;;
      esac
      shift
    done
    printf '%s\n' "$url" >> "$c/requests"
    if [[ "$url" == *'/releases/latest' ]]; then
      # A second unbound latest request must not silently follow a moving tag.
      [[ $(grep -c '/releases/latest$' "$c/requests") == 1 ]] || tag=v9.0.0
    elif [[ "$url" == *'/tags/'* ]]; then tag=${url##*/}; fi
    body="{\"tag_name\":\"$tag\",\"assets\":[{\"name\":\"$release_asset\",\"browser_download_url\":\"https://fixture.invalid/$tag/$release_asset\"}]}"
    if [[ -n "$out" ]]; then printf '%s' "$body" > "$out"; else printf '%s' "$body"; fi
    [[ -z "$format" ]] || printf 200
  }
  addon_release_download() {
    printf '%s\n' "$2" >> "$c/downloads"
    case "$release_mode" in
      tarball) tar -czf "$1" -C "$c" payload ;;
      prebuild) tar -czf "$1" -C "$c/payload" . ;;
      binary) printf 'selected v2.0.0\n' > "$1" ;;
      singlefile) cp "$c/payload/consumer" "$1" ;;
    esac
  }
  curl() { addon_release_curl "$@"; }
  curl_download() { addon_release_download "$@"; }
}
runtime_hooks_model() { addon_release_model; }
runtime_hooks_setup() {
  : > "$c/requests"
  : > "$c/downloads"
  printf 'old package\n' > "$c/package-consumer"
  local marker=${release_app,,}
  marker=${marker// /}
  printf '%s\n' "$([[ "$variant" == no-update ]] && printf 2.0.0 || printf 1.0.0)" > "$c/home/.$marker"
  printf '#!/usr/bin/env bash\nprintf "selected v2.0.0\\n"\n' > "$c/payload/consumer"
  chmod 0755 "$c/payload/consumer"
  # Go build is an external effect, installed only in the fixture's bound /usr/local.
  cat > "$c/local/bin/go" << 'GO'
#!/usr/bin/env bash
exit 0
GO
  chmod 0755 "$c/local/bin/go"
  addon_release_setup
}
runtime_hooks_expected() { [[ "$fault" != checker ]] || expected=17; }
runtime_hooks_assert() {
  if [[ "$variant" == selected ]]; then
    addon_release_consumer_assert
    check "$(grep -c '/releases/tags/v2.0.0$' "$c/requests" || true)" 1 "$app binds selected raw tag"
    check "$(grep -c '/releases/latest$' "$c/requests" || true)" 1 "$app does not resolve latest twice"
    check "$(grep -c 'v9.0.0' "$c/downloads" || true)" 0 "$app never deploys moved latest"
  else
    check "$(stat -c %s "$c/downloads")" 0 "$app/$variant no deployment"
    if [[ "$variant" == checker ]]; then
      check "$(stat -c %s "$c/services")" 0 "$app checker error has no service effects"
    fi
  fi
}
runtime_hooks_retry_assert() { addon_release_consumer_assert; }
