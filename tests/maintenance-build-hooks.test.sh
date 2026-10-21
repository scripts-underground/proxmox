#!/usr/bin/env bash
# Actual cold app hooks/shared deployment/update owner and native Node/Dotenv
# consumers. Dependencies/build artifacts/database/services/model export are models.
set -euo pipefail
systemd-detect-virt --vm --quiet || exit 1
: "${TMPDIR:?disk TMPDIR required}" "${MAINTENANCE_REFERENCES:?}" "${RUNTIME_EXTRA_REFERENCES:?}" "${RUNTIME_NODE:?native Node24 required}"
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
if [[ "${1:-}" == --child ]]; then
  c="$APP_FIXTURE"
  root="/opt/$APP_DIR"
  mount --bind "$c/opt" /opt
  mount --bind "$c/local" /usr/local
  mount --bind "$c/cache" /var/cache
  mount --bind "$c/state" /var/lib/scripts-underground/update-pending
  source "$ROOT/misc/core.func"
  source "$ROOT/misc/error_handler.func"
  source "$ROOT/misc/tools.func"
  load_functions
  source "$c/hooks.sh"
  header_info() { :; }
  check_container_storage() { :; }
  check_container_resources() { :; }
  cleanup_lxc() { :; }
  ensure_dependencies() { :; }
  getent() { return 0; }
  apt() { :; }
  useradd() { :; }
  chown() { :; }
  setup_deb822_repo() { :; }
  install() { if [[ "$1" == -d ]]; then command mkdir -p "${!#}"; else command install "$@"; fi; }
  get_os_info() { printf 'debian\n'; }
  tailscale() { :; }
  setup_nltk() { :; }
  setup_gs() { :; }
  setup_postgresql() { printf '%s\n' "${PG_VERSION:-unset}" >> "$c/db-major"; }
  setup_postgresql_db() { export PG_DB_NAME PG_DB_USER PG_DB_PASS=fixture-db-secret; }
  setup_nodejs() {
    printf runtime >> "$c/effects"
    printf '%s\n' "$NODE_VERSION" > "$c/node-version"
  }
  setup_rust() { :; }
  node() { "$RUNTIME_NODE" "$@"; }
  setup_uv() {
    printf runtime >> "$c/effects"
    printf '%s\n' "$PYTHON_VERSION" > "$c/python-version"
  }
  pip3() { printf system-pip >> "$c/system-pip"; }
  uv() {
    printf '%s\n' "$*" >> "$c/uv-calls"
    if [[ "$1" == venv ]]; then
      local destination="${!#}"
      mkdir -p "$destination/bin"
      cat > "$destination/bin/python" << 'SH'
#!/usr/bin/env bash
if [[ "$1" == -c && "$2" == *'sys.version_info'* ]]; then exit 0; fi
exec /usr/bin/python3 "$@"
SH
      chmod 0755 "$destination/bin/python"
    elif [[ "$1" == pip ]]; then
      [[ "$APP_FAULT" != python ]] || return 51
    elif [[ "$1" == sync ]]; then
      [[ "$APP_FAULT" != build ]] || return 52
      mkdir -p "$root/.venv/bin"
      printf '#!/usr/bin/env bash\nexec /usr/bin/python3 "$@"\n' > "$root/.venv/bin/python"
      chmod 0755 "$root/.venv/bin/python"
    elif [[ "$*" == *'python -'* ]]; then
      while [[ "$1" != python ]]; do shift; done
      shift
      /usr/bin/python3 "$@"
    else
      [[ "$APP_FAULT" != model ]] || return 53
      if [[ "$*" == *'export_onnx.py'* ]]; then
        local previous='' arg
        for arg in "$@"; do
          [[ "$previous" != --out ]] || {
            mkdir -p "$(dirname "$arg")"
            printf model > "$arg"
          }
          previous="$arg"
        done
      fi
    fi
  }
  corepack() { printf '%s\n' "$*" >> "$c/manager"; }
  npm() {
    printf '%s\n' "$*" >> "$c/manager"
    [[ "$APP_FAULT" != build ]] || return 52
  }
  npx() {
    printf '%s\n' "$*" >> "$c/npx"
    [[ "$APP_FAULT" != build ]] || return 52
    [[ "$*" != *setup-db.ts* && "$*" != *typeorm* ]] || return 58
  }
  yarn() {
    printf '%s\n' "$*" >> "$c/yarn"
    [[ "$APP_FAULT" != build ]] || return 52
    if [[ "$*" == 'command:prod upgrade' ]]; then
      [[ "${APP_SECRET:-}" == USER-secret ]] || return 59
      printf 'app-owned upgrade\n' > "$c/upgrade-consumer"
    fi
  }
  pnpm() {
    printf '%s\n' "$*" >> "$c/pnpm"
    if [[ "$APP_CASE" == paperclip && "$*" == *install* ]]; then
      if [[ "$*" == *--no-frozen-lockfile* ]]; then
        printf unlocked >> "$c/unlocked"
        return 0
      fi
      case "$APP_FAULT" in
        stale)
          cat "$RUNTIME_EXTRA_REFERENCES/pnpm-stale-lockfile-native.ndjson"
          return 1
          ;;
        network)
          printf '{"level":"error","name":"pnpm","code":"ERR_PNPM_FETCH_401","err":{"code":"ERR_PNPM_FETCH_401"}}\n'
          return 1
          ;;
        spoof)
          printf 'not a pnpm diagnostic: ERR_PNPM_OUTDATED_LOCKFILE\n'
          return 1
          ;;
        malformed)
          printf '{"level":"error","code":"ERR_PNPM_OUTDATED_LOCKFILE"'
          return 1
          ;;
        mixed)
          cat "$RUNTIME_EXTRA_REFERENCES/pnpm-stale-lockfile-native.ndjson"
          printf '{"level":"error","name":"pnpm","code":"ERR_PNPM_FETCH_401","err":{"code":"ERR_PNPM_FETCH_401"}}\n'
          return 1
          ;;
      esac
    fi
    [[ "$APP_FAULT" != build ]] || return 52
    if [[ "$APP_CASE" == paperclip && "$*" == db:migrate ]]; then
      command pnpm "$@"
      return $?
    fi
    if [[ "$APP_CASE" == tracearr && "$*" == *'install --prod'* ]]; then
      [[ "$*" == *'--filter @tracearr/server...'* && -f packages/emails/package.json ]] || return 57
      mkdir -p node_modules/@tracearr
      ln -s ../../packages/shared node_modules/@tracearr/shared
      ln -s ../../packages/emails node_modules/@tracearr/emails
    fi
  }
  runuser() { :; }
  timescaledb-tune() { :; }
  systemctl() {
    printf '%s\n' "$*" >> "$c/services"
    case "$1" in cat | show) ;; *) printf service >> "$c/effects" ;; esac
    if [[ "$1" == cat ]]; then
      [[ "$APP_FAULT" != query ]] || return 37
      local unit="${!#}" file
      [[ "$unit" == *.service ]] || unit+='.service'
      cat "$c/etc/systemd/system/$unit"
      for file in "$c/etc/systemd/system/$unit.d/"*.conf; do [[ ! -f "$file" ]] || cat "$file"; done
    elif [[ "$1" == show ]]; then
      printf '%s\n' "$c/etc/systemd/system/${!#}"
    elif [[ "$APP_CASE" == tracearr && "$*" == *tracearr* && ("$1" == start || " $* " == *' --now '*) ]]; then
      (
        cd /opt/tracearr
        "$RUNTIME_NODE" apps/server/dist/index.js
      ) > "$c/runtime-consumer"
    fi
  }
  curl_with_retry() {
    [[ "$APP_FAULT" != model ]] || return 53
    mkdir -p "$(dirname "$2")"
    printf model > "$2"
  }
  sha256sum() {
    # Neural artifacts are explicit build models; every other digest is native.
    if [[ "$APP_CASE" == kima-hub && "$*" == '-c -' ]]; then
      local inputs
      inputs=$(cat)
      printf '%s\n' "$inputs" >> "$c/modeled-model-hashes"
      [[ "$APP_FAULT" != checksum ]] || return 54
      return 0
    fi
    command sha256sum "$@"
  }
  curl_download() {
    printf source >> "$c/effects"
    [[ "$APP_FAULT" != download ]] || return 22
    case "$1" in *.tar.xz) tar -cJf "$1" -C "$c" payload ;; *) tar -czf "$1" -C "$c" payload ;; esac
  }
  curl() {
    local out='' url='' format='' tag=v2.0.0 body
    while (($#)); do
      case "$1" in -o)
        out="$2"
        shift
        ;;
      -w)
        format="$2"
        shift
        ;;
      https:*) url="$1" ;; esac
      shift
    done
    if [[ "$url" == *raw.githubusercontent.com*package.json ]]; then
      cat "$c/payload/package.json"
      return 0
    fi
    if [[ "$url" == *paperless.conf.example ]]; then
      cp "$MAINTENANCE_REFERENCES/paperless-v2/paperless.conf.example" "$out"
      return 0
    fi
    [[ "$url" != *'/tags/'* ]] || tag=${url##*/}
    printf '%s %s\n' "$url" "$tag" >> "$c/release-tags"
    body="{\"tag_name\":\"$tag\",\"assets\":[{\"browser_download_url\":\"https://fixture.invalid/paperless-ngx.tar.xz\"}]}"
    if [[ -n "$out" ]]; then printf '%s' "$body" > "$out"; else printf '%s' "$body"; fi
    [[ -z "$format" ]] || printf 200
  }
  cp() {
    if [[ "$APP_FAULT" == copy && "${!#}" == /opt/* && "$*" == *'/deploy-source.'* ]]; then
      command cp -a -- "$3" "${!#}"
      return 41
    fi
    command cp "$@"
  }
  # shellcheck disable=SC2034 # consumed by the sourced deployment helper
  if [[ "$APP_CASE" == twenty ]]; then CLEAN_INSTALL_KEEP_PATHS=('custom store with spaces'); fi
  catch_errors
  if [[ "$APP_ROLE" == install ]]; then install_script; else run_update_script; fi
  exit
fi
work=$(mktemp -d "$TMPDIR/build-hooks.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
failures=0
check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
for app in tracearr twenty kima-hub paperclip paperless-ngx; do
  for mode in no yes; do
    variants='fresh update download build copy'
    [[ "$app" != paperclip ]] || variants+=' stale network spoof malformed mixed fresh-stale fresh-network fresh-spoof fresh-malformed fresh-mixed'
    [[ "$app" != kima-hub ]] || variants+=' python model checksum'
    [[ "$app" != paperless-ngx ]] || variants+=' override-refuse override-valid override-directory override-root-directory regex-current malformed-config ambiguous restart-overrides'
    for variant in $variants; do
      c="$work/$app-$mode-$variant"
      role=update fault=none
      [[ "$variant" != fresh && "$variant" != fresh-* ]] || role=install
      case "$variant" in update | fresh | override-* | regex-current | malformed-config | ambiguous | restart-overrides) ;; *) fault="$variant" ;; esac
      [[ "$variant" != fresh-* ]] || fault="${variant#fresh-}"
      case "$app" in paperclip) dir=paperclip-ai ;; paperless-ngx) dir=paperless ;; *) dir="$app" ;; esac
      mkdir -p "$c/"{opt,local/bin,cache,state,home,bin,etc/systemd/system,etc/nginx,lib/systemd/system,data/tracearr,app,external,payload,root,legacy}
      printf 'ID=debian\nVERSION_ID=13\nVERSION_CODENAME=trixie\n' > "$c/etc/os-release"
      printf 'UTC\n' > "$c/etc/timezone"
      for file in db-major system-pip uv-calls manager npx yarn pnpm services unlocked effects; do : > "$c/$file"; done
      printf 'USER database\n' > "$c/external/database"
      mkdir -p "$c/payload/"{packages/twenty-front/build,packages/twenty-server/dist,packages/shared/dist,packages/emails/dist,apps/server/dist,apps/server/scripts,apps/server/src/db/migrations,apps/web/dist,assets,data,backend,frontend,services/audio-analyzer/models,services/audio-analyzer-clap,src}
      printf 'new code\n' > "$c/payload/code"
      printf 'web output\n' > "$c/payload/packages/twenty-front/build/index.html"
      printf 'UPSTREAM LOGO\n' > "$c/payload/assets/logo.png"
      printf 'new cache default\n' > "$c/payload/data/default"
      printf 'export const shared="shared";\n' > "$c/payload/packages/shared/dist/index.js"
      printf 'export const emails="emails";\n' > "$c/payload/packages/emails/dist/index.js"
      printf 'import {shared} from "@tracearr/shared";import {emails} from "@tracearr/emails";import fs from "node:fs";console.log(shared+":"+emails+":"+fs.readFileSync("assets/logo.png","utf8").trim());\n' > "$c/payload/apps/server/dist/index.js"
      cp "$MAINTENANCE_REFERENCES/tracearr/package.json" "$c/payload/package.json"
      cp "$MAINTENANCE_REFERENCES/tracearr/pnpm-workspace.yaml" "$c/payload/pnpm-workspace.yaml"
      printf 'lockfile fixture\n' > "$c/payload/pnpm-lock.yaml"
      for package in apps/server packages/shared packages/emails; do cp "$MAINTENANCE_REFERENCES/tracearr/$package/package.json" "$c/payload/$package/package.json"; done
      if [[ "$app" == paperclip ]]; then cp "$MAINTENANCE_REFERENCES/paperclip/package.json" "$c/payload/package.json"; fi
      cp "$MAINTENANCE_REFERENCES/paperless-v2/pyproject.toml" "$c/payload/pyproject.toml"
      cp "$MAINTENANCE_REFERENCES/paperless-v2/paperless.conf.example" "$c/payload/paperless.conf.example"
      for analyzer in audio-analyzer audio-analyzer-clap; do
        cp "$MAINTENANCE_REFERENCES/kima-hub/services/$analyzer/requirements.txt" "$c/payload/services/$analyzer/requirements.txt"
        printf 'print("modeled analyzer")\n' > "$c/payload/services/$analyzer/analyzer.py"
      done
      printf 'import os,pathlib,sys\nif os.getenv("APP_FAULT")=="model":sys.exit(53)\nout=sys.argv[sys.argv.index("--out")+1]\np=pathlib.Path(out);p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(b"model")\n' > "$c/payload/services/audio-analyzer-clap/export_onnx.py"
      printf 'import os,sys\nsys.exit(53 if os.getenv("APP_FAULT")=="model" else 0)\n' > "$c/payload/services/audio-analyzer-clap/verify_runtime.py"
      cp "$c/payload/services/audio-analyzer-clap/verify_runtime.py" "$c/payload/services/audio-analyzer/convert_musicnn.py"
      printf model > "$c/payload/services/audio-analyzer/models/msd-musicnn-1.onnx"
      printf '# shared runtime dependency fixture\n' > "$c/payload/services/audio-analyzer-clap/gpu_switch.py"
      if [[ "$role" == update ]]; then
        mkdir -p "$c/opt/$dir/data" "$c/opt/$dir/models" "$c/opt/$dir/backend" "$c/opt/$dir/frontend" "$c/opt/$dir/packages/twenty-server/.local-storage" "$c/opt/$dir/custom store with spaces" "$c/opt/$dir/custom home"
        printf 'old code\n' > "$c/opt/$dir/code"
        printf 'APP_SECRET=USER-secret\nPORT=4555\n' > "$c/opt/$dir/.env"
        printf 'USER stored file\n' > "$c/opt/$dir/packages/twenty-server/.local-storage/file"
        printf 'USER custom store\n' > "$c/opt/$dir/custom store with spaces/file"
        printf 'USER image cache\n' > "$c/opt/$dir/data/cache"
        printf 'USER model\n' > "$c/opt/$dir/models/user-model"
        printf 'PORT=4555\nSESSION_SECRET=USER-session\n' > "$c/opt/$dir/backend/.env"
        printf 'PORT=6443\nBACKEND_URL=http://127.0.0.1:4555\n' > "$c/opt/$dir/frontend/.env"
        printf 'USER home data\n' > "$c/opt/$dir/custom home/file"
        if [[ "$app" == paperclip ]]; then printf 'PAPERCLIP_HOME="/opt/paperclip-ai/custom home"\nPAPERCLIP_CONFIG="/opt/paperclip-ai/custom home/config.json"\nDATABASE_URL="USER database"\nPORT=4555\n' > "$c/opt/$dir/.env"; fi
        if [[ "$app" == tracearr ]]; then
          printf 'PORT=4555\nJWT_SECRET=USER-secret\nAPP_VERSION=old\n' > "$c/data/tracearr/.env"
          printf 'USER prestart PostgreSQL16 settings\n' > "$c/data/tracearr/prestart.sh"
          mkdir -p "$c/lib/systemd/system"
          printf '[Service]\nUser=tracearr\n' > "$c/lib/systemd/system/tracearr.service"
        fi
        if [[ "$app" == paperless-ngx ]]; then
          mkdir -p "$c/opt/$dir/src"
          printf "PAPERLESS_SECRET_KEY='USER secret'\nPAPERLESS_CONSUMER_IGNORE_PATTERNS='[\".*\",\"^scan[0-9]+[.]pdf$\"]'\nPAPERLESS_CONSUMPTION_DIR='%s/external/consume'\n" "$c" > "$c/opt/$dir/paperless.conf"
          cp "$MAINTENANCE_REFERENCES/paperless-v2/pyproject.toml" "$c/opt/$dir/pyproject.toml"
          case "$variant" in
            override-refuse) printf "PAPERLESS_CONSUMER_IGNORE_PATTERNS='[\"private*/*\"]'\n" > "$c/opt/$dir/paperless.conf" ;;
            override-valid) printf "PAPERLESS_SECRET_KEY='USER secret'\nPAPERLESS_DBENGINE=postgresql\nPAPERLESS_CONSUMER_IGNORE_PATTERNS='[\"ignore-*.pdf\",\"scan?.pdf\",\"literal.name.pdf\",\"[ab]scan.pdf\"]'\n" > "$c/opt/$dir/paperless.conf" ;;
            override-directory) printf "PAPERLESS_CONSUMPTION_DIR='%s/consume'\nPAPERLESS_CONSUMER_IGNORE_PATTERNS='[\"private/*\"]'\n" "$c" > "$c/opt/$dir/paperless.conf" ;;
            override-root-directory) printf "PAPERLESS_CONSUMPTION_DIR='%s/consume'\nPAPERLESS_CONSUMER_IGNORE_PATTERNS='[\"consume/*\"]'\n" "$c" > "$c/opt/$dir/paperless.conf" ;;
            malformed-config) printf "PAPERLESS_CONSUMER_IGNORE_PATTERNS='not JSON'\n" > "$c/opt/$dir/paperless.conf" ;;
            ambiguous) printf '[project]\nname="paperless"\n' > "$c/opt/$dir/pyproject.toml" ;;
            regex-current) cp "$MAINTENANCE_REFERENCES/paperless-v3/pyproject.toml" "$c/opt/$dir/pyproject.toml" ;;
          esac
          case "$variant" in override-* | regex-current | malformed-config | ambiguous) cp "$MAINTENANCE_REFERENCES/paperless-v3/pyproject.toml" "$c/payload/pyproject.toml" ;; esac
        fi
      fi
      for service in kima-analyzer kima-analyzer-clap paperless-consumer paperless-scheduler paperless-task-queue paperless-webserver; do
        printf '[Service]\nExecStart=uv run -- python modeled.py\nEnvironment=USER_PORT=4555\n' > "$c/etc/systemd/system/$service.service"
        if [[ "$service" == kima-* ]]; then
          analyzer=audio-analyzer
          [[ "$service" != kima-analyzer-clap ]] || analyzer=audio-analyzer-clap
          printf '[Service]\nExecStart=/usr/bin/python3 /opt/kima-hub/services/%s/analyzer.py\nEnvironment=BACKEND_URL=http://127.0.0.1:4555\n' "$analyzer" > "$c/etc/systemd/system/$service.service"
        fi
      done
      if [[ "$variant" == restart-overrides ]]; then
        printf 'Restart=no\nRestartSec=29\n' >> "$c/etc/systemd/system/paperless-consumer.service"
        mkdir -p "$c/etc/systemd/system/paperless-scheduler.service.d"
        printf '[Service]\nRestart=always\nRestartSec=31\n' > "$c/etc/systemd/system/paperless-scheduler.service.d/90-user.conf"
        printf 'RestartSec=43\n' >> "$c/etc/systemd/system/paperless-task-queue.service"
      fi
      printf 'old\n' > "$c/home/.$dir"
      pin=''
      case "$variant" in override-* | regex-current | malformed-config | ambiguous) pin=v3.3.2 ;; esac
      if [[ "$variant" == regex-current ]]; then printf '3.3.2\n' > "$c/home/.$dir"; fi
      cat > "$c/bin/pnpm" << 'SH'
