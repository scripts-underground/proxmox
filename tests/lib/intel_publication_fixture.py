"""Real Intel provider; native APT plus modeled primitive publication boundaries."""
import json
import os
from pathlib import Path
import shlex
import stat
import subprocess

from intel_sources_fixture import apt_config, repository


BOUNDARY = r'''package GPUAptBoundary;
use strict;
use warnings;
our ($done, $held);
sub edit {
    my ($path) = @_;
    open(my $fh, '>>', $path) or die $!;
    print {$fh} "# late operator edit\n" or die $!;
    close($fh) or die $!;
}
sub mark {
    open(my $fh, '>', $ENV{GPU_BOUNDARY_MARK}) or die $!;
    print {$fh} "actual primitive reached\n"; close($fh) or die $!;
}
if ($ENV{GPU_BOUNDARY_KIND} eq 'held-inode') {
    open($held, '>>', $ENV{GPU_BOUNDARY_TARGET}) or die $!;
}
sub native {
    my ($number, @args) = @_;
    return CORE::syscall($number, @args);
}
BEGIN {
    *CORE::GLOBAL::syscall = sub {
        my @args = @_;
        my $target = $ENV{GPU_BOUNDARY_TARGET};
        my $publication = @args == 6 && $args[5] == 2 && ($args[2] eq $target || $args[4] eq $target);
        if ($publication && !$done) {
            my $kind = $ENV{GPU_BOUNDARY_KIND};
            if ($kind eq 'late-inplace') { edit($target); $done = 1; mark(); }
            if ($kind eq 'late-replace' || $kind eq 'late-create') {
                my $writer = "$target.writer";
                edit($writer); CORE::rename($writer, $target) or die $!; $done = 1; mark();
            }
        }
        my $rc = native(@args);
        if ($publication && $rc == 0 && !$done && $ENV{GPU_BOUNDARY_KIND} eq 'held-inode') {
            print {$held} "# late operator edit\n"; close($held); $done = 1; mark();
        }
        return $rc;
    };
    *CORE::GLOBAL::rename = sub ($$) {
        my ($from, $to) = @_;
        my $target = $ENV{GPU_BOUNDARY_TARGET};
        if (!$done && ($from eq $target || $to eq $target)) {
            my $kind = $ENV{GPU_BOUNDARY_KIND};
            if ($kind eq 'late-inplace') { edit($target); $done = 1; mark(); }
            if ($kind eq 'late-replace') {
                unlink($target) or die $!; edit($target); $done = 1; mark();
            }
        }
        my $ok = CORE::rename($from, $to);
        if ($ok && !$done && $to eq $target && $ENV{GPU_BOUNDARY_KIND} eq 'held-inode') {
            print {$held} "# late operator edit\n"; close($held); $done = 1; mark();
        }
        return $ok;
    };
    *CORE::GLOBAL::link = sub ($$) {
        my ($from, $to) = @_;
        if (!$done && $to eq $ENV{GPU_BOUNDARY_TARGET}) {
            if ($ENV{GPU_BOUNDARY_KIND} eq 'late-create') { edit($to); $done = 1; mark(); }
            my $ok = CORE::link($from, $to);
            if ($ok && $ENV{GPU_BOUNDARY_KIND} eq 'held-inode') {
                print {$held} "# late operator edit\n"; close($held); $done = 1; mark();
            }
            return $ok;
        }
        return CORE::link($from, $to);
    };
}
1;
'''


