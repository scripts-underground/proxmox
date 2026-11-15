#!/usr/bin/env bash
# Cold Colanode hook and actual replacement helper; network, npm and services
# are modeled. Run only through the VM-owned maintenance runtime suite.
set -euo pipefail
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/../..")
if [[ "${1:-}" == --child ]]; then
  c="$CASE_ROOT"
  # Provide private mount targets without creating directories on the VM.
  # Keep the disk-backed workspace visible after replacing /var.
  mount --rbind /var/lib/scripts-underground "$c/opt/workspace-anchor"
  mount --rbind "$c/opt" /opt
  mount --bind "$c/var" /var
  mount --rbind /opt/workspace-anchor /var/lib/scripts-underground
  mount --bind "$c/etc" /etc
  mount --bind "$c/www" /var/www
  mount --bind "$c/nginx" /etc/nginx
  mount --bind "$c/state" /var/lib/scripts-underground/update-pending
  # shellcheck disable=SC1090 # The transformed framework is sourced in this shell.
  source <(sed "s|/var/lib/scripts-underground/maintenance-locks|$c/maintenance-locks|g" "$ROOT/misc/core.func")
  source "$ROOT/misc/error_handler.func"
  source "$ROOT/misc/tools.func"
  source "$c/hooks.sh"
  export HOME="$c/home" STD=''
  header_info() { :; }
  check_container_storage() { :; }
  check_container_resources() { :; }
  cleanup_lxc() { :; }
  get_active_logfile() { printf '%s\n' "$CASE_ROOT/silent.log"; }
  msg_info() { :; }
  msg_ok() { :; }
  msg_warn() { printf '%s\n' "$*" >> "$CASE_ROOT/warnings"; }
  msg_error() { printf '%s\n' "$*" >&2; }
  ensure_dependencies() { :; }
  getent() { :; }
  _gh_release_json() {
    local tag=v2.0.0
    printf '%s\n' "$2" >> "$CASE_ROOT/release-requests"
    [[ "$FAULT" != lookup ]] || return 1
    [[ "$2" != 1.0.0 ]] || tag=v1.0.0
    [[ "$2" != v3.0.0 ]] || tag=v3.0.0
    printf '{"tag_name":"%s","assets":[]}\n' "$tag" > "$4"
  }
  curl_download() {
    [[ "$FAULT" != download ]] || return 22
    case "$2" in *v1.0.0*) cp "$CASE_ROOT/old.tar.gz" "$1" ;; *) cp "$CASE_ROOT/new.tar.gz" "$1" ;; esac
  }
  cp() {
    if [[ "$FAULT" == publish && "${!#}" == /opt/colanode/* && "$*" == *'/deploy-source.'* ]]; then
      command cp -a -- "$3" "${!#}" || return $?
      return 41
    fi
    if [[ ("$FAULT" == retry-web || "$FAULT" == retry-edit) && "${!#}" == /var/www/colanode/* && "$*" == *'/deploy-source.'* ]]; then
      command cp -a -- "$3" "${!#}" || return $?
      return 41
    fi
    command cp "$@"
  }
  npm() {
    [[ "$FAULT" != build && "$FAULT" != silent-build ]] || return 52
    if [[ "$*" == 'run build -w @colanode/web' ]]; then
      mkdir -p apps/web/dist packages/core/dist
      printf 'new web\n' > apps/web/dist/index.html
      printf 'new generated\n' > packages/core/dist/index.js
    fi
  }
  systemctl() { printf '%s\n' "$*" >> "$CASE_ROOT/services"; }
  nginx() {
    [[ "$1" == -T && "$2" == -c && -f "$3" ]] || return 61
    ! grep -Fq 'client_max_body_size 0;' /etc/nginx/sites-available/colanode || return 62
    grep -Fq 'client_max_body_size 0;' "${3%/nginx.conf}/candidate" || return 63
    printf 'candidate validated before publication\n' >> "$CASE_ROOT/nginx-checks"
    printf '# configuration file %s/enabled/colanode:\n' "${3%/nginx.conf}"
  }
  # shellcheck disable=SC2034 # Used by the sourced update hook.
  CLEAN_INSTALL_KEEP_PATHS=('custom keep')
  # shellcheck disable=SC2034 # Used by the sourced maintenance runner.
  NSAPP=colanode
  [[ "$FAULT" != silent-build && "$FAULT" != silent-none ]] || STD=silent
  [[ "$FAULT" != forced ]] || export UPDATE_FORCE=1
  [[ "$FAULT" != override* ]] || export var_appversion=v3.0.0
  [[ "$FAULT" != override-latest ]] || export var_appversion=latest
  if [[ "${COLANODE_COLD:-0}" == 1 ]]; then
    source "$ROOT/misc/bundle.func"
    # shellcheck disable=SC2034 # These values are read by _write_bundle.
    APP=Colanode
    # shellcheck disable=SC2034 # These values are read by _write_bundle.
    REPO_BASE="file://$ROOT"
    # shellcheck disable=SC2034 # This value is baked into the bundle.
    var_lxc_tmpdir="$c/tmp"
    {
      declare -f header_info check_container_storage check_container_resources cleanup_lxc get_active_logfile
      declare -f msg_info msg_ok msg_warn msg_error ensure_dependencies getent _gh_release_json curl_download
      declare -f cp npm systemctl nginx
      printf '%s\n' "CLEAN_INSTALL_KEEP_PATHS=('custom keep')"
    } > "$c/cold-models.sh"
    _write_bundle update update_script "$ROOT/misc" --script-id colanode -- --requirements 0 0 -- \
      'source "$CASE_ROOT/cold-models.sh"' 'run_update_script "$@"' > "$c/cold-update"
    exec env -i PATH="$PATH" HOME="$c/home" CASE_ROOT="$c" FAULT="$FAULT" LOCAL_IP=127.0.0.1 \
      VERBOSE=yes bash "$c/cold-update"
  fi
  catch_errors
  run_update_script
  exit
fi

: "${TMPDIR:?disk-backed TMPDIR required}"
systemd-detect-virt --vm --quiet || exit 1
case "$(realpath -e "$TMPDIR")" in /tmp | /tmp/*) exit 1 ;; esac
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
work=$(mktemp -d "$TMPDIR/colanode-hook.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
awk_bin=$(realpath "$(command -v awk)")
failures=0
check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s: expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
if [[ "${COLANODE_COLD:-0}" == 1 ]]; then
  faults=(none retry-web retry-edit)
else
  faults=(red none build silent-build silent-none download publish conflict markerless legacy current historical current-site lookup forced override override-current override-noop override-latest retry-web retry-edit)
fi
for fault in "${faults[@]}"; do
  c="$work/$fault"
  mkdir -p "$c/"{opt/colanode/data,opt/colanode/packages/core/dist,opt/colanode/custom,home,www/colanode,nginx/sites-available,nginx/sites-enabled,old/payload,new/payload,state}
  mkdir -p "$c/"{opt/workspace-anchor,var/lib/scripts-underground,var/www,etc/nginx,tmp}
  mkdir -p "$c/etc/alternatives"
  ln -s "$awk_bin" "$c/etc/alternatives/awk"
  : > "$c/services"
  mkdir -p "$c/"{old/payload/packages/core,new/payload/packages/core,new/payload/apps/web}
  mkdir -p "$c/opt/colanode/node_modules/@colanode" "$c/new/payload/node_modules/@colanode"
  ln -s ../../packages/core "$c/opt/colanode/node_modules/@colanode/core"
  ln -s ../../packages/core "$c/new/payload/node_modules/@colanode/core"
  printf 'old source\n' > "$c/old/payload/code"
  printf 'new source\n' > "$c/new/payload/code"
  printf '{"packages":{"old":{}}}\n' > "$c/old/payload/package-lock.json"
  printf '{"packages":{}}\n' > "$c/new/payload/package-lock.json"
  cp "$c/old/payload/code" "$c/opt/colanode/code"
  [[ "$fault" != conflict ]] || printf 'operator source\n' > "$c/opt/colanode/code"
  [[ "$fault" != forced ]] || cp "$c/new/payload/code" "$c/opt/colanode/code"
  case "$fault" in
    markerless) ;;
    legacy) printf '1.0.0\n' > "$c/opt/colanode_version.txt" ;;
    current | current-site | forced | override-current | override-latest) printf '2.0.0\n' > "$c/home/.colanode" ;;
    override-noop) printf '3.0.0\n' > "$c/home/.colanode" ;;
    *) printf '1.0.0\n' > "$c/home/.colanode" ;;
  esac
  [[ "$fault" != override-current && "$fault" != override-noop ]] || cp "$c/new/payload/code" "$c/opt/colanode/code"
  printf 'user env\n' > "$c/opt/colanode/.env"
  printf 'upload bytes\n' > "$c/opt/colanode/data/upload"
  printf 'custom bytes\n' > "$c/opt/colanode/custom/state"
  printf '{"storage":{"provider":{"type":"file","directory":"file://custom/storage-path"}}}\n' > "$c/opt/colanode/operator-config.json"
  printf 'custom\n' > "$c/opt/colanode/custom/storage-path"
  printf 'keep bytes\n' > "$c/opt/colanode/custom keep"
  printf 'old generated\n' > "$c/opt/colanode/packages/core/dist/index.js"
  printf 'nested user bytes\n' > "$c/opt/colanode/packages/core/dist/notes"
  mkdir -p "$c/opt/colanode/apps/web/dist"
  printf 'old web\n' > "$c/opt/colanode/apps/web/dist/index.html"
  printf 'old web\n' > "$c/www/colanode/index.html"
  printf 'certificate\n' > "$c/www/colanode/colanode.crt"
  printf 'custom nginx\n' > "$c/nginx/sites-available/colanode"
  if [[ "$fault" == historical || "$fault" == current-site ]]; then
    cat > "$c/nginx/sites-available/colanode" << 'NGINX'
server {
    listen 4000 ssl;
    server_name _;
    root /var/www/colanode;
    index index.html;

    ssl_certificate /etc/ssl/colanode/colanode.crt;
    ssl_certificate_key /etc/ssl/colanode/colanode.key;

    add_header Cross-Origin-Opener-Policy "same-origin" always;
    add_header Cross-Origin-Embedder-Policy "require-corp" always;

    location ~ ^/(config|client)(/.*)?$ {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location = /colanode.crt {
        default_type application/x-x509-ca-cert;
    }

    location / {
        try_files $uri $uri/ /index.html;
    }
}
NGINX
    ln -s /etc/nginx/sites-available/colanode "$c/nginx/sites-enabled/colanode"
    printf 'events {}\nhttp { include /etc/nginx/sites-enabled/*; }\n' > "$c/nginx/nginx.conf"
  fi
  printf '{"packages":{"node_modules/@colanode/core":{"link":true,"resolved":"packages/core"}}}\n' > "$c/opt/colanode/package-lock.json"
  tar -czf "$c/old.tar.gz" -C "$c/old" payload
  tar -czf "$c/new.tar.gz" -C "$c/new" payload
  if [[ "$fault" == red ]]; then
    git --no-optional-locks -C "$ROOT" show 1aba4b5ffeb07d47c76479bd33b5e63a3dc2cafa:scripts/lxc/colanode.sh |
      sed '/^# framework bootstrap/,$d' > "$c/hooks.sh"
  else
    sed '/^# framework bootstrap/,$d' "$ROOT/scripts/lxc/colanode.sh" > "$c/hooks.sh"
  fi
  rc=0
  CASE_ROOT="$c" FAULT="$fault" timeout 120s unshare -m --propagation private -- bash "$0" --child > "$c/output" 2>&1 || rc=$?
  expected=0
  case "$fault" in build | silent-build) expected=52 ;; download) expected=250 ;; publish | retry-web | retry-edit) expected=252 ;; conflict) expected=65 ;; lookup) expected=1 ;; esac
  check "$rc" "$expected" "$fault hook status"
  if [[ "$rc" != "$expected" ]]; then cat "$c/output" >&2; fi
  if [[ "$fault" == red ]]; then
    check "$(test -e "$c/opt/colanode/data/upload" && printf present || printf absent)" absent 'baseline clean update removes unprotected upload'
    check "$(grep -Fc 'proxy_set_header Host \$host;' "$c/hooks.sh" || true)" 1 'baseline template drops Host port'
    check "$(grep -Fc 'client_max_body_size 0;' "$c/hooks.sh" || true)" 0 'baseline template lacks upload body correction'
    continue
  fi
  if [[ "$fault" == retry-web || "$fault" == retry-edit ]]; then
    check "$(cat "$c/home/.colanode")" 1.0.0 "$fault failed first attempt retains marker"
    check "$(test -f "$c/state/colanode" && printf pending)" pending "$fault first attempt retains pending"
    check "$(cat "$c/opt/colanode/code")" 'new source' "$fault app was published before web failure"
    check "$(test -s "$c/home/.colanode-update-recovery" && printf retained)" retained "$fault recovery record retained"
    if [[ "$fault" == retry-edit ]]; then printf 'operator changed source\n' > "$c/opt/colanode/code"; fi
    retry_rc=0
    CASE_ROOT="$c" FAULT=none timeout 120s unshare -m --propagation private -- bash "$0" --child > "$c/retry-output" 2>&1 || retry_rc=$?
    if [[ "$fault" == retry-edit ]]; then
      check "$retry_rc" 65 'operator change is a retry conflict'
      check "$(cat "$c/opt/colanode/code")" 'operator changed source' 'retry retains intervening operator change'
      check "$(test -f "$c/state/colanode" && printf pending)" pending 'conflict retains pending flag'
    else
      check "$retry_rc" 0 'retry succeeds after web fault clears'
      check "$(cat "$c/opt/colanode/code")" 'new source' 'retry retains selected app output'
      check "$(cat "$c/www/colanode/index.html")" 'new web' 'retry publishes selected web output'
      check "$(cat "$c/home/.colanode")" 2.0.0 'retry publishes selected marker'
      check "$(test -e "$c/state/colanode" && printf pending || printf clear)" clear 'successful retry clears pending'
      check "$(test -e "$c/home/.colanode-update-recovery" && printf retained || printf clear)" clear 'successful retry retires recovery record'
    fi
    check "$(cat "$c/opt/colanode/data/upload")" 'upload bytes' "$fault preserves upload"
    continue
  fi
  check "$(cat "$c/opt/colanode/data/upload")" 'upload bytes' "$fault data survives"
  check "$(cat "$c/opt/colanode/.env")" 'user env' "$fault environment survives"
  check "$(cat "$c/opt/colanode/custom/state")" 'custom bytes' "$fault custom data survives"
  check "$(cat "$c/opt/colanode/custom/storage-path")" custom "$fault file reference survives"
  check "$(test -f "$c/opt/colanode/operator-config.json" && printf present)" present "$fault custom config survives"
  check "$(readlink "$c/opt/colanode/node_modules/@colanode/core")" ../../packages/core "$fault workspace link survives"
  check "$(cat "$c/opt/colanode/custom keep")" 'keep bytes' "$fault inherited keep survives"
  check "$(cat "$c/opt/colanode/packages/core/dist/notes")" 'nested user bytes' "$fault nested old-only state survives"
  check "$(cat "$c/www/colanode/colanode.crt")" certificate "$fault certificate survives"
  if [[ "$fault" == historical || "$fault" == current-site ]]; then
    check "$(cat "$c/nginx-checks" 2> /dev/null || true)" 'candidate validated before publication' "$fault candidate prevalidation"
    check "$(grep -Fc 'client_max_body_size 0;' "$c/nginx/sites-available/colanode" || true)" 1 "$fault body directive"
    check "$(grep -Fc 'proxy_set_header Host $http_host;' "$c/nginx/sites-available/colanode" || true)" 1 "$fault Host directive"
  else
    check "$(cat "$c/nginx/sites-available/colanode")" 'custom nginx' "$fault custom nginx survives"
  fi
  if [[ "$fault" == none || "$fault" == silent-none || "$fault" == markerless || "$fault" == legacy || "$fault" == historical || "$fault" == forced || "$fault" == override || "$fault" == override-current ]]; then
    check "$(cat "$c/opt/colanode/code")" 'new source' 'new release source published'
    check "$(cat "$c/opt/colanode/packages/core/dist/index.js")" 'new generated' 'new build output published'
    check "$(cat "$c/www/colanode/index.html")" 'new web' 'new web output published'
    marker=2.0.0
    [[ "$fault" != override* ]] || marker=3.0.0
    check "$(cat "$c/home/.colanode")" "$marker" "$fault real marker follows publication"
    if [[ "$fault" == override || "$fault" == override-current ]]; then
      check "$(grep -c '^v3.0.0$' "$c/release-requests" || true)" 1 'explicit override reaches release selector'
    fi
    if [[ "$fault" == forced ]]; then
      check "$(grep -c '^v2.0.0$' "$c/release-requests" || true)" 1 'forced equal release is fetched'
    fi
  elif [[ "$fault" == current || "$fault" == current-site || "$fault" == override-noop || "$fault" == override-latest ]]; then
    marker=2.0.0
    [[ "$fault" != override-noop ]] || marker=3.0.0
    check "$(cat "$c/home/.colanode")" "$marker" "$fault current release marker unchanged"
    check "$(grep -c '^stop colanode-server$' "$c/services" 2> /dev/null || true)" 0 'current release does not stop service'
  else
    check "$(cat "$c/home/.colanode")" 1.0.0 "$fault leaves real marker"
    if [[ "$fault" != publish ]]; then
      check "$(test -s "$c/services" && printf started || printf untouched)" untouched "$fault precedes service stop"
    else
      check "$(cat "$c/opt/colanode/code")" 'old source' 'publication failure restores old code'
    fi
  fi
done
printf '%s failure(s); actual Colanode hook and merge helper; network/build/services modeled\n' "$failures"
[[ "$failures" == 0 ]]
if [[ "${COLANODE_COLD:-0}" != 1 ]]; then
  COLANODE_COLD=1 bash "$0"
fi