#!/usr/bin/env bash
if [[ "$*" == *onboard* ]]; then mkdir -p "$(dirname "$PAPERCLIP_CONFIG")"; printf '{"mode":"authenticated"}\n' > "$PAPERCLIP_CONFIG"; exit 0; fi
if [[ "$*" == db:migrate ]]; then /usr/bin/python3 -c 'import json,os,pathlib;pathlib.Path(os.environ["APP_FIXTURE"],"migration-consumer").write_text(json.dumps({"home":os.getenv("PAPERCLIP_HOME"),"database":os.getenv("DATABASE_URL")}))'; fi
SH
      chmod 0755 "$c/bin/pnpm"
      python3 - "$ROOT/scripts/lxc/$app.sh" "$c" << 'PY'
import pathlib,re,subprocess,sys
p=pathlib.Path(sys.argv[1]);c=pathlib.Path(sys.argv[2]);hooks=subprocess.check_output(['bash','-c','curl() { :; }; source "$1"; declare -f install_script update_script','hook-source',str(p)],text=True)
mapping={'/etc':str(c/'etc'),'/root':str(c/'root'),'/data':str(c/'data'),'/app':str(c/'app'),'/music':str(c/'music'),'/lib/systemd':str(c/'lib/systemd'),'/usr/share/nltk_data':str(c/'nltk')}
pattern=r'(?<![A-Za-z0-9_./-])('+ '|'.join(re.escape(k) for k in sorted(mapping,key=len,reverse=True))+r')(?=/|[\s"\x27]|$)';hooks=re.sub(pattern,lambda m:mapping[m[0]],hooks);(c/'hooks.sh').write_text(hooks)
PY
      before=''
      [[ ! -f "$c/opt/$dir/.env" ]] || before=$(sha256sum "$c/opt/$dir/.env")
      before=${before%% *}
      conf_before=''
      [[ ! -f "$c/opt/$dir/paperless.conf" ]] || conf_before=$(sha256sum "$c/opt/$dir/paperless.conf")
      conf_before=${conf_before%% *}
      rc=0
      env -i PATH="$c/bin:$PATH" HOME="$c/home" TMPDIR="$TMPDIR" PYTHONPATH="${PYTHONPATH:-}" RUNTIME_NODE="$RUNTIME_NODE" MAINTENANCE_REFERENCES="$MAINTENANCE_REFERENCES" RUNTIME_EXTRA_REFERENCES="$RUNTIME_EXTRA_REFERENCES" var_appversion="$pin" APP_FIXTURE="$c" APP_CASE="$app" APP_ROLE="$role" APP_FAULT="$fault" APP_DIR="$dir" APP="$app" NSAPP="$app" LOCAL_IP=10.20.30.40 VERBOSE="$mode" BUILD_LOG="$c/build.log" INSTALL_LOG="$c/inherited-install.log" _HOST_LOGFILE="$c/inherited-host.log" DEBUG_LOGFILE="$c/errors.log" \
        unshare -m --propagation private -- bash "$0" --child <<< n > "$c/output" 2>&1 || rc=$?
      expected=0
      case "$fault" in download) expected=250 ;; build) expected=52 ;; copy) expected=252 ;; python) expected=51 ;; model) expected=53 ;; checksum) expected=54 ;; network | spoof | malformed | mixed) expected=1 ;; esac
      case "$variant" in override-refuse | override-root-directory | malformed-config | ambiguous) expected=65 ;; esac
      check "$rc" "$expected" "$app/$mode/$variant actual cold-hook status"
      if [[ "$rc" != "$expected" ]]; then
        python3 - "$c/output" "$app/$variant" << 'PY'
