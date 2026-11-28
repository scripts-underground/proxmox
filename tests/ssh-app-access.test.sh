#!/usr/bin/env bash
set -euo pipefail
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
umask 077

extract_build() {
  sed -n "/^$1() {/,/^}/p" "$ROOT/misc/build.func"
}

# Cold-load the shipped closure, not a second list of its dependencies.
# shellcheck source=/dev/null
source "$ROOT/misc/ssh-access.func"
ssh_access_command_contents rea > "$work/configure-ssh-access"
bash -n "$work/configure-ssh-access"
if bash "$work/configure-ssh-access" root > "$work/log" 2>&1; then
  echo 'FAIL command admitted an unintended account' >&2
  exit 1
fi

ssh-keygen -q -t ed25519 -N '' -f "$work/client"
public_key=$(cat "$work/client.pub")
ssh -V > /dev/null 2>&1

if ssh_access_validate_account root; then
  echo 'FAIL root is not an application account' >&2
  exit 1
fi
if ssh_access_validate_account 'rea,*'; then
  echo 'FAIL a Match pattern was accepted as an application account' >&2
  exit 1
fi

# Operators can select only credentials they actually supplied. Validation is
# also required when callers run under if/|| (where errexit is unavailable).
if ssh_access_apply rea both < /dev/null > "$work/log" 2>&1; then
  echo 'FAIL missing credential stream admitted conditionally' >&2
  exit 1
fi
if bash -euo pipefail -c 'source "$1"; ssh_access_apply rea key </dev/null; echo "unexpected continuation"' \
  _ "$ROOT/misc/ssh-access.func" > "$work/log" 2>&1; then
  echo 'FAIL missing credential stream admitted under strict mode' >&2
  exit 1
fi

[[ -n "$public_key" ]]
echo 'PASS checked command closure, account and credential admission'

failed=0
expect() {
  local label=$1
  shift
  if "$@"; then
    printf 'PASS %s\n' "$label"
  else
    printf 'FAIL %s\n' "$label" >&2
    failed=1
  fi
}
refuses() {
  local rc=0
  "$@" > "$work/log" 2>&1 || rc=$?
  [[ $rc == 65 ]]
}

key_deduplication() (
  mkdir -p "$work/key-home/.ssh" || return $?
  ssh-keygen -q -t ed25519 -N '' -f "$work/other-client" || return $?
  local auth="$work/key-home/.ssh/authorized_keys" fp type blob
  read -r _ fp _ <<< "$(ssh-keygen -lf "$work/client.pub")"
  read -r type blob _ < "$work/other-client.pub"
  printf '%s %s unrelated %s comment\n' "$type" "$blob" "$fp" > "$auth"
  _ssh_access_append_keys "$work/key-home" <<< "$public_key" || return $?
  grep -Fxq "$public_key" "$auth" || return 1
  printf 'no-port-forwarding %s\n' "$public_key" > "$auth"
  cp "$auth" "$work/restricted"
  _ssh_access_append_keys "$work/key-home" <<< "$public_key" || return $?
  cmp -s "$auth" "$work/restricted"
)
expect 'key fingerprint in a comment is not a duplicate; option-prefixed key is' key_deduplication

candidate() { _ssh_access_candidate "$1" rea no yes password; }
printf '%s\n' '# operator prefix' 'UsePAM yes' > "$work/prefix"
printf '%s\n' '# scripts-underground ssh-access begin rea' 'Match User rea' \
  '    PubkeyAuthentication yes' '    PasswordAuthentication no' \
  '    KbdInteractiveAuthentication no' '    AuthenticationMethods publickey' \
  '# scripts-underground ssh-access end rea' > "$work/key-policy"
printf '%s\n' '# operator comment' 'mAtCh User root' > "$work/suffix"
printf '\tPasswordAuthentication no' >> "$work/suffix"
cat "$work/prefix" "$work/key-policy" "$work/suffix" > "$work/input"
sed -e 's/PubkeyAuthentication yes/PubkeyAuthentication no/' \
  -e 's/PasswordAuthentication no/PasswordAuthentication yes/' \
  -e 's/AuthenticationMethods publickey/AuthenticationMethods password/' "$work/key-policy" > "$work/password-policy"
