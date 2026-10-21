#!/usr/bin/env bash
# Native source-format capability evidence, not a claim of a working migration.
set -euo pipefail
systemd-detect-virt --vm --quiet || exit 1
: "${TMPDIR:?disk TMPDIR required}" "${MAINTENANCE_REFERENCES:?}"
work=$(mktemp -d "$TMPDIR/paperless-format-source.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
python3 - "$MAINTENANCE_REFERENCES" "$work" << 'PY'
import ast,fnmatch,json,os,pathlib,sys,typing
from types import SimpleNamespace
from dotenv import dotenv_values
from watchfiles import Change,DefaultFilter
refs=pathlib.Path(sys.argv[1]);root=pathlib.Path(sys.argv[2]);consume=root/'consume';consume.mkdir()
for folder in ('public','private-one','private-two'):
 (consume/folder).mkdir();(consume/folder/'scan.pdf').write_bytes(b'PDF fixture')
config=root/'paperless.conf';config.write_text("PAPERLESS_CONSUMER_IGNORE_PATTERNS='[\"private*/*\"]'\nPAPERLESS_SECRET_KEY='literal O\\'Reilly secret'\n")
values=dotenv_values(config);patterns=json.loads(values['PAPERLESS_CONSUMER_IGNORE_PATTERNS'])
assert patterns==['private*/*']
assert values['PAPERLESS_SECRET_KEY']=="literal O'Reilly secret"
old=ast.parse((refs/'paperless-v2/src/documents/management/commands/document_consumer.py').read_text())
function=next(n for n in old.body if isinstance(n,ast.FunctionDef) and n.name=='_is_ignored')
ns={'Path':pathlib.Path,'PurePath':pathlib.PurePath,'filter':fnmatch.filter,'settings':SimpleNamespace(CONSUMPTION_DIR=consume,CONSUMER_IGNORE_PATTERNS=patterns)}
exec(compile(ast.Module(body=[function],type_ignores=[]),'actual-v2-consumer','exec'),ns)
old_ignore=ns['_is_ignored']
new=ast.parse((refs/'paperless-v3/src/documents/management/commands/document_consumer.py').read_text())
klass=next(n for n in new.body if isinstance(n,ast.ClassDef) and any(isinstance(b,ast.Name) and b.id=='DefaultFilter' for b in n.bases))
ns3={'DefaultFilter':DefaultFilter,'Final':typing.Final,'Change':Change,'Path':pathlib.Path}
exec(compile(ast.Module(body=[klass],type_ignores=[]),'actual-v3-consumer','exec'),ns3)
factory=ns3[klass.name]
regex=factory(supported_extensions=frozenset({'.pdf'}),ignore_patterns=[fnmatch.translate(p) for p in patterns])
literal=factory(supported_extensions=frozenset({'.pdf'}),ignore_dirs=['private*'])
for folder in ('private-one','private-two'):
 path=consume/folder/'scan.pdf'
 assert old_ignore(path)
 assert regex(Change.added,str(path))
 assert literal(Change.added,str(path))
assert not old_ignore(consume/'public/scan.pdf')
ns['settings'].CONSUMER_IGNORE_PATTERNS=['consume/*']
assert not old_ignore(consume/'public/scan.pdf')
root_literal=factory(supported_extensions=frozenset({'.pdf'}),ignore_dirs=['consume'])
assert not root_literal(Change.added,str(consume/'public/scan.pdf'))
print('NATIVE_V3_LITERAL_DIRECTORY_ROOT_COLLISION=ignores a document accepted by actual v2')
print('NATIVE_PAPERLESS_DOTENV_JSON_AND_QUOTED_SECRET=parsed')
print('NATIVE_V2_PRIVATE_DIRECTORY_GLOB=ignores private-one/scan.pdf and private-two/scan.pdf')
print('NATIVE_V3_ESCAPED_REGEX_REWRITE=accepts both formerly ignored documents')
print('NATIVE_V3_IGNORE_DIRS_LITERAL_WILDCARD=accepts both formerly ignored documents')
print('NATIVE_UNSUPPORTED_GLOB_CAPABILITY=checked refusal required for wildcard directories and absolute-root collisions')
PY