import pathlib,sys
lines=pathlib.Path(sys.argv[1]).read_text().splitlines()
for s in lines:
 if any(w in s for w in ('unbound variable','No such file','exit code','unsupported')):print('DIAG '+sys.argv[2]+' '+s)
for s in lines[-4:]:print('DIAG '+sys.argv[2]+' '+s)
PY
      fi
      check "$(cat "$c/external/database")" 'USER database' "$app/$variant existing database data preserved"
      if [[ "$role" == update ]]; then
        check "$(stat -c %s "$c/db-major")" 0 "$app/$variant no installed DB major provisioning"
        after=$(sha256sum "$c/opt/$dir/.env" 2> /dev/null) || after=missing
        check "${after%% *}" "$before" "$app/$variant complete saved env preserved"
      fi
      case "$app" in
        tracearr)
          if [[ "$rc" == 0 ]]; then check "$(cat "$c/runtime-consumer" 2> /dev/null || true)" 'shared:emails:UPSTREAM LOGO' "$app/$variant native module/logo consumer"; fi
          if [[ "$role" == update ]]; then
            check "$(cat "$c/opt/$dir/data/cache" 2> /dev/null || true)" 'USER image cache' "$app/$variant live cache retained"
            check "$(cat "$c/data/tracearr/prestart.sh")" 'USER prestart PostgreSQL16 settings' "$app/$variant installed prestart/DB context retained"
          fi
          ;;
        twenty)
          if [[ "$rc" == 0 && "$role" == update ]]; then check "$(cat "$c/upgrade-consumer" 2> /dev/null || true)" 'app-owned upgrade' "$app supported upgrade-command consumer"; fi
          if [[ "$role" == update ]]; then
            check "$(cat "$c/opt/$dir/custom store with spaces/file" 2> /dev/null || true)" 'USER custom store' "$app/$variant inherited literal keep retained"
            check "$(cat "$c/opt/$dir/packages/twenty-server/.local-storage/file" 2> /dev/null || true)" 'USER stored file' "$app/$variant upload storage retained"
          fi
          ;;
        kima-hub)
          check "$(stat -c %s "$c/system-pip")" 0 "$app/$variant never mutates system Python"
          if [[ "$rc" == 0 ]]; then
            for service in kima-analyzer kima-analyzer-clap; do check "$(grep -c '/opt/kima-hub/venv/bin/python' "$c/etc/systemd/system/$service.service" || true)" 1 "$app/$variant $service selects isolated interpreter"; done
            check "$(cat "$c/python-version" 2> /dev/null || true)" 3.11 "$app/$variant wheel-compatible interpreter selection"
            status=0
            python3 - "$c/modeled-model-hashes" "$RUNTIME_EXTRA_REFERENCES/kima-hub/Dockerfile" << 'PY' || status=$?