cat "$work/prefix" "$work/password-policy" "$work/suffix" > "$work/expected"
candidate "$work/input" > "$work/output"
expect 'managed block stays in place; unrelated bytes and final newline state preserved' cmp -s "$work/expected" "$work/output"

sed '/AuthenticationMethods/a\    X11Forwarding no' "$work/input" > "$work/edited"
expect 'foreign directive inside managed markers refused' refuses candidate "$work/edited"
cat "$work/prefix" "$work/key-policy" > "$work/continuation"
printf '%s\n' '# operator comment' '    X11Forwarding no' >> "$work/continuation"
expect 'foreign continuation without a new Match refused' refuses candidate "$work/continuation"
cat "$work/prefix" "$work/key-policy" "$work/key-policy" > "$work/duplicate"
expect 'duplicate owned block refused' refuses candidate "$work/duplicate"

review2_preflight() (
  local scenario=$1 rc=0 live="$work/review2-live" stage="$work/review2/candidate" home="$work/review2-home"
  # shellcheck disable=SC2034 # Passed by name to the stage owner.
  local selected_keys="$public_key" fixture='test-only'
  mkdir -p "${stage%/*}" "$home/.ssh"
  printf '%s\n' '# existing operator key' > "$home/.ssh/authorized_keys"
  chmod 0600 "$home/.ssh/authorized_keys"
  chmod 0700 "$home/.ssh"
  cp "$work/prefix" "$live"
  case "$scenario" in
    peer) printf '%s\n' 'Match User rea Address 192.0.2.0/24' '  PasswordAuthentication yes' '  AuthenticationMethods password' >> "$live" ;;
    strict) chmod 0775 "$home/.ssh" ;;
    root) printf '%s\n' 'Match User root Address 192.0.2.0/24' '  PasswordAuthentication yes' >> "$live" ;;
    matching) printf '%s\n' 'Match Address 192.0.2.0/24' '  PasswordAuthentication no' >> "$live" ;;
  esac
  cp "$live" "$work/review2-before"
  local mode=key
  [[ $scenario != strict ]] || mode=both
  sshd() {
    if [[ $1 == -T ]]; then
      if [[ $* == *user=root,* ]]; then return 0; fi
      if [[ $3 == /dev/stdin ]]; then
        if grep -Fiq 'Match User root'; then printf '%s\n' 'permittty yes'; fi
        return 0
      fi
      printf '%s\n' 'pubkeyauthentication yes' 'kbdinteractiveauthentication no' \
        'strictmodes yes' 'authorizedkeysfile .ssh/authorized_keys .ssh/authorized_keys2'
      if [[ $mode == key ]]; then
        printf '%s\n' 'passwordauthentication no' 'authenticationmethods publickey'
      else
        printf '%s\n' 'passwordauthentication yes' 'authenticationmethods publickey password'
      fi
    fi
  }
  id() { printf '%s\n' "$EUID"; }
  _ssh_access_activation_state() { :; }
  _ssh_access_activate() { :; }
  runuser() { : > "$work/review2-writer"; }
  chpasswd() {
    cat > /dev/null
    : > "$work/review2-password"
  }
  rm -f "$work/review2-writer" "$work/review2-password"
  _ssh_access_apply_candidate rea "$mode" "$live" "$stage" "$home" selected_keys fixture > "$work/log" 2>&1 || rc=$?
  case "$scenario" in
    peer | strict)
      [[ $rc == 65 && ! -e "$work/review2-writer" && ! -e "$work/review2-password" ]] && cmp -s "$work/review2-before" "$live"
      ;;
    root | matching) [[ $rc == 0 && -e "$work/review2-writer" && ! -e "$work/review2-password" ]] ;;
  esac
)
expect 'earlier peer-specific mode conflict refused before effects' review2_preflight peer
expect 'strict mode refuses group-writable .ssh before key or password effects' review2_preflight strict
expect 'earlier root-only methods do not block app access' review2_preflight root
expect 'compatible peer-specific methods do not block app access' review2_preflight matching

