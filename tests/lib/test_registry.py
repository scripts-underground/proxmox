"""Source-owned catalogue. Metadata is not authorization to execute a suite."""
from dataclasses import dataclass


@dataclass(frozen=True)
class Suite:
    path: str
    modes: tuple
    role: str = 'guest-fixture'
    args: tuple = ()


# Closed audit (main 01ed3f4), not filesystem discovery or caller commands.
FIXTURES = '''autocaliweb-update container-install-failure deploy-replace-contents
endurain-github filebrowser-retry-install gpu-passthrough gpu-userspace
invidious-companion-update jellyfin-ffmpeg keycloak-keep-install legacy-version-marker
llama-cpp maintenance-addon-writer maintenance-app-compat maintenance-app-preservation
maintenance-build-hooks maintenance-build-temp maintenance-bundle-bootstrap maintenance-current-hardening
maintenance-bundle-writer maintenance-consumers maintenance-cron-update maintenance-go-minimum
maintenance-gpg-key maintenance-immich maintenance-keep maintenance-kosmozoo-current maintenance-merge-inplace
maintenance-node24-vite maintenance-nodejs maintenance-package-force maintenance-paperless-format-source
maintenance-prefix-arch maintenance-receiver-portability maintenance-receiving-context
maintenance-release-boundaries maintenance-release-metadata maintenance-replacement-review
maintenance-retry-callers maintenance-retry-preservation maintenance-runtime-hooks
maintenance-service-edges maintenance-service-uninstall maintenance-silent
maintenance-uninstall maintenance-uv-range maintenance-webtrees maintenance-zigbee2mqtt
migration-dragonfly nvidia-userspace ollama-keep-install release-check-errors requested-release
restore-backup ssh-default-keys strata tools-retry-timer update-pending
wanderer-plugin-dirs'''.split()
REGISTRY = {name: Suite(f'tests/{name}.test.sh', ('fixture',)) for name in FIXTURES}
REGISTRY.update({
    'calibre-web-automated': Suite('tests/calibre-web-automated.test.sh', ('nested-install',), 'nested-install'),
    'odysseus': Suite('tests/odysseus.test.sh', ('nested-install',), 'nested-install'),
    'codeberg-release': Suite('tests/codeberg-release.test.sh', ('fixture', 'live', 'bundle'), 'mode-specific', (('live', '--live'), ('bundle', '--bundle'))),
    'github-force-deploy': Suite('tests/github-force-deploy.test.sh', ('live-runtime',), 'live-runtime'),
    'maintenance-kosmozoo-native': Suite('tests/maintenance-kosmozoo-native.test.sh', ('live-runtime',), 'live-runtime'),
    'maintenance-lazylibrarian-native': Suite('tests/maintenance-lazylibrarian-native.test.sh', ('bundle',), 'bundle'),
    'migration-dragonfly-native': Suite('tests/migration-dragonfly-native.test.sh', ('live-runtime',), 'live-runtime'),
    'uv-project-version': Suite('tests/uv-project-version.test.sh', ('live-runtime',), 'live-runtime'),
    'romm-player-serving': Suite('tests/romm-player-serving.test.sh', ('live-runtime', 'setup'), 'live-runtime', (('setup', '--setup'),)),
    'romm-live-verification': Suite('tests/romm-live-verification.test.sh', ('installed-probe',), 'installed-probe'),
    'maintenance-service-systemd': Suite('tests/maintenance-service-systemd.test.sh', ('native-unit',), 'native-unit'),
    'maintenance-service-edge-native': Suite('tests/maintenance-service-edge-native.test.sh', ('native-unit',), 'native-unit'),
    'maintenance-cleanup': Suite('tests/maintenance-cleanup.test.sh', ('fixture', 'native-fixture'), 'mode-specific', (('native-fixture', '--native'),)),
    'maintenance-temp-root': Suite('tests/maintenance-temp-root.test.sh', ('fixture', 'native-fixture'), 'mode-specific', (('native-fixture', '--native'),)),
    'maintenance-globnotes': Suite('tests/maintenance-globnotes.test.sh', ('native-fixture', 'baseline', 'runtime-lock-only', 'python-syntax'), 'native-root', (('native-fixture', '--native'), ('baseline', '--baseline'), ('runtime-lock-only', '--runtime-lock-only'), ('python-syntax', '--python-syntax-only'))),
    'maintenance-globnotes-lxc': Suite('tests/maintenance-globnotes-lxc.test.sh', ('native-app', 'guard'), 'native-app', (('native-app', '--native'), ('guard', '--stage', 'guard'))),
    'maintenance-template-lock': Suite('tests/maintenance-template-lock.test.sh', ('native-fixture', 'baseline', 'review-baseline', 'pty-baseline'), 'native-root', (('native-fixture', '--native'), ('baseline', '--baseline'), ('review-baseline', '--review-baseline'), ('pty-baseline', '--pty-baseline'))),
    'maintenance-update-lock': Suite('tests/maintenance-update-lock.test.sh', ('native-fixture', 'baseline', 'review-baseline', 'ui-no-detach'), 'native-root', (('native-fixture', '--native'), ('baseline', '--baseline'), ('review-baseline', '--review-baseline'), ('ui-no-detach', '--ui-no-detach'))),
})
TOOLS = {
    'globnotes-browser': Suite('tests/maintenance-globnotes-browser.mjs', ('installed-probe',), 'installed-probe'),
    'go-unit': Suite('tools/ast/main_test.go', ('contribution',), 'contribution'),
    'go-ast': Suite('tools/ast/main.go', ('contribution',), 'contribution'),
    'catalogue': Suite('tools/regen-scripts-json.rb', ('contribution',), 'contribution'),
    'logos': Suite('tools/validate-logos.rb', ('contribution',), 'contribution'),
    'contribution': Suite('.pre-commit-config.yaml', ('contribution',), 'contribution'),
}
REGISTRY.update(TOOLS)
REGISTRY['workflow-ownership'] = Suite('tests/test-workflow-ownership.test.sh', ('fixture',))
REGISTRY['workflow-entrypoints'] = Suite('tests/test-workflow-entrypoints.test.sh', ('fixture',))


