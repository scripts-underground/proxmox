#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2026 scripts-underground.org
# Author: Alex Indigo (alexindigo)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/alexindigo/kosmozoo

# shellcheck disable=SC2034
APP="Kosmozoo"
var_tags="${var_tags:-comfyui;review;curation}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"
var_lxc_kosmozoo_state="${var_lxc_kosmozoo_state:-${KOZMOZOO_STATE:-/data/state}}"
var_lxc_kosmozoo_cache="${var_lxc_kosmozoo_cache:-${KOZMOZOO_CACHE:-/data/cache}}"
var_lxc_kosmozoo_hosts="${var_lxc_kosmozoo_hosts:-${KOZMOZOO_HOSTS:-}}"
var_lxc_kosmozoo_initial_release="${var_lxc_kosmozoo_initial_release:-${var_appversion:-latest}}"

function install_script() {
  (
    app_maintenance_acquire "${NSAPP:-}" || return $?
    # Both hooks are cold declare-f bundles. Their local validators deliberately
    # travel with each hook, rather than depending on script-global functions.
    local arch stage tag version digest association output actual path other pair name address value port hosts=''
    local var_appversion='' USE_ORIGINAL_FILENAME=false started=0 committed=0 fact_written=0
    arch=$(get_system_arch) || return $?
    [[ "$arch" == amd64 ]] || {
      msg_error 'Kosmozoo requires GNU/Linux x86_64'
      return 65
    }
    local libc
    libc=$(getconf GNU_LIBC_VERSION) || return 65
    [[ "$libc" =~ ^glibc\ ([0-9]+\.[0-9]+)$ && "$(printf '%s\n' 2.27 "${BASH_REMATCH[1]}" | sort -V | tail -n 1)" == "${BASH_REMATCH[1]}" ]] || {
      msg_error 'Native Kosmozoo requires glibc >=2.27 (not musl/Alpine)' >&2
      return 65
    }
    [[ ! -e /opt/kosmozoo && ! -L /opt/kosmozoo && ! -e /etc/kosmozoo/env &&
      ! -e /etc/systemd/system/kosmozoo.service && ! -e /etc/systemd/system/kosmozoo.service.d ]] || {
      msg_error 'Fresh installation requires an unused native layout'
      return 65
    }

    # One static runtime identity per cold hook. Root remains the administrator.
    local kz_user=kosmozoo kz_uid kz_gid kz_groups kz_account kz_account_home
    local -a kz_credentials=()
    kz_identity() {
      local record group extra groups
      record=$(getent passwd "$kz_user") || return 65
      [[ "$record" != *$'\n'* ]] || return 65
      IFS=: read -r kz_user _ kz_uid kz_gid _ kz_account_home _ <<< "$record"
      [[ "$kz_uid" =~ ^[0-9]+$ && "$kz_gid" =~ ^[0-9]+$ && "$kz_uid" != 0 && "$kz_gid" != 0 ]] || return 65
      kz_account=$kz_user
      record=$(getent initgroups "$kz_user") || return 65
      read -r group groups <<< "$record"
      [[ "$group" == "$kz_user" ]] || return 65
      extra=$kz_gid
      for group in $groups; do
        [[ "$group" =~ ^[0-9]+$ ]] || return 65
        extra+=" $group"
      done
      local -a group_ids=()
      read -r -a group_ids <<< "$extra"
      kz_groups=$(printf '%s\n' "${group_ids[@]}" | sort -nu | paste -sd,) || return $?
      kz_credentials=(setpriv "--reuid=$kz_uid" "--regid=$kz_gid" "--groups=$kz_groups")
    }
    if ! getent passwd kosmozoo > /dev/null; then
      useradd --system --user-group --home-dir /data --no-create-home --shell /usr/sbin/nologin kosmozoo ||
        return $?
    fi
    kz_identity || {
      msg_error 'Kosmozoo needs an existing valid static non-root account/group; account properties were not changed' >&2
      return 65
    }
    kz_access() {
      local path=$1 mode=$2 ancestor=$1
      while [[ "$mode" == write && "$ancestor" != / ]]; do
        [[ ! -L "$ancestor" ]] || return 65
        ancestor=${ancestor%/*}
        ancestor=${ancestor:-/}
      done
      [[ -d "$path" ]] || return 65
      if [[ "$mode" == write && "$(stat -c %u "$path")" != "$kz_uid" ]]; then
        msg_error "Existing runtime directory $path must be owned by UID $kz_uid; metadata was not changed" >&2
        return 65
      fi
      "${kz_credentials[@]}" /bin/sh -c 'test -r "$1" && test -x "$1" && { test "$2" != write || test -w "$1"; }' sh "$path" "$mode" || {
        msg_error "Runtime account $kz_account cannot access $path ($mode); provide ownership/access without changing existing data automatically" >&2
        return 65
      }
    }

    kz_path() {
      [[ "$1" == /* && "$1" != / && ! "$1" =~ [[:cntrl:]] ]] || return 65
      local resolved
      resolved=$(realpath -m -- "$1") || return $?
      [[ "$resolved" == "$1" ]] || return 65
      case "$resolved/" in /opt/ | /opt/kosmozoo/* | /etc/* | /usr/* | /bin/* | /sbin/* | /lib/* | /lib64/* | /proc/* | /sys/* | /dev/* | /root/*) return 65 ;; esac
    }
    # Validate the complete path set before making any directories. Existing
    # mounts/directories and their owners/modes are never changed.
    local -a paths=("$var_lxc_kosmozoo_state" "$var_lxc_kosmozoo_cache" /data/plugins /data/tmp)
    local -A distinct_paths=()
    for path in "${paths[@]}"; do
      kz_path "$path" || {
        msg_error "Invalid persistent path: $path"
        return 65
      }
      [[ ! -v 'distinct_paths[$path]' ]] || {
        msg_error 'Persistent path roles must be distinct'
        return 65
      }
      distinct_paths[$path]=1
      for other in /opt/kosmozoo "${paths[@]}"; do
        [[ "$path" == "$other" ]] && continue
        [[ "$path/" != "$other/"* && "$other/" != "$path/"* ]] || {
          msg_error 'State, cache, plugins, temporary storage and code must be separate'
          return 65
        }
      done
    done
    [[ "${paths[0]}" != "${paths[1]}" ]] || return 65
    kz_seed_error() {
      msg_error 'Invalid KOZMOZOO_HOSTS: use comma-separated unique name=host[:port] or name=folder:/absolute/path entries; HTTP decimal port 1..65535 (default 80); no controls or empty entries. Provide readable folder mounts inside the container before first start, or use an empty seed and add sources after mounting.' >&2
      return 65
    }
    [[ ! "$var_lxc_kosmozoo_hosts" =~ [[:cntrl:]] ]] || {
      kz_seed_error
      return 65
    }
    # Current source trims seed pairs; controls remain intentionally forbidden.
    var_lxc_kosmozoo_hosts=${var_lxc_kosmozoo_hosts#"${var_lxc_kosmozoo_hosts%%[! ]*}"}
    var_lxc_kosmozoo_hosts=${var_lxc_kosmozoo_hosts%"${var_lxc_kosmozoo_hosts##*[! ]}"}
    local -A names=()
    if [[ -n "$var_lxc_kosmozoo_hosts" ]]; then
      [[ "$var_lxc_kosmozoo_hosts" != ,* && "$var_lxc_kosmozoo_hosts" != *, && "$var_lxc_kosmozoo_hosts" != *,,* ]] || {
        kz_seed_error
        return 65
      }
      local -a pairs
      IFS=, read -r -a pairs <<< "$var_lxc_kosmozoo_hosts"
      for pair in "${pairs[@]}"; do
        [[ "$pair" == *=* ]] || {
          kz_seed_error
          return 65
        }
        name=${pair%%=*} address=${pair#*=}
        name=${name#"${name%%[! ]*}"} name=${name%"${name##*[! ]}"}
        address=${address#"${address%%[! ]*}"} address=${address%"${address##*[! ]}"}
        [[ "$name" =~ ^[a-zA-Z0-9_][a-zA-Z0-9_.-]*$ && ! -v 'names[$name]' ]] || {
          kz_seed_error
          return 65
        }
        names[$name]=1
        if [[ "$address" == folder:/* ]]; then
          path=${address#folder:}
          kz_access "$path" read || {
            msg_error "Folder seed is not an accessible directory inside the container: $path. Mount/provide it before first start, or use KOZMOZOO_HOSTS='' and add it after mounting." >&2
            return 65
          }
        else
          [[ "$address" =~ ^[a-zA-Z0-9_.-]+(:[0-9]+)?$ ]] || {
            kz_seed_error
            return 65
          }
          port=80
          [[ "$address" != *:* ]] || port=${address##*:}
          # Bound the decimal representation before arithmetic. Strip zeros in
          # one expansion, including arbitrarily long all-zero inputs.
          port=${port#"${port%%[!0]*}"} port=${port:-0}
          [[ ${#port} -le 5 ]] && ((10#$port >= 1 && 10#$port <= 65535)) || {
            kz_seed_error
            return 65
          }
          # Explicit :80 also works with the older published v0.2.2 parser.
          address=${address%%:*}:$((10#$port))
        fi
        hosts+="${hosts:+,}$name=$address"
      done
    fi
    var_lxc_kosmozoo_hosts=$hosts

    # Installer/updater OS support, not a dependency of the native engine.
    $STD apt install -y ca-certificates curl jq iproute2 dbus || return $?
    if ! systemctl is-active --quiet dbus.socket; then
      systemctl start dbus.socket || return $?
    fi
    systemctl is-active --quiet dbus.socket || {
      msg_error 'Debian dbus.socket is not active; repair the OS system bus before installing Kosmozoo' >&2
      return 1
    }
    timeout 15 busctl --system --json=short get-property org.freedesktop.systemd1 /org/freedesktop/systemd1 org.freedesktop.systemd1.Manager Version > /dev/null || {
      local status=$?
      msg_error 'Debian dbus system bus is unavailable; check dbus.socket/dbus.service before installing Kosmozoo' >&2
      return "$status"
    }
    mkdir -m 0755 /opt/kosmozoo || return $?
    mkdir -p /etc/kosmozoo || return $?
    kz_access /opt/kosmozoo read || return 65
    stage=$(mktemp -d /opt/kosmozoo/.stage.XXXXXXXX) || return $?
    kz_install_recover() {
      local status=$? end active='' p='' group='' members='' result=''
      trap - EXIT
      if [[ "$status" != 0 && "$started" == 1 && "$committed" == 0 ]]; then
        timeout --signal=TERM --kill-after=5 50 systemctl stop kosmozoo || true
        end=$((SECONDS + 15))
        while :; do
          p=$(systemctl show kosmozoo -p MainPID --value) || break
          active=$(systemctl show kosmozoo -p ActiveState --value) || break
          group=$(systemctl show kosmozoo -p ControlGroup --value) || break
          if [[ "$p" == 0 && ("$active" == inactive || "$active" == failed) ]]; then
            members=''
            if [[ -n "$group" ]]; then
              [[ "$group" == /* && "$group" != / && "$group" != *..* ]] || break
              if [[ -d "/sys/fs/cgroup$group" ]]; then
                members=$(find "/sys/fs/cgroup$group" -name cgroup.procs -type f -exec cat {} +) || break
              fi
            fi
            [[ -z "$members" ]] && break
          fi
          ((SECONDS < end)) || break
          sleep 1
        done
        if systemctl disable kosmozoo; then
          result=$(systemctl is-enabled kosmozoo) || true
          [[ "$result" == disabled && "$p" == 0 && -z "$members" ]] || msg_error 'Unresolved candidate stop/boot-link state; do not start older code'
        else
          msg_error 'Could not disable candidate boot links; candidate/recovery retained'
        fi
        msg_error "Activation failed; state retained; service must remain stopped/disabled. Recovery: $stage"
      elif [[ "$status" != 0 && "$committed" == 1 ]]; then
        msg_error "Activation committed; healthy new code retained; cleanup pending at $stage"
      elif [[ "$status" != 0 && "$started" == 0 ]]; then
        local safe=1 file
        if [[ "$fact_written" == 1 ]]; then
          rm -f -- /opt/kosmozoo/activation-attempt.json || safe=0
          [[ ! -e /opt/kosmozoo/activation-attempt.json && ! -L /opt/kosmozoo/activation-attempt.json ]] || safe=0
        fi
        if [[ "$safe" == 1 ]]; then
          # Public release/probe identities go to the existing framework log;
          # do not retain full pre-start payloads or print private next-start env.
          msg_error "Pre-start failure (status=$status); retiring current stage $stage" >&2
          for file in selected.json deployed.json version.txt kosmozoo; do
            [[ ! -f "$stage/$file" ]] || sha256sum -- "$stage/$file" >&2 || true
          done
          for file in selected.json deployed.json; do
            [[ ! -f "$stage/$file" ]] || jq -c '{id,tag_name,assets:[.assets[]? | {id,name,size,digest}]}' "$stage/$file" >&2 || true
          done
          [[ ! -f "$stage/version.txt" ]] || cat "$stage/version.txt" >&2 || true
          rm -r -- "$stage" || msg_error "Stage retirement incomplete; retained diagnostics at $stage" >&2
        else
          msg_error "Pre-start fact recovery incomplete; retained $stage" >&2
        fi
      fi
      exit "$status"
    }
    trap kz_install_recover EXIT
    chmod 0700 "$stage" || return $?
    mkdir -m 0700 "$stage/home" "$stage/tmp" || return $?
    local HOME="$stage/home" TMPDIR="$stage/tmp"
    # An install-only pin crosses the bundle boundary; it never pins updates.
    local CHECK_UPDATE_RELEASE='' rc=0
    check_for_gh_release kosmozoo alexindigo/kosmozoo "$var_lxc_kosmozoo_initial_release" || rc=$?
    [[ "$rc" == 0 ]] || return "$rc"
    tag=$CHECK_UPDATE_RELEASE version=${CHECK_UPDATE_RELEASE#v}
    [[ "$version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || return 65
    _gh_release_json alexindigo/kosmozoo "$tag" '' "$stage/selected.json" || return $?
    kz_metadata() {
      jq -cer --arg tag "$tag" '
      select(.id | type == "number" and . > 0) |
      select(.tag_name == $tag and .draft == false and .prerelease == false) |
      select(.published_at | type == "string" and length > 0) |
      [.id, .tag_name, ([.assets[] | select(.name == "kosmozoo-linux-x86_64")] |
        select(length == 1) | .[0] |
        select(.id | type == "number" and . > 0) |
        select(.digest | type == "string" and test("^sha256:[0-9a-f]{64}$")) |
        select(.browser_download_url == ("https://github.com/alexindigo/kosmozoo/releases/download/" + $tag + "/kosmozoo-linux-x86_64")) |
        {id, name, digest, size, browser_download_url}),
        ([.assets[] | select(.name == "SHA256SUMS")] | select(length == 1) | .[0] |
        select(.id | type == "number" and . > 0) |
        select(.browser_download_url == ("https://github.com/alexindigo/kosmozoo/releases/download/" + $tag + "/SHA256SUMS")) |
        {id,name,browser_download_url})] | select(length == 4)' "$1"
    }
    association=$(kz_metadata "$stage/selected.json") || return 65
    digest=$(jq -er '.[2].digest | ltrimstr("sha256:")' <<< "$association") || return $?
    fetch_and_deploy_gh_release kosmozoo alexindigo/kosmozoo singlefile "$tag" "$stage" kosmozoo-linux-x86_64 '' "$stage/deployed.json" || return $?
    actual=$(kz_metadata "$stage/deployed.json") || return 65
    [[ "$actual" == "$association" ]] || return 65
    # The checksum list must belong to the very same selected release as the ELF.
    curl_download "$stage/SHA256SUMS" "$(jq -er '.[3].browser_download_url' <<< "$association")" || return $?
    LC_ALL=C tr -d '\000' < "$stage/SHA256SUMS" > "$stage/checksum-text" || return $?
    cmp -s "$stage/SHA256SUMS" "$stage/checksum-text" || return 65
    local line checksum_count=0 checksum_hash='' checksum_grammar='^([0-9a-f]{64}) [ *]([^[:cntrl:]]+)$'
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ "$line" =~ $checksum_grammar ]] || return 65
      if [[ "${BASH_REMATCH[2]}" == kosmozoo-linux-x86_64 ]]; then
        checksum_count=$((checksum_count + 1)) checksum_hash=${BASH_REMATCH[1]}
      fi
    done < "$stage/SHA256SUMS"
    [[ "$checksum_count" == 1 && "$checksum_hash" == "$digest" ]] || return 65
    printf '%s  %s\n' "$digest" "$stage/kosmozoo" | sha256sum --check --strict || return 65
    [[ -f "$stage/kosmozoo" && ! -L "$stage/kosmozoo" ]] || return 65
    [[ "$(od -An -tx1 -N4 "$stage/kosmozoo" | tr -d ' \n')" == 7f454c46 ]] || return 65
    chmod 0755 "$stage/kosmozoo" || return $?
    output=$(timeout 15 env -i PATH=/usr/bin:/bin HOME="$stage/home" TMPDIR="$stage/tmp" "$stage/kosmozoo" --version) || return $?
    printf '%s\n' "$output" > "$stage/version.txt" || return $?
    local grammar='^kosmozoo v([0-9]+\.[0-9]+(\.[0-9]+)?)( \([0-9a-f]{7}\)|-dev) \(input ([0-9a-f]{64}|working-source); Deno [0-9]+\.[0-9]+\.[0-9]+; x86_64-unknown-linux-gnu\)$'
    [[ "$output" =~ $grammar && "${BASH_REMATCH[1]}" == "$version" ]] || return 65
    for path in /data "${paths[@]}"; do
      # Create only missing components; never repair an existing directory.
      local ancestor=$path component accumulated=''
      local -a components=()
      IFS=/ read -r -a components <<< "$ancestor"
      for component in "${components[@]}"; do
        [[ -n "$component" ]] || continue
        accumulated+=/$component
        [[ ! -L "$accumulated" ]] || return 65
        if [[ ! -e "$accumulated" ]]; then
          mkdir -m 0755 -- "$accumulated" && chown "$kz_uid:$kz_gid" "$accumulated" || return $?
        fi
      done
      kz_access "$path" write || return 65
    done
    for path in "$var_lxc_kosmozoo_state/engine.lock" "$var_lxc_kosmozoo_state/engine-instance.json"; do
      if [[ -e "$path" || -L "$path" ]]; then
        [[ -f "$path" && ! -L "$path" && "$(stat -c '%u:%a' "$path")" == "$kz_uid:600" ]] || {
          msg_error "Existing runtime-private file $path has incompatible ownership/mode; preserve it and resolve the runtime identity before retrying" >&2
          return 65
        }
      fi
    done
    case "$(findmnt -rn -T "$var_lxc_kosmozoo_state" -o FSTYPE)" in ext2 | ext3 | ext4 | xfs | btrfs | zfs | f2fs | bcachefs) : ;; *)
      msg_error 'State needs a real local filesystem for SQLite WAL/locking (not NFS/SMB)' >&2
      return 65
      ;;
    esac
    case "$(findmnt -rn -T /data/tmp -o FSTYPE)" in '' | tmpfs | ramfs) return 65 ;; esac
    [[ ",$(findmnt -rn -T /data/tmp -o OPTIONS)," != *,noexec,* ]] || return 65
    # A runtime-owned projection, never traversable private administrative staging.
    local projection
    projection=$("${kz_credentials[@]}" mktemp -d /data/tmp/kosmozoo-probe.XXXXXXXX) || return $?
    if install -o "$kz_uid" -g "$kz_gid" -m 0700 "$stage/kosmozoo" "$projection/kosmozoo" &&
      timeout 15 "${kz_credentials[@]}" env -i PATH=/usr/bin:/bin HOME=/data TMPDIR=/data/tmp "$projection/kosmozoo" --version > "$stage/runtime-version.txt"; then rc=0; else rc=$?; fi
    rm -r -- "$projection" || return $?
    [[ "$rc" == 0 ]] || return "$rc"
    [[ "$(cat "$stage/runtime-version.txt")" == "$output" ]] || return 65
    kz_assignment() {
      value=${2//\\/\\\\} value=${value//\"/\\\"}
      value=${value//\$/\\\$} value=${value//\`/\\\`}
      printf '%s="%s"\n' "$1" "$value"
    }
    {
      kz_assignment HOME /data && kz_assignment TMPDIR /data/tmp &&
        kz_assignment KOZMOZOO_STATE "$var_lxc_kosmozoo_state" &&
        kz_assignment KOZMOZOO_CACHE "$var_lxc_kosmozoo_cache" &&
        kz_assignment KOZMOZOO_PLUGINS /data/plugins &&
        kz_assignment KOZMOZOO_HOSTS "$var_lxc_kosmozoo_hosts" &&
        kz_assignment KOZMOZOO_BIND 0.0.0.0 && kz_assignment KOZMOZOO_PORT 80
    } > "$stage/env" || return $?
    kz_assignment KOZMOZOO_HOSTS "$var_lxc_kosmozoo_hosts" > "$stage/expected-hosts" || return $?
    grep -Fxq -f "$stage/expected-hosts" "$stage/env" || {
      msg_error 'KOZMOZOO_HOSTS must be explicitly rendered; an empty value disables default seeding' >&2
      return 65
    }
    install -m 0600 "$stage/env" /etc/kosmozoo/env || return $?
    cmp -s "$stage/env" /etc/kosmozoo/env || {
      msg_error 'Installed /etc/kosmozoo/env differs from validated configuration; explicit KOZMOZOO_HOSTS is required before start' >&2
      return 65
    }
    cat << 'EOF' > /etc/systemd/system/kosmozoo.service || return $?
[Unit]
Description=Kosmozoo native review engine
After=network.target

[Service]
Type=simple
User=kosmozoo
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
WorkingDirectory=/opt/kosmozoo
EnvironmentFile=/etc/kosmozoo/env
ExecStart=/opt/kosmozoo/kosmozoo serve
Restart=on-failure
RestartSec=5
TimeoutStopSec=45s
SendSIGKILL=no

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload || return $?
    # Record before publication: even first-start failures can have opened state.
    jq -n --arg release "$version" --arg digest "$digest" --arg recovery "$stage" \
      '{version:1, release:$release, digest:$digest, enabled:true, recovery:$recovery}' > "$stage/attempt.json" || return $?
    chmod 0600 "$stage/attempt.json" || return $?
    fact_written=1
    mv -T "$stage/attempt.json" /opt/kosmozoo/activation-attempt.json || return $?
    mv -T "$stage/kosmozoo" /opt/kosmozoo/kosmozoo || return $?
    local ready=0 pid deadline=$((SECONDS + 90))
    kz_install_environment() {
      local entry
      local -A environment=()
      while IFS= read -r -d '' entry; do environment[${entry%%=*}]=${entry#*=}; done < "/proc/$1/environ" || return $?
      [[ "${environment[HOME]-}" == /data && "${environment[TMPDIR]-}" == /data/tmp &&
        "${environment[KOZMOZOO_STATE]-}" == "$var_lxc_kosmozoo_state" &&
        "${environment[KOZMOZOO_CACHE]-}" == "$var_lxc_kosmozoo_cache" &&
        "${environment[KOZMOZOO_HOSTS]+present}" == present && "${environment[KOZMOZOO_HOSTS]-}" == "$var_lxc_kosmozoo_hosts" &&
        "${environment[KOZMOZOO_PLUGINS]-}" == /data/plugins &&
        "${environment[KOZMOZOO_BIND]-}" == 0.0.0.0 && "${environment[KOZMOZOO_PORT]-}" == 80 ]]
    }
    kz_process_identity() {
      local field a b c d groups='' saw_uid=0 saw_gid=0
      local -a group_ids=()
      while read -r field a b c d; do
        case "$field" in
          Uid:)
            [[ "$a:$b:$c:$d" == "$kz_uid:$kz_uid:$kz_uid:$kz_uid" ]] || return 65
            saw_uid=1
            ;;
          Gid:)
            [[ "$a:$b:$c:$d" == "$kz_gid:$kz_gid:$kz_gid:$kz_gid" ]] || return 65
            saw_gid=1
            ;;
          Groups:)
            read -r -a group_ids <<< "$a $b $c $d"
            groups=$(printf '%s\n' "${group_ids[@]}" | sort -nu | paste -sd,) || return $?
            ;;
        esac
      done < "/proc/$1/status"
      [[ "$saw_uid:$saw_gid" == 1:1 && "$groups" == "$kz_groups" ]]
    }
    started=1
    if timeout --signal=TERM --kill-after=5 90 systemctl start kosmozoo; then
      while ((SECONDS < deadline)); do
        pid=$(systemctl show kosmozoo -p MainPID --value) || break
        if [[ "$pid" =~ ^[1-9][0-9]*$ && "$(readlink "/proc/$pid/exe")" == /opt/kosmozoo/kosmozoo ]] && kz_process_identity "$pid" && kz_install_environment "$pid" &&
          curl --noproxy '*' --fail --silent --max-time 2 http://127.0.0.1:80/api/runtime > "$stage/runtime.json" &&
          [[ -f "$var_lxc_kosmozoo_state/engine-instance.json" && ! -L "$var_lxc_kosmozoo_state/engine-instance.json" ]] &&
          [[ "$(stat -c '%u:%a' "$var_lxc_kosmozoo_state/engine-instance.json")" == "$kz_uid:600" ]] &&
          jq -e --arg v "$version" --argjson pid "$pid" --slurpfile private "$var_lxc_kosmozoo_state/engine-instance.json" '
          .protocol == "kosmozoo-runtime" and .version == 1 and .status == "ready" and .mode == "serve" and
          .configuredBind == "0.0.0.0" and .binding == {hostname:"0.0.0.0",port:80} and .app.version == $v and
          (.instance | test("^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")) and
          .instance == $private[0].instance and .sourceVersion == $private[0].sourceVersion and
          .binding == $private[0].binding and $private[0].ownerPid == $pid' "$stage/runtime.json" > /dev/null &&
          ss -H -lntp 'sport = :80' | grep -Fq "pid=$pid,"; then
          ready=1
          break
        fi
        systemctl is-active --quiet kosmozoo || break
        sleep 1
      done
    fi
    if [[ "$ready" != 1 ]]; then
      return 1
    fi
    printf '%s\n' "$version" > /root/.kosmozoo.new || return $?
    mv -T /root/.kosmozoo.new /root/.kosmozoo || return $?
    systemctl enable kosmozoo || return $?
    [[ "$(systemctl is-enabled kosmozoo)" == enabled ]] || return 1
    [[ "$(cat /root/.kosmozoo)" == "$version" ]] || return 1
    committed=1
    rm -- /opt/kosmozoo/activation-attempt.json || return $?
    rm -r -- "$stage" || return $?
    msg_ok "Installed Kosmozoo $version (native GNU/Linux x86_64)"
  )
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
  echo -e "${INFO}${YW}Add sources in the UI; persistent configuration is /etc/kosmozoo/env inside the container.${CL}"
  echo -e "${INFO}${YW}No authentication by design - trusted LAN only.${CL}"
}

function update_script() {
  (
    app_maintenance_acquire "${NSAPP:-}" || return $?
    local code=/opt/kosmozoo/kosmozoo fact=/opt/kosmozoo/activation-attempt.json
    local marker=/root/.kosmozoo stage='' started=0 committed=0 stopped=0 running=0
    local enabled='' prior='' tag='' version='' digest='' association='' actual='' output='' rc=0 pid='' group=''
    local current='' marked='' floor='' attempt='' stop_us stop_seconds property data item state cache bind port home
    local requested="${var_appversion:-latest}" var_appversion=''
    local -x USE_ORIGINAL_FILENAME=false
    local UPDATE_FORCE="${UPDATE_FORCE:-0}"
    local bus=/org/freedesktop/systemd1/unit/kosmozoo_2eservice
    local environment_files='' had_fact=0 fact_written=0 publication_attempted=0 stop_attempted=0
    local -A next=() process=()
    local kz_user kz_uid kz_gid kz_groups kz_account kz_account_home kz_unit_identity
    local -a kz_credentials=()
    kz_identity_inputs() {
      local field
      for field in User Group SupplementaryGroups DynamicUser RootDirectory RootImage PrivateUsers; do
        printf '%s=' "$field"
        systemctl show kosmozoo -p "$field" --value || return $?
        printf '\n'
      done
    }
    kz_identity() {
      local record group extra groups unit_group supplementary dynamic root_directory root_image private_users
      kz_unit_identity=$(kz_identity_inputs) || return $?
      kz_user=$(systemctl show kosmozoo -p User --value) || return $?
      kz_user=${kz_user:-root}
      unit_group=$(systemctl show kosmozoo -p Group --value) || return $?
      supplementary=$(systemctl show kosmozoo -p SupplementaryGroups --value) || return $?
      dynamic=$(systemctl show kosmozoo -p DynamicUser --value) || return $?
      root_directory=$(systemctl show kosmozoo -p RootDirectory --value) || return $?
      root_image=$(systemctl show kosmozoo -p RootImage --value) || return $?
      private_users=$(systemctl show kosmozoo -p PrivateUsers --value) || return $?
      [[ "$dynamic" == no && -z "$root_directory" && -z "$root_image" && "$private_users" == no ]] || return 65
      record=$(getent passwd "$kz_user") || return 65
      [[ "$record" != *$'\n'* ]] || return 65
      IFS=: read -r kz_user _ kz_uid kz_gid _ kz_account_home _ <<< "$record"
      [[ "$kz_uid" =~ ^[0-9]+$ && "$kz_gid" =~ ^[0-9]+$ ]] || return 65
      kz_account=$kz_user
      if [[ -n "$unit_group" ]]; then
        record=$(getent group "$unit_group") || return 65
        [[ "$record" != *$'\n'* ]] || return 65
        IFS=: read -r _ _ kz_gid _ <<< "$record"
        [[ "$kz_gid" =~ ^[0-9]+$ ]] || return 65
      fi
      # NSS supplementary membership excludes the passwd primary GID; the unit
      # may select a different primary group. Do not re-add the old primary.
      record=$(getent initgroups "$kz_user") || return 65
      read -r group groups <<< "$record"
      [[ "$group" == "$kz_user" ]] || return 65
      # systemd does not initialize NSS supplementary groups for UID0. Only
      # explicit SupplementaryGroups apply there; the effective GID is separate.
      if [[ "$kz_uid" == 0 ]]; then
        groups=''
        extra=''
      else extra=$kz_gid; fi
      for group in $groups; do
        [[ "$group" =~ ^[0-9]+$ ]] || return 65
        extra+=" $group"
      done
      for group in $supplementary; do
        record=$(getent group "$group") || return 65
        [[ "$record" != *$'\n'* ]] || return 65
        IFS=: read -r _ _ group _ <<< "$record"
        [[ "$group" =~ ^[0-9]+$ ]] || return 65
        extra+=" $group"
      done
      local -a group_ids=()
      read -r -a group_ids <<< "$extra"
      kz_groups=$(printf '%s\n' "${group_ids[@]}" | sort -nu | paste -sd,) || return $?
      kz_credentials=(setpriv "--reuid=$kz_uid" "--regid=$kz_gid")
      if [[ -n "$kz_groups" ]]; then kz_credentials+=("--groups=$kz_groups"); else kz_credentials+=(--clear-groups); fi
      [[ "$(kz_identity_inputs)" == "$kz_unit_identity" ]]
    }
    kz_access() {
      local path=$1 mode=$2 ancestor=$1
      while [[ "$mode" == write && "$ancestor" != / ]]; do
        [[ ! -L "$ancestor" ]] || return 65
        ancestor=${ancestor%/*}
        ancestor=${ancestor:-/}
      done
      [[ -d "$path" ]] || return 65
      if [[ "$mode" == write && "$(stat -c %u "$path")" != "$kz_uid" ]]; then
        msg_error "Existing runtime directory $path must be owned by UID $kz_uid; metadata was not changed" >&2
        return 65
      fi
      "${kz_credentials[@]}" /bin/sh -c 'test -r "$1" && test -x "$1" && { test "$2" != write || test -w "$1"; }' sh "$path" "$mode" || {
        msg_error "Runtime account $kz_account cannot access $path ($mode); provide ownership/access without changing existing data automatically" >&2
        return 65
      }
    }
    kz_process_identity() {
      local field a b c d groups='' saw_uid=0 saw_gid=0
      local -a group_ids=()
      while read -r field a b c d; do
        case "$field" in
          Uid:)
            [[ "$a:$b:$c:$d" == "$kz_uid:$kz_uid:$kz_uid:$kz_uid" ]] || return 65
            saw_uid=1
            ;;
          Gid:)
            [[ "$a:$b:$c:$d" == "$kz_gid:$kz_gid:$kz_gid:$kz_gid" ]] || return 65
            saw_gid=1
            ;;
          Groups:)
            read -r -a group_ids <<< "$a $b $c $d"
            groups=$(printf '%s\n' "${group_ids[@]}" | sort -nu | paste -sd,) || return $?
            ;;
        esac
      done < "/proc/$1/status"
      [[ "$saw_uid:$saw_gid" == 1:1 && "$groups" == "$kz_groups" ]]
    }

    kz_property() {
      local status=0
      timeout 15 busctl --system --json=short get-property org.freedesktop.systemd1 "$bus" org.freedesktop.systemd1.Service "$1" || status=$?
      if [[ "$status" != 0 ]]; then
        msg_error "Cannot read $1 (status=$status): verify the Debian dbus package and active dbus.socket/dbus.service, then retry; updater will not install or reconfigure the system bus" >&2
      fi
      return "$status"
    }
    kz_version() {
      local text grammar='^kosmozoo v([0-9]+\.[0-9]+(\.[0-9]+)?)( \([0-9a-f]{7}\)|-dev) \(input ([0-9a-f]{64}|working-source); Deno [0-9]+\.[0-9]+\.[0-9]+; x86_64-unknown-linux-gnu\)$'
      text=$(timeout 15 env -i PATH=/usr/bin:/bin HOME="$stage/home" TMPDIR="$stage/tmp" "$1" --version) || return $?
      [[ "$text" =~ $grammar ]] || return 65
      printf '%s\n' "$text" >&2
      printf '%s\n' "${BASH_REMATCH[1]}"
    }
    kz_normalize() {
      local value=${1#v} component result='' i
      [[ "$value" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || return 65
      [[ "$value" == *.*.* ]] || value+=.0
      for ((i = 0; i < 3; i++)); do
        component=${value%%.*} value=${value#*.}
        while [[ ${#component} -gt 1 && "$component" == 0* ]]; do component=${component#0}; done
        result+="${result:+.}$component"
      done
      printf '%s\n' "$result"
    }
    kz_empty() {
      local p active c members
      p=$(systemctl show kosmozoo -p MainPID --value) || return $?
      active=$(systemctl show kosmozoo -p ActiveState --value) || return $?
      c=$(systemctl show kosmozoo -p ControlGroup --value) || return $?
      [[ "$p" == 0 && ("$active" == inactive || "$active" == failed) ]] || return 1
      [[ -n "$c" ]] || return 0
      [[ "$c" == /* && "$c" != / && "$c" != *..* ]] || return 1
      [[ -d "/sys/fs/cgroup$c" ]] || return 0
      members=$(find "/sys/fs/cgroup$c" -name cgroup.procs -type f -exec cat {} +) || return $?
      [[ -z "$members" ]]
    }
    kz_stop() {
      local end status=0
      timeout --signal=TERM --kill-after=5 "$stop_seconds" systemctl stop kosmozoo || status=$?
      end=$((SECONDS + 15))
      while ! kz_empty; do
        if ((SECONDS >= end)); then
          systemctl show kosmozoo -p ActiveState -p SubState -p MainPID -p ControlGroup >&2 || true
          msg_error 'Writers remain; candidate/code restoration is forbidden'
          return 1
        fi
        sleep 1
      done
      [[ "$running" == 0 ]] || stopped=1
      return "$status"
    }
    kz_disabled() {
      local result
      systemctl disable kosmozoo || return $?
      result=$(systemctl is-enabled kosmozoo) || [[ "$result" == disabled ]] || return 1
      [[ "$result" == disabled ]]
    }
    kz_recover() {
      local status=$? safe=1 file
      trap - EXIT
      if [[ "$status" != 0 && "$committed" == 0 && "$started" == 1 ]]; then
        # Candidate may have opened SQLite. Never restore state or let restored
        # older code boot automatically. Stop/disable failures retain candidate.
        if kz_stop && kz_disabled && kz_empty; then
          if [[ -f "$stage/previous" ]]; then
            mv -T "$stage/previous" "$code" || safe=0
          fi
          if [[ -f "$stage/marker" ]]; then
            cp -- "$stage/marker" /root/.kosmozoo.recovery && mv -T /root/.kosmozoo.recovery "$marker" || safe=0
          else
            rm -f -- "$marker" || safe=0
          fi
        else
          msg_error 'Could not stop/disable candidate; retained candidate code and recovery material'
        fi
        msg_error "State was not rolled back. Leave service stopped/disabled; same/newer repair required. Recovery: $stage"
      elif [[ "$status" != 0 && "$committed" == 0 && "$started" == 0 ]]; then
        if [[ "$stop_attempted" == 1 ]]; then kz_empty || safe=0; fi
        if [[ "$publication_attempted" == 1 && "$safe" == 1 ]]; then
          if kz_empty && [[ -f "$stage/previous" ]]; then
            if ! cmp -s "$stage/previous" "$code"; then mv -T "$stage/previous" "$code" || safe=0; fi
          else
            safe=0
          fi
        fi
        if [[ "$fact_written" == 1 && "$safe" == 1 ]]; then
          if [[ "$had_fact" == 1 ]]; then
            if [[ -f "$fact" && ! -L "$fact" && "$(stat -c '%u:%a' "$fact")" == 0:600 ]] && cmp -s "$stage/prior-attempt.json" "$fact"; then
              : # Failed atomic publication may have left the exact prior fact intact.
            else
              cp -- "$stage/prior-attempt.json" "$stage/restore-attempt.json" && chmod 0600 "$stage/restore-attempt.json" &&
                mv -T "$stage/restore-attempt.json" "$fact" && cmp -s "$stage/prior-attempt.json" "$fact" || safe=0
            fi
          else
            if [[ -e "$fact" || -L "$fact" ]]; then rm -f -- "$fact" || safe=0; fi
            [[ ! -e "$fact" && ! -L "$fact" ]] || safe=0
          fi
        fi
        # Only this invocation's previously-running, untouched writer is eligible.
        if [[ "$safe" == 1 && "$stopped" == 1 && "$running" == 1 ]]; then systemctl start kosmozoo || safe=0; fi
        if [[ "$safe" == 1 ]]; then
          msg_error "Pre-start failure (status=$status); retiring current stage $stage; prior recovery untouched" >&2
          for file in selected.json deployed.json kosmozoo previous; do
            [[ ! -f "$stage/$file" ]] || sha256sum -- "$stage/$file" >&2 || true
          done
          for file in selected.json deployed.json; do
            [[ ! -f "$stage/$file" ]] || jq -c '{id,tag_name,assets:[.assets[]? | {id,name,size,digest}]}' "$stage/$file" >&2 || true
          done
          rm -r -- "$stage" || msg_error "Stage retirement incomplete; retained diagnostics at $stage" >&2
        else
          msg_error "Pre-start recovery incomplete; retained $stage; original status=$status" >&2
        fi
      fi
      if [[ "$status" != 0 && "$committed" == 1 ]]; then
        msg_error "Activation committed; healthy new code retained, cleanup pending at $stage"
      fi
      exit "$status"
    }

    # After ownership, layout admission is the first app-specific gate: no Git operation/release selection/stop is
    # permitted merely because an obsolete directory or branch marker exists.
    [[ -f "$code" && ! -L "$code" && -x "$code" && -f /etc/kosmozoo/env && ! -L /etc/kosmozoo/env ]] || {
      msg_error 'No native Kosmozoo installation found (fresh native layout required)'
      return 65
    }
    [[ "$(od -An -tx1 -N4 "$code" | tr -d ' \n')" == 7f454c46 ]] || return 65
    property=$(systemctl show kosmozoo -p ExecStart --value) || return $?
    [[ "$property" == *'path=/opt/kosmozoo/kosmozoo ; argv[]=/opt/kosmozoo/kosmozoo serve ;'* ]] || return 65
    kz_identity || {
      msg_error 'Cannot resolve effective static User/Group/SupplementaryGroups: DynamicUser, private user namespaces and alternate roots are unsupported; retain the unit/data and configure a resolvable static identity before retrying' >&2
      return 65
    }
    [[ "$(get_system_arch)" == amd64 ]] || return 65
    property=$(getconf GNU_LIBC_VERSION) || return 65
    [[ "$property" =~ ^glibc\ ([0-9]+\.[0-9]+)$ && "$(printf '%s\n' 2.27 "${BASH_REMATCH[1]}" | sort -V | tail -n 1)" == "${BASH_REMATCH[1]}" ]] || {
      msg_error 'Native Kosmozoo requires glibc >=2.27 (not musl/Alpine)' >&2
      return 65
    }
    if [[ -e "$fact" || -L "$fact" ]]; then
      [[ -f "$fact" && ! -L "$fact" && "$(stat -c '%u:%a' "$fact")" == 0:600 ]] || return 65
      jq -e 'type == "object" and (keys | sort) == ["digest","enabled","recovery","release","version"] and
        .version == 1 and (.release | type == "string" and test("^[0-9]+\\.[0-9]+(\\.[0-9]+)?$")) and
        (.digest | type == "string" and test("^[0-9a-f]{64}$")) and (.enabled | type == "boolean") and
        (.recovery | type == "string" and test("^/opt/kosmozoo/\\.stage\\.[a-zA-Z0-9]+$"))' "$fact" > /dev/null || return 65
      attempt=$(jq -er '.release' "$fact") || return $?
      prior=$(jq -er '.enabled | tostring' "$fact") || return $?
      had_fact=1
    fi
    enabled=$(systemctl is-enabled kosmozoo) || [[ "$enabled" == disabled ]] || return 65
    [[ "$enabled" == enabled || "$enabled" == disabled ]] || return 65
    [[ -n "$prior" ]] || { if [[ "$enabled" == enabled ]]; then prior=true; else prior=false; fi; }
    property=$(kz_property TimeoutStopUSec) || return $?
    stop_us=$(jq -er '.data | select(type == "number" and . >= 30000000 and . <= 900000000)' <<< "$property") || return 65
    stop_seconds=$((stop_us / 1000000 + 5))
    property=$(kz_property SendSIGKILL) || return $?
    [[ "$(jq -er '.data | tostring' <<< "$property")" == false ]] || {
      msg_error 'Effective stop overrides must allow >=30s graceful drain and SendSIGKILL=no'
      return 65
    }
    environment_files=$(kz_property EnvironmentFiles) || return $?
    jq -e '.type == "a(sb)" and (.data | type == "array" and all(.[]; type == "array" and length == 2 and (.[0] | type == "string") and (.[1] | type == "boolean")))' <<< "$environment_files" > /dev/null || return 65
    stage=$(mktemp -d /opt/kosmozoo/.stage.XXXXXXXX) || return $?
    trap kz_recover EXIT
    chmod 0700 "$stage" || return $?
    mkdir -m 0700 "$stage/home" "$stage/tmp" || return $?
    if [[ "$had_fact" == 1 ]]; then cp -- "$fact" "$stage/prior-attempt.json" || return $?; fi
    current=$(kz_version "$code") || return $?
    floor=$(kz_normalize "$current") || return $?
    if [[ -f "$marker" && ! -L "$marker" ]]; then
      marked=$(cat "$marker") || return $?
      marked=$(kz_normalize "$marked") || marked=''
    fi
    if [[ -n "$attempt" ]]; then attempt=$(kz_normalize "$attempt") || return $?; fi
    floor=$(printf '%s\n' "$floor" "${marked:-$floor}" "${attempt:-$floor}" | sort -V | tail -n 1) || return $?
    [[ -z "$attempt" && "$marked" == "$(kz_normalize "$current")" ]] || UPDATE_FORCE=1
    # The checker distinguishes no-op (1) from selection/transport errors.
    CHECK_UPDATE_RELEASE=''
    check_for_gh_release kosmozoo alexindigo/kosmozoo "$requested" || rc=$?
    if [[ "$rc" == 1 ]]; then
      rm -r -- "$stage" || return $?
      msg_ok 'Kosmozoo native release is current'
      return 0
    fi
    [[ "$rc" == 0 ]] || return "$rc"
    tag=$CHECK_UPDATE_RELEASE version=${CHECK_UPDATE_RELEASE#v}
    actual=$(kz_normalize "$version") || return $?
    [[ "$(printf '%s\n' "$floor" "$actual" | sort -V | tail -n 1)" == "$actual" ]] || {
      msg_error "Refusing downgrade below possibly state-opening version $floor"
      return 65
    }
    _gh_release_json alexindigo/kosmozoo "$tag" '' "$stage/selected.json" || return $?
    kz_metadata() {
      jq -cer --arg tag "$tag" '
        select(.id | type == "number" and . > 0) |
        select(.tag_name == $tag and .draft == false and .prerelease == false) |
        select(.published_at | type == "string" and length > 0) |
        [.id, .tag_name, ([.assets[] | select(.name == "kosmozoo-linux-x86_64")] |
          select(length == 1) | .[0] | select(.id | type == "number" and . > 0) |
          select(.digest | type == "string" and test("^sha256:[0-9a-f]{64}$")) |
          select(.browser_download_url == ("https://github.com/alexindigo/kosmozoo/releases/download/" + $tag + "/kosmozoo-linux-x86_64")) |
          {id, name, digest, size, browser_download_url}),
          ([.assets[] | select(.name == "SHA256SUMS")] | select(length == 1) | .[0] |
          select(.id | type == "number" and . > 0) |
          select(.browser_download_url == ("https://github.com/alexindigo/kosmozoo/releases/download/" + $tag + "/SHA256SUMS")) |
          {id,name,browser_download_url})] | select(length == 4)' "$1"
    }
    association=$(kz_metadata "$stage/selected.json") || return 65
    digest=$(jq -er '.[2].digest | ltrimstr("sha256:")' <<< "$association") || return $?
    HOME="$stage/home" fetch_and_deploy_gh_release kosmozoo alexindigo/kosmozoo singlefile "$tag" "$stage" kosmozoo-linux-x86_64 '' "$stage/deployed.json" || return $?
    actual=$(kz_metadata "$stage/deployed.json") || return 65
    [[ "$actual" == "$association" ]] || return 65
    curl_download "$stage/SHA256SUMS" "$(jq -er '.[3].browser_download_url' <<< "$association")" || return $?
    LC_ALL=C tr -d '\000' < "$stage/SHA256SUMS" > "$stage/checksum-text" || return $?
    cmp -s "$stage/SHA256SUMS" "$stage/checksum-text" || return 65
    local line checksum_count=0 checksum_hash='' checksum_grammar='^([0-9a-f]{64}) [ *]([^[:cntrl:]]+)$'
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ "$line" =~ $checksum_grammar ]] || return 65
      if [[ "${BASH_REMATCH[2]}" == kosmozoo-linux-x86_64 ]]; then
        checksum_count=$((checksum_count + 1)) checksum_hash=${BASH_REMATCH[1]}
      fi
    done < "$stage/SHA256SUMS"
    [[ "$checksum_count" == 1 && "$checksum_hash" == "$digest" ]] || return 65
    printf '%s  %s\n' "$digest" "$stage/kosmozoo" | sha256sum --check --strict || return 65
    [[ -f "$stage/kosmozoo" && ! -L "$stage/kosmozoo" && "$(od -An -tx1 -N4 "$stage/kosmozoo" | tr -d ' \n')" == 7f454c46 ]] || return 65
    chmod 0755 "$stage/kosmozoo" || return $?
    actual=$(kz_version "$stage/kosmozoo") || return $?
    [[ "$actual" == "$version" ]] || return 65

    # Ask the real systemd EnvironmentFile parser, never shell-source/eval an
    # administrator's file. Copy environment properties into a bounded transient
    # env-only unit; it neither starts Kosmozoo nor opens its state.
    local -a probe=(systemd-run --quiet --wait --pipe --collect --service-type=exec "--unit=kosmozoo-env-$$-$RANDOM" "--property=User=$kz_uid" "--property=Group=$kz_gid" "--property=SupplementaryGroups=${kz_groups//,/ }")
    for property in Environment PassEnvironment UnsetEnvironment; do
      data=$(systemctl show kosmozoo -p "$property" --value) || return $?
      probe+=("--property=$property=$data")
    done
    data=$environment_files
    jq -j '.data[] | (if .[1] then "-" else "" end) + .[0] + "\u0000"' <<< "$data" > "$stage/env-files" || return $?
    while IFS= read -r -d '' item; do probe+=("--property=EnvironmentFile=$item"); done < "$stage/env-files"
    timeout 15 "${probe[@]}" /usr/bin/env -0 > "$stage/next-env" || return $?
    while IFS= read -r -d '' item; do
      case "${item%%=*}" in HOME | TMPDIR | TMP | TEMP | XDG_STATE_HOME | KOZMOZOO_STATE | KOZMOZOO_CACHE | KOZMOZOO_PLUGINS | KOZMOZOO_HOSTS | KOZMOZOO_BIND | KOZMOZOO_PORT) next[${item%%=*}]=${item#*=} ;; esac
    done < "$stage/next-env"
    home=${next[HOME]-$kz_account_home}
    bind=${next[KOZMOZOO_BIND]-0.0.0.0} port=${next[KOZMOZOO_PORT]-2084}
    if [[ -n "${next[KOZMOZOO_STATE]-}" ]]; then
      state=${next[KOZMOZOO_STATE]}
    elif [[ -v 'next[XDG_STATE_HOME]' ]]; then
      state=${next[XDG_STATE_HOME]:+${next[XDG_STATE_HOME]}/}kosmozoo
    else
      state=${home:+$home/}.local/state/kosmozoo
    fi
    home=${next[HOME]-$kz_account_home}
    cache=${next[KOZMOZOO_CACHE]-${home:+$home/}.local/share/kosmozoo/cache}
    local cwd path other
    cwd=$(systemctl show kosmozoo -p WorkingDirectory --value) || return $?
    cwd=${cwd:-/}
    [[ "$cwd" == /* ]] || return 65
    [[ "$state" == /* ]] || state="$cwd/$state"
    [[ "$cache" == /* ]] || cache="$cwd/$cache"
    state=$(realpath -m -- "$state") || return $?
    cache=$(realpath -m -- "$cache") || return $?
    local -a paths=("$state" "$cache" /opt/kosmozoo)
    for item in TMPDIR KOZMOZOO_PLUGINS; do
      if [[ -n "${next[$item]-}" ]]; then
        path=${next[$item]}
        [[ "$path" == /* ]] || path="$cwd/$path"
        path=$(realpath -m -- "$path") || return $?
        paths+=("$path")
      fi
    done
    local i j
    for ((i = 0; i < ${#paths[@]}; i++)); do
      [[ "${paths[i]}" != / ]] || return 65
      for ((j = i + 1; j < ${#paths[@]}; j++)); do
        path=${paths[i]} other=${paths[j]}
        [[ "$path/" != "$other/"* && "$other/" != "$path/"* ]] || {
          msg_error 'Effective code/state/cache/temp/plugin paths overlap'
          return 65
        }
      done
    done
    [[ "$port" =~ ^[0-9]+$ && "$bind" != *[[:space:]/\\\?\#\[\]]* && -n "$bind" ]] || return 65
    port=${port#"${port%%[!0]*}"} port=${port:-0}
    [[ ${#port} -le 5 ]] || return 65
    ((10#$port >= 1 && 10#$port <= 65535)) || return 65
    port=$((10#$port))
    # Validate actual runtime credentials before drain/publication. Existing paths
    # and stable lock metadata are refused, never repaired or removed.
    local runtime_tmp=${next[TMPDIR]-} plugins=${next[KOZMOZOO_PLUGINS]-} projection
    [[ "$home" == /* && "$runtime_tmp" == /* ]] || {
      msg_error 'Set absolute HOME and writable disk-backed TMPDIR in the effective unit environment' >&2
      return 65
    }
    for path in "$home" "$state" "$cache" "$runtime_tmp"; do kz_access "$path" write || return 65; done
    [[ -z "$plugins" ]] || kz_access "$plugins" read || return 65
    local seed_address
    local -a seed_pairs=()
    IFS=, read -r -a seed_pairs <<< "${next[KOZMOZOO_HOSTS]-}"
    for item in "${seed_pairs[@]}"; do
      seed_address=${item#*=}
      seed_address=${seed_address#"${seed_address%%[! ]*}"} seed_address=${seed_address%"${seed_address##*[! ]}"}
      if [[ "$seed_address" == folder:/* ]]; then
        kz_access "${seed_address#folder:}" read || {
          msg_error 'Folder seed must be accessible by the effective runtime account before restart' >&2
          return 65
        }
      fi
    done
    for item in engine.lock engine-instance.json; do
      path=$state/$item
      if [[ -e "$path" || -L "$path" ]]; then
        [[ -f "$path" && ! -L "$path" && "$(stat -c '%u:%a' "$path")" == "$kz_uid:600" ]] || {
          msg_error "Runtime-private file $path must be owned by UID $kz_uid with mode0600; preserve and resolve the existing identity, never delete the stable lock" >&2
          return 65
        }
      fi
    done
    case "$(findmnt -rn -T "$state" -o FSTYPE)" in ext2 | ext3 | ext4 | xfs | btrfs | zfs | f2fs | bcachefs) : ;; *)
      msg_error 'State needs a real local filesystem for SQLite WAL/locking (not NFS/SMB)' >&2
      return 65
      ;;
    esac
    case "$(findmnt -rn -T "$runtime_tmp" -o FSTYPE)" in '' | tmpfs | ramfs) return 65 ;; esac
    [[ ",$(findmnt -rn -T "$runtime_tmp" -o OPTIONS)," != *,noexec,* ]] || return 65
    projection=$("${kz_credentials[@]}" mktemp -d "$runtime_tmp/kosmozoo-probe.XXXXXXXX") || return $?
    if install -o "$kz_uid" -g "$kz_gid" -m 0700 "$stage/kosmozoo" "$projection/kosmozoo" &&
      timeout 15 "${kz_credentials[@]}" env -i PATH=/usr/bin:/bin HOME="$home" TMPDIR="$runtime_tmp" "$projection/kosmozoo" --version > "$stage/runtime-version.txt"; then rc=0; else rc=$?; fi
    rm -r -- "$projection" || return $?
    [[ "$rc" == 0 ]] || return "$rc"
    [[ "$(cat "$stage/runtime-version.txt")" == "$(timeout 15 env -i PATH=/usr/bin:/bin HOME="$stage/home" TMPDIR="$stage/tmp" "$stage/kosmozoo" --version)" ]] || return 65
    [[ "$(kz_identity_inputs)" == "$kz_unit_identity" ]] || {
      msg_error 'Effective unit identity changed during preflight; retry without changing the unit' >&2
      return 65
    }
    property=$(systemctl show kosmozoo -p ActiveState --value) || return $?
    if [[ "$property" == active ]]; then running=1; else kz_empty || return 65; fi
    cp -- "$code" "$stage/previous" || return $?
    if [[ -f "$marker" ]]; then cp -- "$marker" "$stage/marker" || return $?; fi
    if [[ "$running" == 1 ]]; then
      stop_attempted=1
      kz_stop || return $?
    fi
    kz_empty || return 1
    jq -n --arg release "$version" --arg digest "$digest" --argjson enabled "$prior" --arg recovery "$stage" \
      '{version:1, release:$release, digest:$digest, enabled:$enabled, recovery:$recovery}' > "$stage/attempt.json" || return $?
    chmod 0600 "$stage/attempt.json" || return $?
    fact_written=1
    mv -T "$stage/attempt.json" "$fact" || return $?
    publication_attempted=1
    mv -T "$stage/kosmozoo" "$code" || return $?
    started=1
    local deadline=$((SECONDS + 90)) ready=0 destination=$bind
    timeout --signal=TERM --kill-after=5 90 systemctl start kosmozoo || return $?
    case "$bind" in 0.0.0.0) destination=127.0.0.1 ;; ::) destination='[::1]' ;; *:*) destination="[$bind]" ;; esac
    while ((SECONDS < deadline)); do
      pid=$(systemctl show kosmozoo -p MainPID --value) || return $?
      if [[ "$pid" =~ ^[1-9][0-9]*$ && "$(readlink "/proc/$pid/exe")" == "$code" ]] && kz_process_identity "$pid"; then
        process=()
        while IFS= read -r -d '' item; do
          case "${item%%=*}" in HOME | TMPDIR | TMP | TEMP | XDG_STATE_HOME | KOZMOZOO_STATE | KOZMOZOO_CACHE | KOZMOZOO_PLUGINS | KOZMOZOO_HOSTS | KOZMOZOO_BIND | KOZMOZOO_PORT) process[${item%%=*}]=${item#*=} ;; esac
        done < "/proc/$pid/environ"
        for item in HOME TMPDIR TMP TEMP XDG_STATE_HOME KOZMOZOO_STATE KOZMOZOO_CACHE KOZMOZOO_PLUGINS KOZMOZOO_HOSTS KOZMOZOO_BIND KOZMOZOO_PORT; do
          if [[ "${process[$item]+present}" != "${next[$item]+present}" || "${process[$item]-}" != "${next[$item]-}" ]]; then
            msg_error 'Started process environment differs from parsed next-start configuration'
            return 65
          fi
        done
        if curl --noproxy '*' --fail --silent --max-time 2 "http://$destination:$port/api/runtime" > "$stage/runtime.json" &&
          [[ -f "$state/engine-instance.json" && ! -L "$state/engine-instance.json" && "$(stat -c '%u:%a' "$state/engine-instance.json")" == "$kz_uid:600" ]] &&
          jq -e --arg v "$version" --arg bind "$bind" --argjson port "$port" --argjson pid "$pid" \
            --slurpfile private "$state/engine-instance.json" '
            .protocol == "kosmozoo-runtime" and .version == 1 and .status == "ready" and .mode == "serve" and
            .configuredBind == $bind and .binding.port == $port and .app.version == $v and
            (.instance | test("^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")) and
            .instance == $private[0].instance and .sourceVersion == $private[0].sourceVersion and
            .binding == $private[0].binding and $private[0].ownerPid == $pid' "$stage/runtime.json" > /dev/null &&
          ss -H -lntp "sport = :$port" | grep -Fq "pid=$pid,"; then
          ready=1
          break
        fi
      fi
      systemctl is-active --quiet kosmozoo || return 1
      sleep 1
    done
    [[ "$ready" == 1 ]] || return 1
    printf '%s\n' "$version" > /root/.kosmozoo.new || return $?
    mv -T /root/.kosmozoo.new "$marker" || return $?
    if [[ "$prior" == true ]]; then
      systemctl enable kosmozoo || return $?
      [[ "$(systemctl is-enabled kosmozoo)" == enabled ]] || return 1
    else
      kz_disabled || return $?
    fi
    [[ "$(cat "$marker")" == "$version" ]] || return 1
    committed=1
    rm -- "$fact" || return $?
    rm -r -- "$stage" || return $?
    msg_ok "Activated native Kosmozoo $version; state/cache/operator configuration preserved"
  )
}

# framework bootstrap
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc") --script-id "kosmozoo" -- "$@"
