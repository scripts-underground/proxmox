#!/usr/bin/env bash
# Runtime owners with real private files/command consumers; package/network effects modeled.
set -euo pipefail
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/../..")
if [[ "${1:-}" == --child ]]; then
  source "$ROOT/misc/tools.func"
  export STD='' HOME="$CASE_ROOT/home" PATH="$CASE_ROOT/bin:$PATH"
  msg_info() { :; }
  msg_ok() { :; }
  msg_error() { printf '%s\n' "$*" >&2; }
  msg_warn() { :; }
  cache_installed_version() { :; }
  sleep() { :; }
  case "$CASE_KIND" in
    node)
      npm() {
        printf '%s\n' "$*" >> "$CASE_ROOT/calls"
        case "$1" in
          root) printf '%s\n' "$CASE_ROOT/modules" ;;
          install)
            [[ "$FAULT" != install ]] || return 42
            local spec="$3" name="${MODULE_SPEC%@*}" version
            version="${spec##*@}"
            mkdir -p "$CASE_ROOT/modules/$name/bin"
            jq -n --arg name "$name" --arg version "$version" '{name:$name,version:$version,bin:{"real-cli":"bin/run","second-cli":"bin/second"}}' > "$CASE_ROOT/modules/$name/package.json"
            for b in real-cli second-cli; do
              local target=run
              [[ "$b" != second-cli ]] || target=second
              printf '#!/bin/sh\nprintf "consumer-%s\\n"\n' "$version" > "$CASE_ROOT/modules/$name/bin/$target"
              chmod +x "$CASE_ROOT/modules/$name/bin/$target"
              [[ "$FAULT" != missing || "$b" != second-cli ]] || continue
              ln -sf "$CASE_ROOT/modules/$name/bin/$target" "$CASE_ROOT/bin/$b"
            done
            ;;
          *) return 66 ;;
        esac
      }
      if [[ "$FAULT" == repair ]]; then FAULT=missing npm install -g "$MODULE_SPEC"; fi
      _node_setup_module "$MODULE_SPEC"
      _node_setup_module "$MODULE_SPEC"
      real-cli > "$CASE_ROOT/consumer"
      ;;
    ruby)
      ensure_apt_working() { :; }
      apt-cache() { printf 'available build dependency\n'; }
      apt() { :; }
      mkdir -p "$HOME/.rbenv/bin" "$HOME/.rbenv/plugins/ruby-build/share/ruby-build"
      : > "$HOME/.rbenv/plugins/ruby-build/share/ruby-build/3.4.4"
      cat > "$HOME/.rbenv/bin/rbenv" << 'RUBY'
#!/bin/sh
case "$1" in
  global) echo 3.3.0 ;;
  init) echo : ;;
  install)
    printf '%s\n' "$TMPDIR" "$RUBY_BUILD_BUILD_PATH" "$RUBY_BUILD_CACHE_PATH" > "$CASE_ROOT/ruby-context"
    test -n "$RUBY_BUILD_BUILD_PATH" || exit 44
    printf 'owned failed Ruby build evidence\n' > "$RUBY_BUILD_BUILD_PATH/evidence"
    exit 44
    ;;
