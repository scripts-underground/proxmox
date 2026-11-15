#!/usr/bin/env bash
# Template discovery against the current `pveam available` layout: section,
# archive name and architecture columns. Catalogue lines are copied from a
# PVE 9.2 node (2026-11-14). Only pveam, dpkg and pvesm are modelled.
# shellcheck disable=SC2034  # REPO_BASE, PREFLIGHT_* and var_* are read by the sourced build.func
set -uo pipefail
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
: "${TMPDIR:?provide a disk-backed TMPDIR}"
case "$(realpath -e "$TMPDIR")" in /tmp | /tmp/*) exit 1 ;; esac
WORK=$(mktemp -d "$TMPDIR/template-discovery.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
fails=0

check() {
  if [[ "$1" == "$2" ]]; then
    echo "ok    $3"
  else
    echo "FAIL  $3: want [$2] got [$1]"
    fails=$((fails + 1))
  fi
}

cat > "$WORK/catalog.txt" << 'EOF'
system          almalinux-10-default_20250930_amd64.tar.xz                   amd64
system          almalinux-9-default_20240911_amd64.tar.xz                    amd64
system          alpine-3.23-default_20261105_amd64.tar.xz                    amd64
system          alpine-3.24-default_20261105_amd64.tar.xz                    amd64
system          alpine-3.24-default_20261105_arm64.tar.xz                    arm64
system          archlinux-base_20260420-1_amd64.tar.zst                      amd64
system          centos-10-stream-default_20260713_amd64.tar.xz               amd64
system          centos-9-stream-default_20240828_amd64.tar.xz                amd64
system          debian-12-standard_12.12-1_amd64.tar.zst                     amd64
system          debian-13-standard_13.6-1_amd64.tar.zst                      amd64
system          debian-13-standard_13.6-1_arm64.tar.zst                      arm64
system          devuan-5.0-standard_5.0_amd64.tar.gz                         amd64
system          fedora-43-default_20260115_amd64.tar.xz                      amd64
system          fedora-44-default_20260713_amd64.tar.xz                      amd64
system          gentoo-current-openrc_20250508_amd64.tar.xz                  amd64
system          openeuler-25.03-default_20250507_amd64.tar.xz                amd64
system          opensuse-15.6-default_20240910_amd64.tar.xz                  amd64
system          opensuse-16.0-default_20260116_amd64.tar.xz                  amd64
system          rockylinux-10-default_20251001_amd64.tar.xz                  amd64
system          rockylinux-9-default_20240912_amd64.tar.xz                   amd64
system          ubuntu-24.04-standard_24.04-2_amd64.tar.zst                  amd64
system          ubuntu-26.04-standard_26.04-1_amd64.tar.zst                  amd64
system          ubuntu-26.10-standard_26.10-1_amd64.tar.zst                  amd64
EOF

TEST_ARCH=amd64
CATALOG_FILE="$WORK/catalog.txt"
pveam() {
  [[ "${1:-}" == available ]] && cat "$CATALOG_FILE"
  return 0
}
dpkg() { printf '%s\n' "$TEST_ARCH"; }
pvesm() { return 0; }

REPO_BASE="file://$ROOT"
# shellcheck source=/dev/null
source "$ROOT/misc/build.func" > /dev/null 2>&1
trap - ERR EXIT
set +eEuo pipefail
trap 'rm -rf "$WORK"' EXIT

check "$(_template_catalog_names fedora-43 -default_)" \
  fedora-43-default_20260115_amd64.tar.xz 'fedora 43 selects the amd64 archive'
check "$(_template_catalog_names fedora- -default_ | tr '\n' ' ')" \
  'fedora-43-default_20260115_amd64.tar.xz fedora-44-default_20260713_amd64.tar.xz ' \
  'empty version selects all Fedora archives in version order'
check "$(_template_catalog_names ubuntu- -standard_ | tail -n 1)" \
  ubuntu-26.10-standard_26.10-1_amd64.tar.zst 'empty dotted version selects the newest Ubuntu archive'
check "$(_template_catalog_names debian-13 -standard_)" \
  debian-13-standard_13.6-1_amd64.tar.zst 'debian 13 selects amd64, not arm64'
check "$(_template_catalog_names alpine-3.24 -default_)" \
  alpine-3.24-default_20261105_amd64.tar.xz 'alpine 3.24 on amd64 ignores the arm64 row'
check "$(_template_catalog_names fedora-99 -default_)" '' 'no match prints nothing'
check "$(_template_catalog_names fedora-4 '')" '' 'search needs a [._-] boundary after the version'
check "$(_template_catalog_names fedora-43 -standard_)" '' 'pattern filters the variant'
printf 'system          fedora-43-default_20260115_amd64.tar.xz\n' > "$WORK/legacy.txt"
CATALOG_FILE="$WORK/legacy.txt"
check "$(_template_catalog_names fedora-43 -default_)" \
  fedora-43-default_20260115_amd64.tar.xz 'older two-column layout is still accepted'
CATALOG_FILE="$WORK/catalog.txt"
check "$(_template_catalog_versions fedora | tr '\n' ' ')" '43 44 ' 'fedora versions from the catalogue'
check "$(_template_catalog_versions ubuntu | tr '\n' ' ')" '24.04 26.04 26.10 ' 'dotted ubuntu versions'

TEST_ARCH=arm64
check "$(_template_catalog_names alpine-3.24 -default_)" \
  alpine-3.24-default_20261105_arm64.tar.xz 'arm64 host selects the arm64 archive'
check "$(_template_catalog_names debian-13 -standard_)" \
  debian-13-standard_13.6-1_arm64.tar.zst 'arm64 host selects the arm64 debian'
check "$(_template_catalog_names fedora-43 -default_)" '' 'arm64 host sees no amd64-only fedora'
TEST_ARCH=amd64

# Preflight is the existing online check; it must honour the host architecture.
preflight_outcome() {
  PREFLIGHT_FAILED=0
  PREFLIGHT_PASSED=0
  preflight_template_available > /dev/null 2>&1
  if ((PREFLIGHT_FAILED > 0)); then echo fail; else echo pass; fi
}

var_os=alpine var_version=3.24
cp "$WORK/catalog.txt" "$WORK/full.txt"
grep 'arm64' "$WORK/full.txt" | grep 'alpine-3.24' > "$WORK/catalog.txt"
check "$(preflight_outcome)" fail 'preflight rejects an arm64-only catalogue on amd64'
cp "$WORK/full.txt" "$WORK/catalog.txt"
check "$(preflight_outcome)" pass 'preflight accepts the amd64 alpine 3.24 archive'

var_os=fedora var_version=99
check "$(preflight_outcome)" fail 'preflight rejects a version the catalogue lacks'
var_os=fedora var_version=''
check "$(preflight_outcome)" pass 'preflight permits an empty version prefix'

if ((fails > 0)); then
  echo "$fails failure(s)"
  exit 1
fi
echo 'template discovery: all checks passed'