# Test against real files; model only daemon, password and service calls.
publication() (
  local scenario=$1 caller=${2:-conditional} rc=0 live="$work/live" stage="$work/stage/candidate"
  # shellcheck disable=SC2034 # Passed by name to the stage owner.
  local selected_keys='' fixture='test-only' before after
  local daemon_title='sshd: /usr/sbin/sshd -D [listener] 0 of 10-100 startups'
  mkdir -p "$work/stage"
  cp "$work/prefix" "$live"
  chmod 0640 "$live"
  touch -d '2001-02-03 04:05:06.123456789 UTC' "$live"
  before=$(stat -c '%a:%u:%g:%y' "$live")
  sshd() {
    if [[ $1 == -t ]]; then
      printf '%s\n' validate >> "$work/events"
      [[ $scenario != invalid ]] || return 42
      if [[ $scenario == replace ]]; then
        cp -p -- "$live" "$live.replacement" && mv -fT -- "$live.replacement" "$live"
      elif [[ $scenario == chmod ]]; then
        chmod 0600 "$live"
      fi
    elif [[ $5 != user=root,* ]]; then
      printf '%s\n' 'pubkeyauthentication no' 'passwordauthentication yes' \
        'kbdinteractiveauthentication no' 'authenticationmethods password'
    fi
    return 0
  }
  type() {
    if [[ $* == '-P sshd' ]]; then printf '%s\n' /bin/bash; else builtin type "$@"; fi
  }
  local pid
  case $scenario in
    daemon-alternate) daemon_title=${daemon_title/-D /-D -f \/etc\/ssh\/alternate } ;;
    daemon-override) daemon_title=${daemon_title/-D /-D -o PasswordAuthentication=no } ;;
  esac
  for pid in 100 200; do
    mkdir -p "$work/proc/$pid/root/etc/ssh"
    ln -sf /bin/bash "$work/proc/$pid/exe"
    ln -sf "$live" "$work/proc/$pid/root/etc/ssh/sshd_config"
    printf '%s\0' "$daemon_title" > "$work/proc/$pid/cmdline"
  done
  # Model only system-owned proc paths with native record bytes.
  # shellcheck source=/dev/null
  source <(sed 's|/proc/\$_pid/|$work/proc/$_pid/|g' "$ROOT/misc/ssh-access.func")
  systemctl() {
    local pid=100 invocation=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa trigger='' killmode=process
    [[ $scenario != socket-* ]] || trigger=ssh.socket
    [[ $scenario != socket-unsafe ]] || killmode=control-group
    if [[ -e $work/activated && $scenario == socket-ok ]]; then
      pid=200 invocation=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
    fi
    case $1 in
      is-active) return 0 ;;
      show)
        if [[ $* == *ssh.socket* ]]; then
          printf '%s\n' Id=ssh.socket LoadState=loaded ActiveState=active SubState=running Triggers=ssh.service Accept=no Result=success
        else
          printf '%s\n' Id=ssh.service LoadState=loaded ActiveState=active SubState=running Result=success \
            "MainPID=$pid" "InvocationID=$invocation" "TriggeredBy=$trigger" "KillMode=$killmode" Type=notify CanReload=yes ConsistsOf= PropagatesStopTo= RootDirectory= RootImage= \
            'ExecStart={ path=/usr/sbin/sshd ; argv[]=/usr/sbin/sshd -D ; ignore_errors=no ; start_time=[fixture] ; }'
        fi
        ;;
      reload | restart)
        printf '%s\n' "$1 $2" >> "$work/events"
        grep -Fqx 'validate' "$work/events" || return 44
        grep -Fqx '    AuthenticationMethods password' "$live" || return 45
        [[ $scenario != *-error ]] || return 47
        : > "$work/activated"
        ;;
      *) return 46 ;;
    esac
  }
  ss() {
    local pid=100 inode=91 owner=''
    if [[ $scenario == socket-* ]]; then
      owner=',("systemd",pid=1,fd=9)'
      if [[ -e $work/activated && $scenario == socket-ok ]]; then pid=200; fi
    elif [[ -e $work/activated && $scenario != reload-ack-only ]]; then
      inode=92
    fi
    if [[ $* != *-6* ]]; then
      printf 'LISTEN 0 128 0.0.0.0:22 0.0.0.0:* users:(("sshd",pid=%s,fd=3)%s) ino:%s sk:1\n' "$pid" "$owner" "$inode"
    fi
    case $scenario in
      reload-dual | reload-lost-v6 | reload-reused-v6)
        if [[ $* != *-4* && (! -e $work/activated || $scenario != reload-lost-v6) ]]; then
          inode=93
          if [[ -e $work/activated && $scenario == reload-dual ]]; then inode=94; fi
          printf 'LISTEN 0 128 [::]:22 [::]:* users:(("sshd",pid=%s,fd=4)) ino:%s sk:2 v6only:1\n' "$pid" "$inode"
        fi
        ;;
    esac
    return 0
  }
  sleep() { :; }
  chpasswd() {
    cat > /dev/null
    : > "$work/password-called"
    [[ $scenario != password-error ]] || return 58
    if [[ $scenario == after-password ]]; then printf '# concurrent\n' >> "$live"; fi
  }
  rm -f "$work/password-called" "$work/events" "$work/activated"
  if [[ $caller == ordinary ]]; then
    _ssh_access_apply_candidate rea password "$live" "$stage" "$work" selected_keys fixture > "$work/log" 2>&1
    printf 'unexpected continuation\n'
    return 0
  fi
  _ssh_access_apply_candidate rea password "$live" "$stage" "$work" selected_keys fixture > "$work/log" 2>&1 || rc=$?
  case $scenario in
    replace | chmod) [[ $rc == 75 && ! -e "$work/password-called" ]] ;;
    after-password) [[ $rc == 75 && -e "$work/password-called" ]] && grep -Fq 'password changed' "$work/log" && grep -Fqx '# concurrent' "$live" ;;
    metadata)
      after=$(stat -c '%a:%u:%g:%y' "$live")
      [[ $rc == 0 && "$before" == "$after" && -e "$work/password-called" ]]
      ;;
    invalid) [[ $rc == 42 && ! -e "$work/password-called" && $(cat "$work/events") == validate ]] ;;
    password-error)
      [[ $rc == 58 && -e "$work/password-called" && $(cat "$work/events") == validate ]] &&
        cmp -s "$work/prefix" "$live" && grep -Fq 'password outcome is unconfirmed and SSH policy was not applied' "$work/log"
      ;;
    reload-ok | reload-dual | socket-ok)
      [[ $rc == 0 && -e "$work/password-called" ]] &&
        [[ $(cat "$work/events") == $'validate\n'"$(if [[ $scenario == socket-ok ]]; then echo restart; else echo reload; fi) ssh.service" ]]
      ;;
    reload-error | socket-error)
      [[ $rc == 47 && -e "$work/password-called" ]] && grep -Fq 'SSH policy was written (password changed)' "$work/log"
      ;;
    reload-ack-only | reload-lost-v6 | reload-reused-v6 | socket-ack-only)
      [[ $rc == 69 && -e "$work/password-called" ]] && grep -Fq 'effective access is unconfirmed' "$work/log"
      ;;
    socket-unsafe | daemon-alternate | daemon-override)
      [[ $rc == 69 && ! -e "$work/password-called" && $(cat "$work/events") == validate ]] && cmp -s "$work/prefix" "$live"
      ;;
  esac
)
if [[ ${1-} == --activation-ordinary ]]; then
  publication "$2" ordinary
  exit 0