@dataclass(frozen=True)
class Input:
    kind: str
    target: str
    required: bool = True


# Every advertised mode has one closed input contract, including empty contracts.
# Targets are fixed argv slots or test-process environment keys, never receiving
# framework exports. Tree values name a hashed immutable directory manifest.
INPUT_BINDINGS = {(suite,mode): {} for suite,row in REGISTRY.items() for mode in row.modes}
INPUT_BINDINGS['maintenance-lazylibrarian-native','bundle'] = {'lazylibrarian_fixture': Input('tree','LAZYLIBRARIAN_FIXTURE')}
for mode in REGISTRY['maintenance-globnotes'].modes:
    INPUT_BINDINGS['maintenance-globnotes',mode] = {'subject': Input('file','argv',False)}
for suite,modes,kind in [
    ('maintenance-template-lock',('baseline','review-baseline','pty-baseline'),'file'),
    ('maintenance-update-lock',('baseline','review-baseline'),'tree'),
    ('maintenance-update-lock',('ui-no-detach',),'file'),
]:
    for mode in modes:
        INPUT_BINDINGS[suite,mode] = {'baseline': Input(kind,'argv')}
for mode in REGISTRY['maintenance-update-lock'].modes:
    INPUT_BINDINGS['maintenance-update-lock',mode]['alpine_busybox'] = Input('executable','ALPINE_BUSYBOX')