import pathlib,re,sys
seen=set(re.findall(r'\b[0-9a-f]{64}\b',pathlib.Path(sys.argv[1]).read_text()))
official=set(re.findall(r'\b[0-9a-f]{64}\b',pathlib.Path(sys.argv[2]).read_text()))
assert len(seen)==9 and seen<=official,(seen-official,len(seen))
PY
            check "$status" 0 "$app/$variant all modeled integrity gates match immutable upstream inputs"
          fi
          if [[ "$role" == update ]]; then check "$(cat "$c/opt/$dir/models/user-model" 2> /dev/null || true)" 'USER model' "$app/$variant user models retained"; fi
          ;;
        paperclip)
          if [[ "$fault" == stale ]]; then check "$(stat -c %s "$c/unlocked")" 8 "$app/$variant exact stale diagnosis retries once with inherited higher-priority logs"; else check "$(stat -c %s "$c/unlocked")" 0 "$app/$variant no unrelated unlock fallback"; fi
          if [[ "$role" == update ]]; then check "$(cat "$c/opt/$dir/custom home/file" 2> /dev/null || true)" 'USER home data' "$app/$variant custom data home retained"; fi
          if [[ "$rc" == 0 && "$role" == update ]]; then
            status=0
            python3 - "$c/migration-consumer" << 'PY' || status=$?