fi
ordinary_activation_fails() {
  local rc=0
  bash -euo pipefail "${BASH_SOURCE[0]}" --activation-ordinary "$1" > "$work/ordinary" 2>&1 || rc=$?
  [[ $rc == "$2" ]] && ! grep -Fq 'unexpected continuation' "$work/ordinary"
}
expect 'same-byte inode replacement refused before credential effects' publication replace
expect 'metadata change refused before credential effects' publication chmod
expect 'concurrent change after password is preserved and reported as partial' publication after-password
expect 'publication preserves file mode ownership and nanosecond mtime' publication metadata
expect 'invalid syntax stops before credentials and activation' publication invalid
expect 'ordinary service reload observes a replacement listener' publication reload-ok
expect 'ordinary reload accepts replacement listeners on both IPv4 and IPv6' publication reload-dual
expect 'ordinary reload refuses success when IPv6 is lost' publication reload-lost-v6
expect 'ordinary reload refuses success when the IPv6 inode is reused' publication reload-reused-v6
expect 'socket-backed service restarts only ssh.service and confirms listener ownership' publication socket-ok
expect 'unsafe socket-backed service refuses before effects' publication socket-unsafe
expect 'alternate daemon config refuses before password or policy effects' publication daemon-alternate
expect 'daemon command-line overrides refuse before password or policy effects' publication daemon-override
expect 'strict ordinary caller refuses alternate daemon config' ordinary_activation_fails daemon-alternate 69
expect 'conditional caller retains reload failure and partial diagnostic' publication reload-error
expect 'conditional caller retains socket restart failure and partial diagnostic' publication socket-error
expect 'conditional caller rejects reload acknowledgment without a new listener' publication reload-ack-only
expect 'conditional caller rejects restart acknowledgment without a new service invocation' publication socket-ack-only
expect 'strict ordinary caller rejects reload acknowledgment without a new listener' ordinary_activation_fails reload-ack-only 69
expect 'strict ordinary caller retains restart failure' ordinary_activation_fails socket-error 47
expect 'conditional password operation failure keeps exact status and live policy' publication password-error
expect 'strict ordinary caller retains password operation failure' ordinary_activation_fails password-error 58

