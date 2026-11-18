#!/usr/bin/env bash
# Invoked only by the admitted Odysseus consumer in its newly created owned CT.
set -euo pipefail
[[ "$(systemd-detect-virt --container)" == lxc ]]
: "${TMPDIR:?disk-backed receiver required}"
subject=${1:?tested source projection}
source "$subject/misc/core.func"
source "$subject/misc/error_handler.func"
source "$subject/misc/tools.func"
_INSTALL_DEFER_BOOTSTRAP=1 source "$subject/misc/install.func"
load_functions
export APP=Odysseus APPLICATION=Odysseus STD=silent
work=$(mktemp -d "$TMPDIR/core-native.XXXXXXXX")
export INSTALL_LOG="$work/consumer.log"
native_evidence() {
  local status=$? capture=0
  trap - EXIT
  tar -czf "$work.evidence.tar.gz" -C "$work" . || capture=$?
  printf 'CORE_NATIVE_EVIDENCE %s.evidence.tar.gz\n' "$work"
  [[ "$status" != 0 ]] || status=$capture
  exit "$status"
}
trap native_evidence EXIT
_configure_apt_conffiles

# The actual APT trust consumer reads the key in place, without network key
# replacement, and consumes authenticated indexes from only this generated source.
key=/usr/share/keyrings/debian-archive-keyring.gpg
before=$(stat -c '%a:%u:%g:%i' "$key")
setup_deb822_repo core-u5-native "$key" https://deb.debian.org/debian trixie main
[[ "$(stat -c '%a:%u:%g:%i' "$key")" == "$before" ]]
grep -Fx "Signed-By: $key" /etc/apt/sources.list.d/core-u5-native.sources
apt-get -o Dir::Etc::sourcelist=/etc/apt/sources.list.d/core-u5-native.sources \
  -o Dir::Etc::sourceparts=- -o APT::Update::Error-Mode=any update > "$work/apt-trust.log" 2>&1
apt-get -o Dir::Etc::sourcelist=/etc/apt/sources.list.d/core-u5-native.sources \
  -o Dir::Etc::sourceparts=- -y install hello >> "$work/apt-trust.log" 2>&1
[[ "$(hello)" == 'Hello, world!' ]]
printf 'PASS native local keyring trust, authenticated package install and executable consumer\n'

# A tiny real package owns the conffile; both raw app APT calls and the package
# abstraction must consume the initialized policy without prompting on conflict.
mkdir -p "$work/package/DEBIAN" "$work/package/etc"
printf '/etc/core-u5-conffile.conf\n' > "$work/package/DEBIAN/conffiles"
for version in 1 2 3 4; do
  printf 'Package: core-u5-conffile\nVersion: %s\nArchitecture: all\nMaintainer: Test <test@example.invalid>\nDescription: Native conffile consumer\n' "$version" > "$work/package/DEBIAN/control"
  printf 'vendor=%s\n' "$version" > "$work/package/etc/core-u5-conffile.conf"
  dpkg-deb --build "$work/package" "$work/package-$version.deb" > /dev/null
  if [[ "$version" == 3 ]]; then
    PKG_MANAGER=apt pkg_install "$work/package-$version.deb"
  elif [[ "$version" == 4 ]]; then
    apt -o Dpkg::Options::=--force-confnew install -y "$work/package-$version.deb" >> "$work/conffile.log" 2>&1
  else
    apt install -y "$work/package-$version.deb" >> "$work/conffile.log" 2>&1
  fi
  if [[ "$version" == 1 ]]; then
    printf 'operator=retained\n' > /etc/core-u5-conffile.conf
  elif [[ "$version" == 4 ]]; then
    [[ "$(cat /etc/core-u5-conffile.conf)" == vendor=4 ]]
  else [[ "$(cat /etc/core-u5-conffile.conf)" == operator=retained ]]; fi
done
printf 'PASS native raw APT and package abstraction preserve conffiles; explicit confnew wins\n'