import json,pathlib,sys
d=json.loads(pathlib.Path(sys.argv[1]).read_text());assert d=={'home':'/opt/paperclip-ai/custom home','database':'USER database'},d
PY
            check "$status" 0 "$app/$variant native migration subprocess consumes custom home and database"
          fi
          ;;
        paperless-ngx)
          case "$variant" in override-refuse | override-root-directory | malformed-config | ambiguous)
            check "$(stat -c %s "$c/effects")" 0 "$app/$variant refusal precedes every modeled effect"
            after_conf=$(sha256sum "$c/opt/$dir/paperless.conf")
            check "${after_conf%% *}" "$conf_before" "$app/$variant refusal preserves exact settings"
            check "$(cat "$c/opt/$dir/code")" 'old code' "$app/$variant refusal preserves source"
            check "$(test -f "$c/state/$app" && printf present || printf absent)" present "$app/$variant checked refusal retains pending truth"
            ;;
          esac
          if [[ "$variant" == override-valid && "$rc" == 0 ]]; then
            status=0
            python3 - "$c/opt/$dir/paperless.conf" "$MAINTENANCE_REFERENCES" "$c" << 'PY' || status=$?
import ast,fnmatch,json,pathlib,sys,typing
from dotenv import dotenv_values
from watchfiles import Change,DefaultFilter
config,refs,c=map(pathlib.Path,sys.argv[1:]);values=dotenv_values(config);patterns=json.loads(values['PAPERLESS_CONSUMER_IGNORE_PATTERNS'])
old=['ignore-*.pdf','scan?.pdf','literal.name.pdf','[ab]scan.pdf']
tree=ast.parse((refs/'paperless-v3/src/documents/management/commands/document_consumer.py').read_text());cls=next(n for n in tree.body if isinstance(n,ast.ClassDef) and any(isinstance(b,ast.Name) and b.id=='DefaultFilter' for b in n.bases));ns={'DefaultFilter':DefaultFilter,'Final':typing.Final,'Change':Change,'Path':pathlib.Path};exec(compile(ast.Module(body=[cls],type_ignores=[]),'actual-v3-consumer','exec'),ns);consumer=ns[cls.name](supported_extensions=frozenset({'.pdf'}),ignore_patterns=patterns)
for name in ('keep.pdf','ignore-one.pdf','scan1.pdf','literal.name.pdf','ascan.pdf','zzscan.pdf'):
 p=c/name;p.write_text('PDF fixture')
 expected=not any(fnmatch.fnmatchcase(name,pattern) for pattern in old)
 assert consumer(Change.added,str(p))==expected,(name,patterns)