# Relocate only system-owned paths, never the implementation or status logic.
sed -e 's|/usr/local/sbin/configure-ssh-access|$work/sbin/configure-ssh-access|' \
  -e 's|/usr/bin/configure-ssh-access|$work/bin/configure-ssh-access|' \
  -e 's|_config=/etc/ssh/sshd_config|_config="$work/sshd_config"|' \
  "$ROOT/misc/ssh-access.func" > "$work/relocated.func"
refresh_failure() (
  source "$work/relocated.func" || return $?
  mkdir -p "$work/bin" || return $?
  ssh_access_install_command rea || return $?
  cp -p "$work/sbin/configure-ssh-access" "$work/previous" || return $?
  mv() { return 59; }
  local rc=0
  ssh_access_install_command rea || rc=$?
  [[ $rc == 59 ]] && cmp -s "$work/previous" "$work/sbin/configure-ssh-access" &&
    [[ $(readlink "$work/bin/configure-ssh-access") == "$work/sbin/configure-ssh-access" &&
    $(find "$work/sbin" -mindepth 1 -maxdepth 1 -printf '%f\n') == configure-ssh-access ]]
)
expect 'failed helper refresh retains old command and alias without leaked stage' refresh_failure

# Synthetic, per-run password; never print it even if a test fails.
cat /proc/sys/kernel/random/uuid > "$work/password-marker"
printf '  fixture:%s \\ tail  \n' "$(cat "$work/password-marker")" > "$work/password"
cancel_then_retry() (
  local phase=cancel mode=prior keys=prior password=prior rc=0
  whiptail() {
    case "$*" in
      *--menu*) printf '%s' password >&2 ;;
      *'CONFIRM SSH ACCOUNT PASSWORD'*)
        [[ $phase == retry ]] || return 255
        # Whiptail sends the response to stderr, without a newline.
        printf '%s' "$(cat "$work/password")" >&2
        ;;
      *--passwordbox*) printf '%s' "$(cat "$work/password")" >&2 ;;
      *) return 70 ;;
    esac
  }
  ssh_access_collect rea '' mode keys password || rc=$?
  [[ $rc == 130 && $mode == prior && $keys == prior && $password == prior ]] || return 1
  phase=retry
  ssh_access_collect rea '' mode keys password || return $?
  [[ $mode == password && -z $keys && $password == "$(cat "$work/password")" ]]
)
expect 'cancel after password entry leaves outputs untouched; re-entry collects anew' cancel_then_retry