# First generate a genuinely short-lived marked pair with native OpenSSL. Its
# checkend result, not a mocked expiry probe, must trigger the normal renewal.
openssl() {
  if [[ "$1" == req ]]; then
    local -a args=("$@")
    local i
    for ((i = 0; i < ${#args[@]} - 1; i++)); do
      [[ "${args[$i]}" != -days ]] || args[$((i + 1))]=1
    done
    command openssl "${args[@]}"
  else command openssl "$@"; fi
}
create_self_signed_cert Odysseus
unset -f openssl
cert=/etc/ssl/odysseus/odysseus.crt
key=/etc/ssl/odysseus/odysseus.key
first=$(openssl x509 -noout -fingerprint -sha256 -in "$cert")
mkdir -p /etc/systemd/system/odysseus.service.d
cat > /etc/systemd/system/odysseus.service.d/core-native-tls.conf << EOF
[Service]
ExecStart=
ExecStart=/opt/odysseus/venv/bin/uvicorn app:app --host 0.0.0.0 --port 443 --ssl-keyfile $key --ssl-certfile $cert
EOF
systemctl daemon-reload
systemctl restart odysseus.service
curl --noproxy '*' --cacert "$cert" --resolve localhost:443:127.0.0.1 -fsSL \
  --retry 20 --retry-connrefused --retry-delay 1 https://localhost/ -o "$work/first.html"
grep -qi odysseus "$work/first.html"
create_self_signed_cert Odysseus
[[ "$(openssl x509 -noout -fingerprint -sha256 -in "$cert")" != "$first" ]]
systemctl restart odysseus.service
curl --noproxy '*' --cacert "$cert" --resolve localhost:443:127.0.0.1 -fsSL \
  --retry 20 --retry-connrefused --retry-delay 1 https://localhost/ -o "$work/renewed.html"
grep -qi odysseus "$work/renewed.html"
[[ "$(stat -c '%a' "$key")" == 600 ]]
printf 'PASS native marked expiry renewal, actual Odysseus TLS loading and CA-verified application HTML\n'

# Controlled failure in the installed application's actual Python runtime. The
# existing error/flag owner must retain255, redact its diagnostic and leave the
# running app untouched; no terminal parser or command models are involved.
diagnostic_status=0
env SUBJECT="$subject" INSTALL_LOG="$work/diagnostics.log" DEBUG_LOGFILE="$work/diagnostics-debug.log" \
  U6_SECRET=fixture-native-private SESSION_ID=core-u6-diagnostics DEV_MODE_KEEP=true \
  bash -c '
    source "$SUBJECT/misc/core.func"
    source "$SUBJECT/misc/error_handler.func"
    load_functions
    unset CTID
    catch_errors
    silent /opt/odysseus/venv/bin/python -c '\''import os; print("password=literal-native-password"); print(os.environ["U6_SECRET"]); print("x"*120000); print("final-native-diagnostic-cause"); raise SystemExit(255)'\''
  ' > "$work/diagnostics-output.log" 2>&1 || diagnostic_status=$?
[[ "$diagnostic_status" == 255 ]]
cp /root/.install-core-u6-diagnostics.failed "$work/diagnostics-flag.log"
[[ "$(cat "$work/diagnostics-flag.log")" == 255 ]]
grep -Fq final-native-diagnostic-cause "$work/diagnostics-output.log"
! grep -Eq 'DPKG: Fatal|literal-native-password|fixture-native-private' "$work/diagnostics-output.log" "$work/diagnostics-debug.log"
[[ "$(wc -c < "$work/diagnostics-output.log")" -lt 16000 ]]
grep -Fq 'Failed command' "$work/diagnostics.log"
curl --noproxy '*' --cacert "$cert" --resolve localhost:443:127.0.0.1 -fsSL https://localhost/ -o "$work/after-diagnostic.html"
grep -qi odysseus "$work/after-diagnostic.html"
printf 'PASS native app-runtime failure retains255, redacted useful diagnostics and failure flag; actual TLS app remains available\n'
printf 'CORE_CREATION_PACKAGES_NATIVE_PASS\n'
