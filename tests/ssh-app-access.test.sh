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
    printf 'LISTEN 0 128 *:22 *:* users:(("sshd",pid=%s,fd=3)%s) ino:%s sk:1\n' "$pid" "$owner" "$inode"
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
    reload-ok | socket-ok)
      [[ $rc == 0 && -e "$work/password-called" ]] &&
        [[ $(cat "$work/events") == $'validate\n'"$(if [[ $scenario == socket-ok ]]; then echo restart; else echo reload; fi) ssh.service" ]]
      ;;
    reload-error | socket-error)
      [[ $rc == 47 && -e "$work/password-called" ]] && grep -Fq 'SSH policy was written (password changed)' "$work/log"
      ;;
    reload-ack-only | socket-ack-only)
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
fi
exit "$failed"