esac
RUBY
      chmod +x "$HOME/.rbenv/bin/rbenv"
      RUBY_VERSION=3.4.4 RUBY_INSTALL_RAILS=false setup_ruby
      ;;
    rust)
      # Avoid borrowing the VM's Rust installation while retaining native shell utilities.
      command() { case "${*: -1}" in
        rustup) return 1 ;;
        rustc) [[ -x "$HOME/.cargo/bin/rustc" ]] ;;
        *) builtin command "$@" ;;
      esac }
      curl() {
        local n=0 out=''
        [[ ! -f "$CASE_ROOT/count" ]] || n=$(< "$CASE_ROOT/count")
        n=$((n + 1))
        printf '%s\n' "$n" > "$CASE_ROOT/count"
        [[ "$FAULT" != transfer && "$n" -gt 1 ]] || return 18
        while (($#)); do
          if [[ "$1" == -o ]]; then
            out="$2"
            shift
          fi
          shift
        done
        if [[ "$FAULT" == recover && "$n" == 3 ]]; then
          printf '#!/bin/sh\nmkdir -p "$HOME/.cargo/bin"\nprintf '\''#!/bin/sh\\necho rustc 1.85.1\\n'\'' > "$HOME/.cargo/bin/rustc"\nchmod +x "$HOME/.cargo/bin/rustc"\n' > "$out"
        else
          printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/install-args"\nexit 43\n' "$CASE_ROOT" > "$out"
        fi
      }
      RUST_TOOLCHAIN=1.85.1 RUST_PROFILE=minimal setup_rust
      ;;
    php)
      mkdir -p "$CASE_ROOT/apt" "$CASE_ROOT/systemd"
      mount --bind "$CASE_ROOT/apt" /etc/apt
      mount --bind "$CASE_ROOT/systemd" /etc/systemd/system
      get_os_info() { case "$1" in id) echo debian ;; codename) echo trixie ;; esac }
      is_tool_installed() { echo 8.4; }
      prepare_repository_setup() { :; }
      manage_tool_repository() { :; }
      ensure_apt_working() { :; }
      apt-cache() { printf 'Version: 8.4.0\n'; }
      apt() { :; }
      php() { printf 'PHP 8.4.0\n'; }
      systemctl() {
        printf '%s\n' "$*" >> "$CASE_ROOT/calls"
        if [[ "$1" == show ]]; then
          [[ "$FAULT" != query ]] || return 41
          printf '%s\n' "$FAULT"
        elif [[ "$1" == list-unit-files ]]; then
          [[ "$FAULT" != query ]] || return 41
          [[ "$FAULT" == loaded ]] || return 0
          printf 'php8.4-fpm.service enabled\n'
          # The old early-closing grep makes this completed query SIGPIPE.
          python3 -c 'print("unrelated.service enabled\\n" * 10000)'
        fi
      }
      safe_service_restart() { printf '%s\n' "$*" >> "$CASE_ROOT/restarted"; }
      PHP_FPM=YES setup_php
      ;;
    completion)
      uv() {
        printf 'actual completion bytes\n'
        [[ "$FAULT" != yes ]] || return 39
      }
      _uv_publish_completion bash "$CASE_ROOT/completion/new/uv"
      ;;
    stage)
      if [[ "$FAULT" == default ]]; then unset TMPDIR; fi
      if [[ "$FAULT" == explicit-ram ]]; then mount -t tmpfs -o size=1m tmpfs "$TMPDIR"; fi
      if [[ "$FAULT" == no-disk ]]; then
        unset TMPDIR
        mount -t tmpfs -o size=1m tmpfs /var/tmp
        mount -t tmpfs -o size=1m tmpfs /opt
      fi
      stage=$(_tools_stage_dir runtime-proof) || exit $?
      printf '%s\n' "$stage" > "$CASE_ROOT/stage"
      findmnt -rn -T "$stage" -o FSTYPE > "$CASE_ROOT/fstype"
      rmdir -- "$stage"
      ;;
  esac
  exit 0
