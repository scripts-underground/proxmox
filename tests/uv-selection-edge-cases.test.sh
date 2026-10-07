#!/usr/bin/env bash
# Selection fixtures are executable witnesses, not genuine uv resolvers.
set -euo pipefail
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
# shellcheck source=tests/lib/safety-gap-common.sh
source "$ROOT/tests/lib/safety-gap-common.sh"
sg_init "$@"
mkdir "$SG_CASE/project"
python3 - << 'PY'
import io
import json
import os
import pathlib
import tarfile
import tomllib

root = pathlib.Path(os.environ['SG_CASE'])
project = root / 'project'
case = os.environ['SG_ID']
older, latest = '0.12.13', '0.12.22'
override = ''
if case == 'U1':
    override = latest
    (project / 'pyproject.toml').write_text('[tool.uv]\nrequired-version = "==0.12.13"\n')
elif case == 'U2':
    (project / 'uv.toml').write_text('required-version = "==0.12.13"\n')
elif case == 'U3':
    (project / 'uv.toml').write_text('required-version = "==0.12.13"\n')
    (project / 'pyproject.toml').write_text('[tool.uv]\nrequired-version = "==0.12.22"\n')
elif case == 'U4':
    (project / 'uv.toml').write_text('required-version = ">=0.12.13"\n')
    (project / 'pyproject.toml').write_text('[tool.uv]\nrequired-version = "==0.12.13"\n')
elif case == 'U5':
    (project / 'uv.toml').write_text("required-version = '==0.12.13'\n")
elif case == 'U6':
    (project / 'uv.toml').write_text('required-version = "==0.12.13" # legitimate TOML comment\n')
elif case == 'U7':
    (project / 'uv.toml').write_text('  required-version  =  "  == 0.12.13"  \n')
elif case == 'U8':
    override = '==0.12.13'
elif case == 'U9':
    (project / 'pyproject.toml').write_text('[tool.other]\nrequired-version = "==0.12.22"\nnotes = \'\'\'\n[tool.uv]\nrequired-version = "==0.12.22"\n\'\'\'\n[tool.uv]\nrequired-version = "==0.12.13"\n')
elif case == 'U10':
    (project / 'uv.toml').write_text('index-url = "https://fixture.invalid/simple"\n')
    (project / 'pyproject.toml').write_text('[tool.uv]\nrequired-version = "==0.12.13"\n')
elif case == 'U11':
    (project / 'pyproject.toml').write_text('[tool.uv]\nrequired-version = "0.12.13"\n')
elif case == 'U12':
    (project / 'uv.toml').write_text('required-version = "==0.12.\\u0031\\u0033"\n')
else:
    raise SystemExit('unknown uv fixture')
effective = ''
if (project / 'uv.toml').exists():
    effective = tomllib.loads((project / 'uv.toml').read_text()).get('required-version', '')
elif (project / 'pyproject.toml').exists():
    effective = tomllib.loads((project / 'pyproject.toml').read_text()).get('tool', {}).get('uv', {}).get('required-version', '')
requirement = (override or effective).strip()
expected = latest
if requirement in (older, latest):
    expected = requirement
elif requirement.startswith('==') and requirement[2:].strip() in (older, latest):
    expected = requirement[2:].strip()
(root / 'oracle.json').write_text(json.dumps({'expected': expected, 'effective_configuration': effective,
                                           'override': override, 'latest_fixture': latest,
                                           'oracle': 'tomllib and documented uv.toml precedence',
                                            'conditional_override': case == 'U8'}, indent=2) + '\n')
(root / 'override.txt').write_text(override)
for version in (older, latest):
    program = (f'#!/bin/sh\nif [ "$1" = "--version" ]; then printf "uv {version}\\n"; exit 0; fi\n'
               'if [ "$1" = "generate-shell-completion" ]; then printf "# fixture completion\\n"; exit 0; fi\nexit 64\n').encode()
    with tarfile.open(root / 'assets' / f'uv-{version}.tar.gz', 'w:gz') as archive:
        entry = tarfile.TarInfo('uv-fixture/uv')
        entry.mode, entry.size, entry.mtime = 0o755, len(program), 0
        archive.addfile(entry, io.BytesIO(program))
PY
sg_release_routes github astral-sh/uv 0.12.13 "$SG_CASE/assets/uv-0.12.13.tar.gz" uv-x86_64-unknown-linux-gnu.tar.gz prebuild
sg_release_routes github astral-sh/uv 0.12.22 "$SG_CASE/assets/uv-0.12.22.tar.gz" uv-x86_64-unknown-linux-gnu.tar.gz prebuild
sg_add_route https://github.com/astral-sh/uv/releases/download/==0.12.13/uv-x86_64-unknown-linux-gnu.tar.gz 404 invalid-requirement-style-release-url
sg_snapshot "$SG_CASE/before.json" binary=/usr/local/bin/uv cache=/var/cache/app-versions/uv_version.txt
sg_load
if [[ "$SG_ID" == U12 ]]; then
  printf '#!/bin/sh\nprintf "uv 0.12.13\\n"\n' > /usr/local/bin/uv
  chmod 755 /usr/local/bin/uv
  cache_installed_version uv 0.12.13
  sg_snapshot "$SG_CASE/before.json" binary=/usr/local/bin/uv cache=/var/cache/app-versions/uv_version.txt
fi
export UV_PROJECT_DIR="$SG_CASE/project"
override=$(< "$SG_CASE/override.txt")
[[ -z "$override" ]] || export UV_VERSION="$override"
if _uv_required_version "$UV_PROJECT_DIR" > "$SG_CASE/parsed-project-pin.txt"; then
  parsed_rc=0
else
  parsed_rc=$?
fi
printf '%s\n' "$parsed_rc" > "$SG_CASE/parser-status.txt"
if setup_uv; then operation_rc=0; else operation_rc=$?; fi
printf '%s\n' "$operation_rc" > "$SG_CASE/operation-status.txt"
if [[ -x /usr/local/bin/uv ]]; then
  if /usr/local/bin/uv --version > "$SG_CASE/consumer-version.txt"; then consumer_rc=0; else consumer_rc=$?; fi
  printf '%s\n' "$consumer_rc" > "$SG_CASE/consumer-status.txt"
fi
get_cached_version uv > "$SG_CASE/consumer-cache.txt"
sg_snapshot "$SG_CASE/after.json" binary=/usr/local/bin/uv cache=/var/cache/app-versions/uv_version.txt