def exercise_intel_publication(source, work, run, check):
    root = work / 'intel-publication-cases'
    root.mkdir()
    quote = lambda value: shlex.quote(str(value))
    models = work / 'provider-models'
    for kind in ('alias-noop', 'alias-edit', 'alias-chain', 'alias-unreadable', 'alias-duplicate',
                 'hardlink-noop', 'hardlink-edit',
                 'fifo', 'alias-fifo', 'alias-device', 'alias-missing',
                 'late-inplace', 'late-replace', 'late-create', 'held-inode', 'second-update'):
        case = root / kind
        apt = case / 'apt'
        (apt / 'sources.list.d').mkdir(parents=True)
        uri = repository(case / 'repository', 'trixie')
        config = apt_config(case)
        path = apt / 'sources.list.d/operator.sources'
        text = (f'Types: deb\nURIs: {uri}\nSuites: trixie\nComponents: main'
                + (' non-free' if kind.endswith('noop') else '') + '\nTrusted: yes\n')
        target = path
        if kind.startswith('alias-') or kind.startswith('hardlink-'):
            target = case / 'targets/native.sources'
            target.parent.mkdir()
        target.write_text(text)
        target.chmod(0o640)
        os.chown(target, 1234, 1234)
        os.setxattr(target, 'user.fixture', b'operator ownership')
        if kind.startswith('alias-'):
            if kind == 'alias-chain':
                intermediate = case / 'targets/chain'
                intermediate.symlink_to('native.sources')
                path.symlink_to(intermediate)
            else:
                path.symlink_to(target)
        elif kind.startswith('hardlink-'):
            os.link(target, path)
        if kind == 'alias-duplicate':
            (apt / 'sources.list.d/duplicate.sources').symlink_to(target)
        original = target.stat()
        alias = path.lstat()
        special = kind in ('fifo', 'alias-fifo', 'alias-device', 'alias-missing')
        if special:
            target.unlink()
            if kind.endswith('fifo'):
                os.mkfifo(target, 0o600)
            elif kind == 'alias-device':
                os.mknod(target, stat.S_IFCHR | 0o600, os.makedev(1, 3))
        subprocess.run(['mount', '--bind', str(apt), '/etc/apt'], check=True, timeout=10)
        try:
            env = dict(os.environ, APT_CONFIG=str(config), LC_ALL='C')
            if not special:
                native = subprocess.run(['/usr/bin/apt-get', 'update', '-qq', '-o', 'APT::Update::Error-Mode=any'],
                                        capture_output=True, env=env, timeout=30)
                check(kind + ' native APT accepts input', 0, native.returncode)
            settings = dict(APT_CONFIG=str(config), GPU_TEST_ROOT=str(models),
                            GPU_TEST_INSTALL_SIMULATE='1', GPU_TEST_REFRESH_INDEX='1')
            if kind.startswith('late-') or kind == 'held-inode':
                (case / 'GPUAptBoundary.pm').write_text(BOUNDARY)
                settings.update(PERL5OPT='-I' + str(case) + ' -MGPUAptBoundary',
                                GPU_BOUNDARY_KIND=kind, GPU_BOUNDARY_MARK=str(case / 'boundary'),
                                GPU_BOUNDARY_TARGET='/etc/apt/sources.list.d/operator.sources')
            if kind == 'second-update':
                settings['GPU_TEST_SECOND_UPDATE_TRANSIENT'] = str(case / 'refresh-count')
            if kind == 'alias-unreadable':
                target.chmod(0)
            effects = models / 'effects'
            effects.unlink(missing_ok=True)
            code = ('export ' + ' '.join(key + '=' + quote(value) for key, value in settings.items())
                    + f' PATH={quote(models / "bin")}:"$PATH"\n'
                    + f'source {quote(source / "tools/pve/gpu-intel.func")}\n'
                    + f'source {quote(models / "transport.func")}\ninstall_intel_tools_in_ct 987654')
            if kind == 'alias-unreadable':
                code = '/usr/bin/setpriv --bounding-set=-dac_override,-dac_read_search /bin/bash -c ' + quote(code)
            facts = run('intel-publication-' + kind, code)
            success = kind in ('alias-noop', 'alias-edit', 'alias-chain', 'hardlink-noop')
            check(kind + ' actual provider outcome', success, facts['status'] == 0)
            calls = effects.read_text() if effects.exists() else ''
            if not success:
                check(kind + ' no package install after failure', False, '\napt-get install ' in '\n' + calls)
                check(kind + ' no false Installed claim', False, 'Installed Intel' in facts['stdout'])
            if kind.startswith('alias-'):
                check(kind + ' alias inode/text retained', (alias.st_ino, alias.st_mtime_ns),
                      (path.lstat().st_ino, path.lstat().st_mtime_ns))
            if kind in ('alias-unreadable', 'alias-duplicate', 'hardlink-edit'):
                check(kind + ' refused target bytes retained', text, target.read_text())
                message = {'alias-unreadable': 'Cannot read pinned APT source',
                           'alias-duplicate': 'multiply aliased', 'hardlink-edit': 'hardlinked'}[kind]
                check(kind + ' precise refusal diagnosed', True, message in facts['stderr'])
            if success:
                check(kind + ' native target components', True, 'main non-free' in target.read_text())
                check(kind + ' target metadata retained', (0o640, 1234, 1234, b'operator ownership'.hex()),
                      (target.stat().st_mode & 0o777, target.stat().st_uid, target.stat().st_gid,
                       os.getxattr(target, 'user.fixture').hex()))
                if kind.endswith('noop'):
                    check(kind + ' no-edit inode/bytes retained', (original.st_ino, text),
                          (target.stat().st_ino, target.read_text()))
                else:
                    saved = list(target.parent.glob('.gpu-intel-recovery.*/source'))
                    check(kind + ' original inode retained recoverably', [(original.st_ino, text)],
                          [(p.stat().st_ino, p.read_text()) for p in saved])
                    check(kind + ' exact recovery path diagnosed', True,
                          bool(saved) and str(saved[0]) in facts['stderr'])
            if kind.startswith('late-') or kind == 'held-inode':
                check(kind + ' actual late primitive executed', True, (case / 'boundary').exists())
                saved = list(apt.rglob('.gpu-intel-recovery.*/source'))
                survivors = [p for p in [path, *saved] if p.is_file()]
                check(kind + ' late operator bytes retained', True,
                      any('# late operator edit\n' in p.read_text() for p in survivors))
                check(kind + ' precise recoverable uncertainty diagnosed', True,
                      'recovery' in facts['stderr'].lower() and str(saved[0]).replace(str(apt), '/etc/apt') in facts['stderr'] if saved else False)
            if kind == 'second-update':
                check(kind + ' first refresh then second failure', ('2', 100),
                      ((case / 'refresh-count').read_text(), facts['status']))
            (case / 'facts.json').write_text(json.dumps(dict(facts, effects=calls), indent=2))
        finally:
            subprocess.run(['mount', '--bind', str(work / 'apt'), '/etc/apt'], check=True, timeout=10)