selection_provenance() (
  local scenario=$1 mode='' keys='' password='' rc=0 restricted bare384 bare521
  restricted="command=\"echo restricted\",no-port-forwarding $public_key"
  mkdir "$work/$scenario" || return $?
  export TMPDIR="$work/$scenario"
  ssh-keygen -q -t ecdsa -b 384 -N '' -f "$TMPDIR/p384" &&
    ssh-keygen -q -t ecdsa -b 521 -N '' -f "$TMPDIR/p521" || return $?
  bare384=$(cat "$TMPDIR/p384.pub") && bare521=$(cat "$TMPDIR/p521.pub") || return $?
  case $scenario in
    discovery | root-reuse) printf '%s\n' "$restricted" "$bare384" "$bare521" > "$TMPDIR/authorized_keys" ;;
    root-ecdsa) printf 'no-port-forwarding %s\nno-port-forwarding %s\n' "$bare384" "$bare521" > "$TMPDIR/authorized_keys" ;;
    *) : > "$TMPDIR/authorized_keys" ;;
  esac
  ssh_discover_default_files() { printf '%s\0' "$TMPDIR/authorized_keys"; }
  # Append chosen tags to the mock checklist the same way whiptail does.
  whiptail() {
    case $* in
      *'SSH ACCESS METHOD'*) printf key >&2 ;;
      *'SSH PUBLIC KEY'*) printf reuse >&2 ;;
      *'SSH KEY SOURCE'*)
        case $scenario in
          manual-option | manual-bare) printf manual >&2 ;;
          explicit-none) printf none >&2 ;;
          *) printf found >&2 ;;
        esac
        ;;
      *'SELECT HOST KEYS'*)
        while [[ $1 != --checklist ]]; do shift; done
        shift 5
        while (($#)); do
          printf '"%s" ' "$1" >&2
          shift 3
        done
        ;;
      *'SSH Public Key'*)
        if [[ $scenario == manual-option ]]; then printf '%s' "$restricted" >&2; else printf '%s' "$bare521" >&2; fi
        ;;
      *) return 70 ;;
    esac
  }
  case $scenario in
    discovery)
      # The app picker has a private TMPDIR; keep discovery pointed at the fixture.
      local discovery_file="$TMPDIR/authorized_keys"
      ssh_discover_default_files() { printf '%s\0' "$discovery_file"; }
      ssh_access_collect rea '' mode keys password || return $?
      [[ $mode == key && $keys == "$bare384"$'\n'"$bare521" ]]
      ;;
    manual-option)
      ssh_access_collect rea '' mode keys password > "$work/log" 2>&1 || rc=$?
      [[ $rc == 65 && -z $keys ]]
      ;;
    manual-bare)
      ssh_access_collect rea '' mode keys password || return $?
      [[ $mode == key && $keys == "$bare521" ]]
      ;;
    root-reuse | explicit-none | defaults | root-ecdsa)
      local SSH_KEYS_FILE='' SSH_AUTHORIZED_KEY="$public_key"
      # These locals are read or written by the sourced picker via dynamic scope.
      # shellcheck disable=SC2034
      local SSH_REUSABLE_KEYS='' SSH_MAP_FILE='' COUNT=0
      # shellcheck disable=SC2034
      local -a CHOICES=()
      local _lbs_access_account=rea _lbs_access_key_file='' _lbs_access_password_fd=''
      local _lbs_access_mode='' _lbs_access_keys='' _lbs_access_password=''
      # Exercise the interactive branch without allocating a PTY for mock
      # dialogs. The native bootstrap proof supplies the real PTY.
      # shellcheck source=/dev/null
      source <(extract_build _collect_lxc_ssh_access | sed 's/ || ! -t 0 || ! -t 1//') || return $?
      if [[ $scenario != defaults ]]; then ssh_access_pick_keys 'fixture' root || return $?; fi
      case $scenario in
        root-reuse)
          grep -Fxq "$public_key" "$SSH_KEYS_FILE" || return 1
          _collect_lxc_ssh_access || return $?
          [[ $_lbs_access_keys == "$bare384"$'\n'"$bare521" ]]
          ;;
        explicit-none)
          # A stale default would offer the reuse menu and bypass the refused
          # empty selection. Whiptail must never produce a reusable key here.
          _collect_lxc_ssh_access > "$work/log" || rc=$?
          [[ $rc == 65 && -z $_lbs_access_keys ]]
          ;;
        defaults)
          _collect_lxc_ssh_access || return $?
          [[ $_lbs_access_keys == "$public_key" ]]
          ;;
        root-ecdsa)
          grep -Fxq "$bare384" "$SSH_KEYS_FILE" && grep -Fxq "$bare521" "$SSH_KEYS_FILE"
          ;;
      esac
      ;;
  esac
)
expect 'discovery excludes restricted keys and offers ECDSA P-384 and P-521' selection_provenance discovery
expect 'manual app entry rejects authorized_keys options' selection_provenance manual-option
expect 'manual app entry accepts a bare P-521 key' selection_provenance manual-bare
expect 'legacy root selection strips options from P-384 and P-521 keys' selection_provenance root-ecdsa
expect 'app reuse only receives proven bare root selections; root selection is unchanged' selection_provenance root-reuse
expect 'explicit root No keys does not reuse a stale default' selection_provenance explicit-none
expect 'configured bare root default can still be explicitly reused' selection_provenance defaults