assert values['PAPERLESS_SECRET_KEY']=='USER secret'
assert 'consumer-ignore-format=regex-v3' in config.read_text()
PY
            check "$status" 0 "$app supported conversion consumed exactly by actual v3 filter"
          fi
          if [[ "$variant" == override-directory && "$rc" == 0 ]]; then
            status=0
            python3 - "$c/opt/$dir/paperless.conf" "$MAINTENANCE_REFERENCES" "$c/consume" << 'PY' || status=$?
import ast,fnmatch,json,pathlib,sys,typing
from types import SimpleNamespace
from dotenv import dotenv_values
from watchfiles import Change,DefaultFilter
config,refs,consume=map(pathlib.Path,sys.argv[1:]);consume.mkdir();values=dotenv_values(config)
old=ast.parse((refs/'paperless-v2/src/documents/management/commands/document_consumer.py').read_text());fn=next(n for n in old.body if isinstance(n,ast.FunctionDef) and n.name=='_is_ignored');ns={'Path':pathlib.Path,'PurePath':pathlib.PurePath,'filter':fnmatch.filter,'settings':SimpleNamespace(CONSUMPTION_DIR=consume,CONSUMER_IGNORE_PATTERNS=['private/*'])};exec(compile(ast.Module(body=[fn],type_ignores=[]),'actual-v2','exec'),ns)
new=ast.parse((refs/'paperless-v3/src/documents/management/commands/document_consumer.py').read_text());cls=next(n for n in new.body if isinstance(n,ast.ClassDef) and n.name=='ConsumerFilter');ns3={'DefaultFilter':DefaultFilter,'Final':typing.Final,'Change':Change,'Path':pathlib.Path};exec(compile(ast.Module(body=[cls],type_ignores=[]),'actual-v3','exec'),ns3);consumer=ns3['ConsumerFilter'](supported_extensions=frozenset({'.pdf'}),ignore_patterns=json.loads(values['PAPERLESS_CONSUMER_IGNORE_PATTERNS']),ignore_dirs=json.loads(values['PAPERLESS_CONSUMER_IGNORE_DIRS']))
for name in ('private/scan.pdf','public/scan.pdf','public/private/scan.pdf','private-two/scan.pdf'):
 p=consume/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(b'PDF fixture');assert consumer(Change.added,str(p)) == (not ns['_is_ignored'](p)),name
