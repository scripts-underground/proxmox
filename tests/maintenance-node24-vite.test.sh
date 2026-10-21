#!/usr/bin/env bash
# Native Node24 + npm's engine checker + the selected AliasVault Vite consumer.
# This bounded compiler fixture is not a whole AliasVault/.NET/Rust build.
set -euo pipefail
systemd-detect-virt --vm --quiet || exit 1
: "${TMPDIR:?}" "${RUNTIME_NODE:?}" "${RUNTIME_NPM:?}" "${RUNTIME_EXTRA_REFERENCES:?}"
work=$(mktemp -d "$TMPDIR/node24-vite.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
export HOME="$work/home" npm_config_cache="$work/cache"
mkdir -p "$HOME"
version=$(
  "$RUNTIME_NODE" - "$RUNTIME_NPM" "$RUNTIME_EXTRA_REFERENCES/aliasvault/apps/web/package-lock.json" << 'JS'
const fs=require('node:fs'),path=require('node:path');
const semver=require(path.resolve(process.argv[2],'../../node_modules/semver'));
const lock=JSON.parse(fs.readFileSync(process.argv[3],'utf8'));
let count=0;
for(const [name,pkg] of Object.entries(lock.packages)) {
 if(pkg.engines?.node) { if(!semver.satisfies(process.version,pkg.engines.node))throw Error(name+' rejects '+process.version+' via '+pkg.engines.node);count++; }
}
if(!process.version.startsWith('v24.'))throw Error('Wrong native runtime');
process.stderr.write('NATIVE_ALIAS_NODE_ENGINE_CONSTRAINTS='+count+'\n');
process.stdout.write(lock.packages['node_modules/vite'].version);
JS
)
printf '{"name":"bounded-alias-client","type":"module"}\n' > "$work/package.json"
printf '<html><body><script type="module" src="/main.js"></script></body></html>\n' > "$work/index.html"
printf 'document.body.dataset.consumer="native-node24-vite";\n' > "$work/main.js"
: > "$work/user.npmrc"
: > "$work/global.npmrc"
"$RUNTIME_NODE" "$RUNTIME_NPM" install --prefix "$work" --engine-strict --ignore-scripts --no-audit --no-fund --userconfig="$work/user.npmrc" --globalconfig="$work/global.npmrc" "vite@$version"
"$RUNTIME_NODE" "$work/node_modules/vite/bin/vite.js" build "$work"
test -s "$work/dist/index.html"
python3 - "$work/dist" << 'PY'
import pathlib,sys
p=pathlib.Path(sys.argv[1]);assets=list((p/'assets').glob('*.js'));assert assets and any('native-node24-vite' in f.read_text() for f in assets)
print('NATIVE_ALIAS_NODE24_VITE_CONSUMER=generated index and JS payload observed')
PY