saved_defaults() (
  # shellcheck disable=SC2034 # Read by the extracted saved-default producer.
  local APP=Fixture NSAPP=fixture SSH=yes SSH_AUTHORIZED_KEY="$public_key" CONTAINER_STORAGE=fixture
  local _lbs_access_account=rea _lbs_access_key_file='' _lbs_access_password_fd
  local _lbs_access_mode='' _lbs_access_keys='' _lbs_access_password='' output
  # Substitute only the legacy serializer's hardcoded scratch root. Its actual
  # settings selection and writes are unchanged; the fixture does not use /tmp.
  {
    extract_build _collect_lxc_ssh_access
    extract_build _sanitize_value
    extract_build _build_current_app_vars_tmp | sed 's|mktemp /tmp/|mktemp "$work"/|'
  } > "$work/defaults.func" || return $?
  source "$work/defaults.func" || return $?
  exec {_lbs_access_password_fd}< "$work/password" || return $?
  (
    set -ax
    _collect_lxc_ssh_access || exit $?
    set +ax
    [[ $_lbs_access_mode == password && $_lbs_access_password == "$(cat "$work/password")" ]] || exit 1
    env > "$work/child-env" || exit $?
    output=$(_build_current_app_vars_tmp) || exit $?
    [[ $output == "$work/"* && -s $output ]] || exit 1
    grep -Fqx 'var_ssh=yes' "$output" && grep -Fqx "var_ssh_authorized_key=$public_key" "$output" || exit 1
    # grep status 1 is absence; read/scan errors do not count as a pass.
    local rc=0
    grep -Fq -f "$work/password-marker" "$output" "$work/child-env" "$work/defaults-trace" || rc=$?
    [[ $rc == 1 ]]
  ) > "$work/defaults-trace" 2>&1
)
expect 'real saved-default serializer retains root settings and excludes app password' saved_defaults