PY
            check "$status" 0 "$app exact literal directory conversion reaches actual v3 consumer"
          fi
          if [[ "$variant" == regex-current ]]; then
            after_conf=$(sha256sum "$c/opt/$dir/paperless.conf")
            check "${after_conf%% *}" "$conf_before" "$app current explicit regex is byte-identical"
          fi
          if [[ "$variant" == restart-overrides && "$rc" == 0 ]]; then
            check "$(test -e "$c/etc/systemd/system/paperless-consumer.service.d/10-scripts-underground-restart.conf" && printf altered || printf preserved)" preserved "$app base Restart=no retained"
            check "$(test -e "$c/etc/systemd/system/paperless-scheduler.service.d/10-scripts-underground-restart.conf" && printf altered || printf preserved)" preserved "$app user drop-in Restart=always retained"
            restart_config_text=$(cat "$c/etc/systemd/system/paperless-task-queue.service.d/10-scripts-underground-restart.conf")
            check "$(grep -c '^RestartSec=' <<< "$restart_config_text" || true)" 0 "$app existing independent RestartSec retained"
          elif [[ "$rc" == 0 ]]; then
            for service in consumer scheduler task-queue webserver; do
              restart_config_text=$(cat "$c/etc/systemd/system/paperless-$service.service" "$c/etc/systemd/system/paperless-$service.service.d/"*.conf 2> /dev/null || true)
              check "$(grep -c Restart=on-failure <<< "$restart_config_text" || true)" 1 "$app/$variant $service crash restart configured"
            done
          fi
          ;;
      esac
      if [[ "$role" == update && "$fault" != none ]]; then
        retry_rc=0
        env -i PATH="$c/bin:$PATH" HOME="$c/home" TMPDIR="$TMPDIR" PYTHONPATH="${PYTHONPATH:-}" RUNTIME_NODE="$RUNTIME_NODE" MAINTENANCE_REFERENCES="$MAINTENANCE_REFERENCES" RUNTIME_EXTRA_REFERENCES="$RUNTIME_EXTRA_REFERENCES" var_appversion="$pin" APP_FIXTURE="$c" APP_CASE="$app" APP_ROLE="$role" APP_FAULT=none APP_DIR="$dir" APP="$app" NSAPP="$app" LOCAL_IP=10.20.30.40 VERBOSE="$mode" BUILD_LOG="$c/build.log" DEBUG_LOGFILE="$c/errors.log" \
          unshare -m --propagation private -- bash "$0" --child <<< n > "$c/retry-output" 2>&1 || retry_rc=$?
        check "$retry_rc" 0 "$app/$variant retry succeeds on the same preserved installation"
        if [[ "$retry_rc" != 0 ]]; then
          python3 - "$c/retry-output" << 'PY'
