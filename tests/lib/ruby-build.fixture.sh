#!/usr/bin/env bash
# Real setup_ruby and caller selection; package/network/compiler/rbenv are models.
set -euo pipefail
: "${TMPDIR:?disk-backed TMPDIR required}"
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/../..")
work=$(mktemp -d "$TMPDIR/ruby-build.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
failures=0
check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
for scenario in discourse sure fresh installed available download-failure; do
  c="$work/$scenario"
  mkdir -p "$c/home/.rbenv/bin" "$c/home/.rbenv/versions/3.4.4" "$c/payload/ruby-build-fixture/share/ruby-build" "$c/tmp" "$c/app"
  printf '4.0.10\n' > "$c/target"
  [[ "$scenario" != sure ]] || printf '3.4.5\n' > "$c/target"
  printf 'ruby "~> 4.0.0"\n' > "$c/app/Gemfile"
  cp "$c/target" "$c/app/.ruby-version"
  printf '3.4.4\n' > "$c/home/.rbenv/version"
  if [[ "$scenario" != fresh ]]; then
    mkdir -p "$c/home/.rbenv/plugins/ruby-build/share/ruby-build"
    printf 'stale definition\n' > "$c/home/.rbenv/plugins/ruby-build/share/ruby-build/3.4.4"
  fi
  for version in 4.0.10 3.4.5; do printf 'fresh definition\n' > "$c/payload/ruby-build-fixture/share/ruby-build/$version"; done
  if [[ "$scenario" == installed ]]; then mkdir -p "$c/home/.rbenv/versions/4.0.10"; fi
  if [[ "$scenario" == available ]]; then cp "$c/payload/ruby-build-fixture/share/ruby-build/4.0.10" "$c/home/.rbenv/plugins/ruby-build/share/ruby-build/4.0.10"; fi
  cat > "$c/home/.rbenv/bin/rbenv" << 'RBENV'
#!/usr/bin/env bash
set -euo pipefail
root="$HOME/.rbenv"
case "$1" in
  init) printf ':\n' ;;
  versions) find "$root/versions" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' ;;
  global)
    if [[ $# == 1 ]]; then cat "$root/version"; else printf '%s\n' "$2" > "$root/version"; fi
    ;;
  install)
    printf '%s\n' "$2" >> "$RUBY_FIXTURE/installs"
    [[ -f "$root/plugins/ruby-build/share/ruby-build/$2" ]] || exit 91
    mkdir -p "$root/versions/$2"
    ;;
  *) exit 92 ;;
esac
RBENV
  chmod 0755 "$c/home/.rbenv/bin/rbenv"
  # Keep Discourse's actual update-time Gemfile/index selection through its helper
  # call, and Sure's exact .ruby-version call. Only their filesystem roots move.
  if [[ "$scenario" == discourse ]]; then
    sed -n '/^function update_script()/,$p' "$ROOT/scripts/lxc/discourse.sh" |
      sed -n '/^  local ruby_req /,/^  RUBY_VERSION=.*setup_ruby/p' |
      sed "s|/opt/discourse|$c/app|g" > "$c/caller.sh"
  elif [[ "$scenario" == sure ]]; then
    sed -n '/^function update_script()/,$p' "$ROOT/scripts/lxc/sure.sh" |
      grep 'RUBY_VERSION=.*setup_ruby' |
      sed "s|/opt/sure|$c/app|g; s|HOME=/root|HOME=\"$c/home\"|g" > "$c/caller.sh"
  else
    printf 'RUBY_VERSION=$(cat "$RUBY_FIXTURE/target") RUBY_INSTALL_RAILS=false setup_ruby\n' > "$c/caller.sh"
  fi
  rc=0
  env -i PATH="$PATH" HOME="$c/home" TMPDIR="$c/tmp" RUBY_FIXTURE="$c" RUBY_SCENARIO="$scenario" ROOT="$ROOT" \
    bash -se > "$c/output" 2>&1 << 'CHILD' || rc=$?
source "$ROOT/misc/tools.func"
STD=
msg_info() { :; }
msg_ok() { :; }
msg_warn() { :; }
msg_error() { printf '%s\n' "$*" >&2; }
ensure_apt_working() { :; }
apt-cache() { printf 'fixture-package\n'; }
apt() { :; }
gem() { :; }
cache_installed_version() { printf '%s\n' "$*" >> "$RUBY_FIXTURE/cache"; }
get_latest_github_release() { printf '%s\n' "$1" >> "$RUBY_FIXTURE/releases"; printf 'fixture\n'; }
curl_with_retry() {
  printf '%s\n' "$1" >> "$RUBY_FIXTURE/downloads"
  [[ "$RUBY_SCENARIO" != download-failure ]] || return 22
  tar -czf "$2" -C "$RUBY_FIXTURE/payload" ruby-build-fixture
}
curl() { printf 'name\turl\n ruby-4.0.9\tu\nruby-4.0.9\tu\nruby-4.0.10\tu\nruby-4.1.0-preview1\tu\n'; }
caller() { source "$RUBY_FIXTURE/caller.sh"; }
caller
CHILD
  if [[ "$scenario" == download-failure ]]; then
    check "$rc" 7 'ruby-build refresh propagates download failure'
    check "$(cat "$c/home/.rbenv/version")" 3.4.4 'failed refresh leaves selected Ruby unchanged'
    check "$(cat "$c/home/.rbenv/plugins/ruby-build/share/ruby-build/3.4.4")" 'stale definition' 'failed refresh retains existing plugin'
    check "$(test -e "$c/installs" && printf yes || printf no)" no 'failed refresh never compiles'
  else
    check "$rc" 0 "$scenario stale ruby-build installs selected Ruby"
    check "$(cat "$c/home/.rbenv/version")" "$(cat "$c/target")" "$scenario selected Ruby reaches global consumer"
    check "$(test -d "$c/home/.rbenv/versions/$(cat "$c/target")" && printf yes || printf no)" yes "$scenario selected Ruby is installed"
    if [[ "$scenario" == installed || "$scenario" == available ]]; then
      check "$(test -e "$c/downloads" && printf yes || printf no)" no "$scenario needs no definition download"
    else
      check "$(cat "$c/releases" 2> /dev/null || true)" rbenv/ruby-build "$scenario refresh belongs to shared ruby-build owner"
    fi
    if [[ "$scenario" == installed ]]; then check "$(test -e "$c/installs" && printf yes || printf no)" no 'installed Ruby is not rebuilt'; fi
  fi
done
printf '%s failure(s); real setup_ruby and caller selection, modeled network/packages/compiler\n' "$failures"
[[ "$failures" == 0 ]]