fi
: "${TMPDIR:?disk-backed TMPDIR required}"
work=$(mktemp -d "$TMPDIR/core-runtime.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT
failures=0
check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s: expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
run_case() {
  local kind="$1" fault="$2" expected="$3" spec="${4:-}"
  c="$work/$kind-$fault-${spec//\//_}"
  mkdir -p "$c"/{home,bin,modules,tmp,completion/new}
  : > "$c/calls"
  if [[ "$kind" == completion ]]; then
    if [[ "$fault" == fresh ]]; then rmdir "$c/completion/new"; else printf 'prior completion\n' > "$c/completion/new/uv"; fi
  fi
  rc=0
  env -i PATH="$PATH" TMPDIR="$c/tmp" CASE_ROOT="$c" CASE_KIND="$kind" FAULT="$fault" MODULE_SPEC="$spec" \
    unshare -m --propagation private -- bash "$0" --child > "$c/output" 2>&1 || rc=$?
  check "$rc" "$expected" "$kind/$fault exact outcome"
  [[ "$rc" == "$expected" ]] || cat "$c/output"
}
for spec in pnpm@9.15.4+sha512.abcdef @scope/tool@2.3.4+sha224.abcdef; do
  run_case node no 0 "$spec"
  version=${spec##*@}
  check "$(cat "$c/consumer" 2> /dev/null || true)" "consumer-${version%%+*}" 'exact numeric package version reaches declared bin consumer'
  check "$(grep -c '^install -g ' "$c/calls" || true)" 1 'hash-bearing installed numeric version is not needlessly reinstalled'
done
run_case node repair 0 pnpm@9.15.4
check "$(grep -c '^install -g pnpm@9.15.4$' "$c/calls" || true)" 2 'missing installed bin recovers through the same pinned package'
run_case node missing 127 pnpm@9.15.4
check "$(grep -c '@latest' "$c/calls" || true)" 0 'missing pinned bin never falls back to latest'
run_case node install 42 pnpm@9.15.4
run_case php loaded 0
check "$(cat "$c/restarted" 2> /dev/null || true)" php8.4-fpm 'positive intended unit reaches restart'
run_case php not-found 0
check "$(test -e "$c/restarted" && echo yes || echo no)" no 'verified absent unit is not restarted'
run_case php query 41
run_case php malformed 65
run_case ruby build 150
ruby_stage=$(head -n1 "$c/ruby-context" 2> /dev/null || true)
check "$(dirname "$ruby_stage")" "$c/tmp" 'Ruby build temporary root respects receiving TMPDIR'
check "$(cat "$ruby_stage/build/evidence" 2> /dev/null || true)" 'owned failed Ruby build evidence' 'Ruby failure retains its exact owned build evidence'
check "$(sed -n '2p' "$c/ruby-context" 2> /dev/null || true)" "$ruby_stage/build" 'Ruby compiler build path is inside the owned stage'
check "$(sed -n '3p' "$c/ruby-context" 2> /dev/null || true)" "$ruby_stage/cache" 'Ruby download cache is inside the owned stage'
run_case rust transfer 18
check "$(cat "$c/count" 2> /dev/null || true)" 3 'bounded rust download retries'
run_case rust installer 43
check "$(cat "$c/count" 2> /dev/null || true)" 3 'bounded checked rust download/install retries'
check "$(grep -c -- '--profile minimal --default-toolchain 1.85.1' "$c/install-args" 2> /dev/null || true)" 2 'selected profile/toolchain survive each completed transfer'
run_case rust recover 0
check "$(cat "$c/count" 2> /dev/null || true)" 3 'transient download/install faults recover within bound'
run_case completion no 0
check "$(cat "$c/completion/new/uv")" 'actual completion bytes' 'stdout bytes reach completion consumer'
run_case completion yes 39
check "$(cat "$c/completion/new/uv")" 'prior completion' 'failed optional generation preserves prior consumer'
run_case completion fresh 0
check "$(cat "$c/completion/new/uv" 2> /dev/null || true)" 'actual completion bytes' 'completion destination directory is created when missing'
run_case stage explicit 0
check "$(dirname "$(cat "$c/stage" 2> /dev/null || true)")" "$c/tmp" 'explicit receiving TMPDIR preserved'
run_case stage default 0
check "$(grep -Ec '^(tmpfs|ramfs)$' "$c/fstype" 2> /dev/null || true)" 0 'default large staging lands on admitted disk'
run_case stage explicit-ram 0
check "$(cat "$c/fstype" 2> /dev/null || true)" tmpfs 'explicit receiving tmpfs choice is not overridden'
run_case stage no-disk 252
check "$(test -e "$c/stage" && echo yes || echo no)" no 'unavailable disk never falls back to RAM scratch'
printf '%s runtime contract failure(s)\n' "$failures"
[[ "$failures" == 0 ]]