INPUT_BINDINGS['maintenance-receiver-portability','fixture'] = {'alpine_busybox': Input('executable','ALPINE_BUSYBOX')}
INPUT_BINDINGS['maintenance-gpg-key','fixture'] = {'gpg_fixture': Input('file','GPG_FIXTURE')}
INPUT_BINDINGS['maintenance-app-compat','fixture'] = {
    'apprise_asset': Input('file','APPRISE_ASSET_FIXTURE'),
    'apprise_asset_path': Input('relative','APPRISE_ASSET_PATH'),
    'apprise_supervisor': Input('file','APPRISE_SUPERVISOR_FIXTURE'),
}
for suite in ('maintenance-runtime-hooks','maintenance-paperless-format-source','maintenance-build-hooks'):
    INPUT_BINDINGS[suite,'fixture']['maintenance_references'] = Input('tree','MAINTENANCE_REFERENCES')
for suite in ('maintenance-node24-vite','maintenance-build-hooks'):
    INPUT_BINDINGS[suite,'fixture']['runtime_extra_references'] = Input('tree','RUNTIME_EXTRA_REFERENCES')
for suite in ('maintenance-node24-vite','maintenance-build-hooks','maintenance-immich'):
    INPUT_BINDINGS[suite,'fixture']['runtime_node'] = Input('executable','RUNTIME_NODE')
INPUT_BINDINGS['maintenance-node24-vite','fixture']['runtime_npm'] = Input('file','RUNTIME_NPM')
for suite in ('maintenance-webtrees','maintenance-zigbee2mqtt','maintenance-immich'):
    INPUT_BINDINGS[suite,'fixture']['maintenance_next_references'] = Input('tree','MAINTENANCE_NEXT_REFERENCES')
INPUT_BINDINGS['maintenance-webtrees','fixture']['maintenance_caddy'] = Input('executable','MAINTENANCE_CADDY')
INPUT_BINDINGS['maintenance-replacement-review','fixture'] = {
    'alpine_busybox': Input('executable','ALPINE_BUSYBOX'),
    'replacement_tools': Input('file','REPLACEMENT_TOOLS',False),
    'large_size': Input('integer','REPLACEMENT_LARGE_SIZE',False),
    'budget_workspace': Input('workspace','REPLACEMENT_TASK_WORKSPACE',False),
    'budget_bytes': Input('integer','REPLACEMENT_TASK_BUDGET_BYTES',False),
}


def policy(suite, mode):
    row = REGISTRY.get(suite)
    if row is None or mode not in row.modes:
        raise ValueError('registry suite/mode not registered')
    if suite == 'workflow-ownership':
        return row, 'guest-fixture', ['fixture-files', 'subprocess', 'recording-nested']
    if suite == 'workflow-entrypoints':
        return row, 'guest-fixture', ['fixture-files', 'subprocess', 'recording-nested']
    role = row.role if row.role != 'mode-specific' else mode
    return row, role, [role]


@dataclass(frozen=True)
class Execution:
    owner: str
    public_phase: str
    direct_phase: str


# Executable policy belongs to source, separately from the stable context role/
# effects vocabulary. Unknown effect classes cannot silently become outer runs.
_CLASSES = {
    'guest-fixture': Execution('local','local','local'),
    'fixture': Execution('local','local','local'),
    'native-fixture': Execution('local','local','local'),
    'native-root': Execution('local','local','local'),
    'contribution': Execution('local','local','local'),
    'native-unit': Execution('unit','unit','unit'),
    'nested-install': Execution('local','create','create'),
    'live': Execution('runtime','create','delegated'),
    'live-runtime': Execution('runtime','create','delegated'),
    'setup': Execution('runtime','create','delegated'),
    'bundle': Execution('runtime','create','publisher'),
    'installed-probe': Execution('installed','existing','delegated'),
    'native-app': Execution('local','strong-public','strong-direct'),
}
EXECUTION = {(suite,mode): _CLASSES[policy(suite,mode)[1]]
             for suite,row in REGISTRY.items() for mode in row.modes}
EXECUTION[('globnotes-browser','installed-probe')] = Execution('local','strong-browser','strong-browser')


def execution_policy(suite, mode):
    try:
        return EXECUTION[(suite,mode)]
    except KeyError as error:
        raise ValueError('registry execution policy absent') from error