import pathlib,sys
for line in pathlib.Path(sys.argv[1]).read_text().splitlines()[-8:]:print('DIAG retry '+line)
PY
        fi
        check "$(test -f "$c/state/$app" && printf present || printf absent)" absent "$app/$variant successful retry clears pending truth"
        check "$(cat "$c/external/database")" 'USER database' "$app/$variant retry preserves existing database data"
        after=$(sha256sum "$c/opt/$dir/.env" 2> /dev/null) || after=missing
        check "${after%% *}" "$before" "$app/$variant retry preserves complete saved environment"
        case "$app" in
          tracearr) check "$(cat "$c/opt/$dir/data/cache" 2> /dev/null || true)" 'USER image cache' "$app/$variant retry retains live cache" ;;
          twenty) check "$(cat "$c/opt/$dir/packages/twenty-server/.local-storage/file" 2> /dev/null || true)" 'USER stored file' "$app/$variant retry retains uploads" ;;
          kima-hub) check "$(cat "$c/opt/$dir/models/user-model" 2> /dev/null || true)" 'USER model' "$app/$variant retry retains user models" ;;
          paperclip) check "$(cat "$c/opt/$dir/custom home/file" 2> /dev/null || true)" 'USER home data' "$app/$variant retry retains custom home" ;;
        esac
      fi
      if [[ "$app" == paperless-ngx && -z "$pin" && "$rc" == 0 ]]; then
        status=0
        python3 - "$c/release-tags" << 'PY' || status=$?
import pathlib,sys
requests=[line.split() for line in pathlib.Path(sys.argv[1]).read_text().splitlines() if '/paperless-ngx/paperless-ngx/releases/' in line]
assert requests and all(url.endswith('/tags/v2.20.15') and tag=='v2.20.15' for url,tag in requests),requests
PY
        check "$status" 0 "$app/$variant checker and deployer both retain default v2.20.15 pin"
      fi
      # Each case owns these fixtures; remove only this completed case, not history.
      rm -rf -- "$c"
    done
  done
done
printf '%s failure(s); actual cold hooks/helpers/files/Node/Dotenv consumers; compiled/runtime/service/model artifacts modeled\n' "$failures"
[[ "$failures" == 0 ]]
