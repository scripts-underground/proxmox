"""Framework definitions for cold app fixtures; only external effects are modeled.

Do not manufacture a subset of install.func's API or detected state. The bundle
owner defers source-time bootstrap, then calls _bootstrap/detect_os itself.
"""
from pathlib import Path
import re
import sys


def install_fixture(root):
    return (Path(root) / 'misc/install.func').read_text() + r'''
# These effects belong to the fixture, not a second framework implementation.
_bootstrap() { :; }
pkg_install() { :; }
setup_lxc() { :; }
'''


def minimal_install_models(root):
    """Find ad-hoc install APIs, excluding intentional boundary-only probes.

    These exceptions execute synthetic hooks, or test the service helper directly
    with explicit init inputs. They do not promise an app framework environment.
    """
    exceptions = {
        'gpu-passthrough.test.sh', 'container-install-failure.test.sh',
        'maintenance-temp-root.test.sh', 'maintenance-build-temp.test.sh',
        'maintenance-receiving-context.test.sh', 'maintenance-addon-writer.test.sh',
        'maintenance-service-uninstall.test.sh', 'maintenance-consumers.test.sh',
        'maintenance-uninstall.test.sh', 'lib/terminal_display_fixture.py',
        'lib/batch_metadata_fixture.py', 'lib/framework_fixture.py',
        'runtime-hooks/harness-controls.sh',
    }
    found = []
    for path in sorted((Path(root) / 'tests').rglob('*')):
        if path.suffix not in ('.sh', '.py', '.func'):
            continue
        text = path.read_text()
        if 'install.func' in text and re.search(r'(?:setup_lxc|pkg_install|detect_os)\(\)\s*\{', text):
            name = path.relative_to(Path(root) / 'tests').as_posix()
            if name not in exceptions:
                found.append(name)
    return found


if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[2] == '--audit':
        unexpected = minimal_install_models(sys.argv[1])
        if unexpected:
            sys.exit('Ad-hoc app framework models: ' + ', '.join(unexpected))
    else:
        print(install_fixture(sys.argv[1]), end='')
