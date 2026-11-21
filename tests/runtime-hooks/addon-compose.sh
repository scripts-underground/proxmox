#!/usr/bin/env bash
# runtime-hooks-contract: fixture case-asserted
# Shared node prepass and demand-only parser admission; package/Docker effects modeled.
# shellcheck disable=SC2034
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/harness.sh"
systemd-detect-virt --vm --quiet || exit 1
: "${TMPDIR:?disk-backed TMPDIR required}"
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
source "$ROOT/misc/addon_lxc.func"
work=$(mktemp -d "$TMPDIR/addon-compose.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT
failures=0
msg_error() { printf '%s\n' "$*" >&2; }
msg_warn() { printf '%s\n' "$*" >&2; }
if ! declare -F _addon_compose_preprocess > /dev/null; then
  check missing present 'shared YAML node prepass is required'
else
  cat > "$work/input.yaml" << 'YAML'
x-untouched: &keep
  quoted: !!str on
  number: 0007
  date: 2026-11-19
  command: 'literal $${VAR:-keep}'
services:
  probe:
    image: 'image:${TAG:-latest}'
    x-shared: *keep
    ports: ['${HOST_PORT:-18080}:${TARGET_PORT:-8080}']
    volumes:
      - '${SOURCE:-/host}:${TARGET:-/data}:ro'
      - '${SOURCE:?required}:${TARGET:?required}:rw'
      - '${SOURCE:+/host}:${TARGET:+/data}'
      - '${SOURCE:-${FALLBACK:-/host:with-colon}}:${TARGET:-/data}:ro'
      - '/plain:/unchanged:ro'
      - {type: bind, source: '${SOURCE:-/host}', target: /long-unchanged}
      - '${SOURCE:-/host}:${TARGET:-/data}:ro,rshared,z'
      - '$${LITERAL:-keep}:/literal'
YAML
  _addon_compose_preprocess "$work/input.yaml" "$work/output.yaml"
  status=0
  command python3 - "$work/input.yaml" "$work/output.yaml" << 'PY' || status=$?
import sys,yaml
from yaml.nodes import MappingNode,SequenceNode,ScalarNode
def field(node,key):return next(value for name,value in node.value if name.value==key)
def shape(node):
 if isinstance(node,ScalarNode):return (node.tag,node.value)
 return (node.tag,[(shape(k),shape(v)) for k,v in node.value]) if isinstance(node,MappingNode) else (node.tag,[shape(n) for n in node.value])
before,after=[yaml.compose(open(path),Loader=yaml.SafeLoader) for path in sys.argv[1:]]
b=field(field(before,'services'),'probe');a=field(field(after,'services'),'probe')
old,new=field(b,'volumes'),field(a,'volumes')
assert len(old.value)==len(new.value)==8
expected=[('${SOURCE:-/host}','${TARGET:-/data}',True),('${SOURCE:?required}','${TARGET:?required}',False),('${SOURCE:+/host}','${TARGET:+/data}',False),('${SOURCE:-${FALLBACK:-/host:with-colon}}','${TARGET:-/data}',True)]
for mount,(source,target,readonly) in zip(new.value,expected):
 assert field(mount,'type').value=='bind'
 assert field(mount,'source').value==source and field(mount,'target').value==target
 assert field(mount,'read_only').value==str(readonly).lower()
assert shape(old.value[4])==shape(new.value[4]) and shape(old.value[5])==shape(new.value[5])
assert field(field(new.value[6],'bind'),'propagation').value=='rshared'
assert field(field(new.value[6],'bind'),'selinux').value=='z'
assert field(new.value[6],'read_only').value=='true'
assert shape(old.value[7])==shape(new.value[7])
# Ignore only affected short-bind replacements; every other tag/scalar stays.
new.value[:4]=old.value[:4]
new.value[6]=old.value[6]
assert shape(before)==shape(after)
assert field(after,'x-untouched') is field(a,'x-shared')
PY
  check "$status" 0 'node projection preserves expressions, nested colons, other nodes, tags and aliases'
  printf '%s\n' 'services: {probe: {image: "image:${TAG:-latest}"}}' > "$work/unrelated.yaml"
  _addon_compose_preprocess "$work/unrelated.yaml" "$work/unrelated-copy.yaml"
  check "$(cmp -s "$work/unrelated.yaml" "$work/unrelated-copy.yaml" && printf unchanged || printf changed)" unchanged 'unrelated colon-operator expression leaves all source bytes unchanged'

  # Source-model preparation alone admits the parser. Updates that consume the
  # saved model do not call this owner or acquire an unneeded package.
  for OS_FAMILY in debian alpine; do
    for variant in needed plain dependency-failure preprocess-failure native-failure; do
      case_root="$work/$OS_FAMILY-$variant"
      mkdir "$case_root"
      printf '%s\n' 'services: {probe: {image: scratch}}' > "$case_root/source.yaml"
      if [[ "$variant" != plain ]]; then cp "$work/input.yaml" "$case_root/source.yaml"; fi
      if [[ "$variant" == preprocess-failure ]]; then printf '%s\n' 'services: ["${INVALID:-private-value}"' > "$case_root/source.yaml"; fi
      before=$(sha256sum "$case_root/source.yaml")
      : > "$case_root/dependencies"
      : > "$case_root/docker"
      python3() {
        if [[ "${1:-}" == -c && ! -e "$case_root/installed" ]]; then return 1; fi
        command python3 "$@"
      }
      ensure_dependencies() {
        printf 'package progress output\n'
        printf '%s\n' "$@" >> "$case_root/dependencies"
        [[ "$variant" != dependency-failure ]] || return 54
        touch "$case_root/installed"
      }
      docker() {
        printf invoked >> "$case_root/docker"
        [[ "$variant" != native-failure ]] || return 47
        local file=''
        while (($#)); do
          [[ "$1" != -f ]] || {
            file=$2
            shift
          }
          shift
        done
        stat -c %a "$file" > "$case_root/native-input-mode"
        command python3 - "$file" << 'PY'
import json,sys,yaml
print(json.dumps(yaml.safe_load(open(sys.argv[1])),default=str))
PY
      }
      status=0
      addon_compose_source --project-directory "$case_root" -f "$case_root/source.yaml" > "$case_root/model.json" || status=$?
      expected=0
      [[ "$variant" != dependency-failure ]] || expected=54
      [[ "$variant" != preprocess-failure ]] || expected=65
      [[ "$variant" != native-failure ]] || expected=47
      check "$status" "$expected" "$OS_FAMILY/$variant exact source-model outcome"
      package=python3-yaml
      [[ "$OS_FAMILY" != alpine ]] || package=py3-yaml
      if [[ "$variant" == plain ]]; then package=''; fi
      check "$(cat "$case_root/dependencies")" "$package" "$OS_FAMILY/$variant parser package admitted only on demand"
      check "$(find "$case_root" -name '.addon-compose.*' | wc -l)" 0 "$OS_FAMILY/$variant retires only its preprocessing stage"
      check "$(sha256sum "$case_root/source.yaml")" "$before" "$OS_FAMILY/$variant fetched source stays unchanged"
      if [[ "$variant" == dependency-failure || "$variant" == preprocess-failure ]]; then
        check "$(stat -c %s "$case_root/docker")" 0 'failed parser admission precedes native Compose'
      fi
      if [[ "$variant" == needed ]]; then
        check "$(cat "$case_root/native-input-mode")" 600 'native Compose consumes a private preprocessing stage'
        addon_compose_source --project-directory "$case_root" -f "$case_root/source.yaml" > "$case_root/second-model.json"
        check "$(wc -l < "$case_root/dependencies")" 1 'positive installed parser is reused without another package effect'
      fi
      unset -f python3 ensure_dependencies docker
    done
  done
fi
printf 'RUNTIME_HOOKS_RESULT failures=%s\n' "$failures"
[[ "$failures" == 0 ]]