if ((EUID == 0)); then
  root_framing() (
    source "$work/relocated.func" || return $?
    local rc=0 variant
    local keys="$public_key" password
    password=$(cat "$work/password") || return $?
    getent() {
      : > "$work/lookup"
      printf 'rea:x:1000:1000::%s:/bin/bash\n' "$work"
    }
    _ssh_access_apply_candidate() {
      local got_keys=$6 got_password=$7
      [[ $1 == rea && $2 == both && ${!got_keys} == "$keys" && ${!got_password} == "$password" ]] || return 70
      : > "$work/consumed"
    }
    for variant in truncated trailing third newline; do
      rc=0
      case "$variant" in
        truncated) printf '%s\0%s' "$keys" "$password" ;;
        trailing) printf '%s\0%s\0x' "$keys" "$password" ;;
        third) printf '%s\0%s\0\0' "$keys" "$password" ;;
        newline) printf '%s\0%s\n\0' "$keys" "$password" ;;
      esac > "$work/frame"
      ssh_access_apply rea both < "$work/frame" > "$work/frame-log" 2>&1 || rc=$?
      [[ $rc == 65 && ! -e "$work/lookup" && ! -e "$work/consumed" ]] || return 1
    done
    ssh_access_send keys password ssh_access_apply rea both || return $?
    [[ -e $work/lookup && -e $work/consumed ]]
  )
  expect 'root reader rejects malformed frames before effects and consumes exactly two frames' root_framing

  concurrent_password_setups() (
    source "$work/relocated.func" || return $?
    local second=$1 state="$work/concurrent-$1-$2" rc=0 gate entered winner
    local result=$2
    mkdir -m 0700 "$state" || return $?
    local work=$state
    printf '# original\n' > "$work/sshd_config"
    printf '\0first-test-password\0' > "$work/first"
    printf '\0second-test-password\0' > "$work/second"
    mkfifo "$work/gate" "$work/entered" || return $?
    exec {gate}<> "$work/gate" {entered}<> "$work/entered" || return $?
    getent() { printf '%s:x:1000:1000::%s:/bin/bash\n' "$2" "$work"; }
    _ssh_access_apply_candidate() {
      local password_ref=$7
      printf '%s\n' "$1" >> "$work/transactions"
      if [[ ${!password_ref} == first-test-password ]]; then
        printf 'entered\n' >&"$entered"
        IFS= read -r -t 5 -u "$gate" || return 76
        [[ $result == success ]] || return 42
      fi
      printf '# %s\n' "$1" >> "$3" || return $?
      printf '%s:%s\n' "$1" "${!password_ref}" > "$work/password-effect"
    }
    ssh_access_apply rea password < "$work/first" > "$work/first.log" 2>&1 &
    winner=$!
    IFS= read -r -t 5 -u "$entered" || {
      wait "$winner"
      return 1
    }
    ssh_access_apply "$second" password < "$work/second" > "$work/second.log" 2>&1 || rc=$?
    local before_release=0
    [[ $rc == 75 && $(cat "$work/transactions") == rea && ! -e "$work/password-effect" && $(cat "$work/sshd_config") == '# original' ]] || before_release=1
    printf 'proceed\n' >&"$gate" || return $?
    rc=0
    wait "$winner" || rc=$?
    [[ $before_release == 0 ]] || return 1
    if [[ $result == success ]]; then
      [[ $rc == 0 && $(cat "$work/password-effect") == rea:first-test-password && $(cat "$work/sshd_config") == $'# original\n# rea' ]]
    else
      [[ $rc == 42 && ! -e "$work/password-effect" ]] || return 1
      ssh_access_apply "$second" password < "$work/second" || return $?
      [[ $(cat "$work/password-effect") == "$second:second-test-password" && $(cat "$work/sshd_config") == $'# original\n# '"$second" ]]
    fi
  )
  expect 'simultaneous password setup on the same account refuses before effects' concurrent_password_setups rea success
  expect 'different accounts sharing sshd_config contend and a failed winner releases the lock' concurrent_password_setups another failure
fi
exit "$failed"
