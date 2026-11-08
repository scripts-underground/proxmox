"""Actual provider and real native exchange; only boundary scheduling/faults modeled."""
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys

from intel_sources_fixture import apt_config, repository


BOUNDARY = r'''package GPUAtomicBoundary;
use strict;
use warnings;
if ($ENV{GPU_ATOMIC_KIND} eq 'unsupported-arch') {
    require Config;
    my %actual = %Config::Config;
    untie %Config::Config;
    %Config::Config = (%actual, archname => 'unsupported-fixture-linux');
}
sub schedule {
    my ($phase) = @_;
    my $kind = $ENV{GPU_ATOMIC_KIND};
    return if $kind =~ /^unsupported/;
    my $ready = "$ENV{GPU_ATOMIC_CONTROL}/$phase.ready";
    open(my $fh, '>', $ready) or die $!; print {$fh} "ready\n"; close($fh) or die $!;
    if ($kind eq 'reader') {
        my $ack = "$ENV{GPU_ATOMIC_CONTROL}/$phase.ack";
        my $end = time() + 8;
        while (!-f $ack) { die 'reader acknowledgement deadline' if time() >= $end; select(undef,undef,undef,0.01); }
    }
    if ($kind eq "death-$phase") { kill 9, $$; die 'kill failed'; }
    exit 74 if $kind eq "exit-$phase";
}
sub native {
    my ($number, @args) = @_;
    return CORE::syscall($number, @args);
}
BEGIN {
    *CORE::GLOBAL::rename = sub ($$) {
        my ($from, $to) = @_;
        my $live = $ENV{GPU_ATOMIC_TARGET};
        schedule('before') if $from eq $live;
        my $ok = CORE::rename($from, $to);
        schedule('after') if $ok && $from eq $live;
        return $ok;
    };
    *CORE::GLOBAL::syscall = sub {
        my @args = @_;
        return native(@args) unless @args == 6 && $args[5] == 2;
        my $live = $ENV{GPU_ATOMIC_TARGET};
        my $kind = $ENV{GPU_ATOMIC_KIND};
        if ($kind eq 'unsupported-kernel' || $kind eq 'unsupported-filesystem') {
            # Actual kernel refusals; no successful replacement is simulated.
            if ($kind eq 'unsupported-kernel') { $args[0] = 99999999; }
            else { $args[5] = 0x80000000; }
            return native(@args);
        }
        my $publication = $args[2] eq $live || $args[4] eq $live;
        schedule('before') if $publication;
        my $rc = native(@args);
        schedule('after') if $publication && $rc == 0;
        return $rc;
    };
}
1;
'''

READER = r'''import json,os,subprocess,sys,time
from pathlib import Path
control,path,config=map(Path,sys.argv[1:]); observations=[]
for phase in ('before','after'):
 end=time.monotonic()+12
 while not (control/(phase+'.ready')).exists():
  if time.monotonic()>end:raise RuntimeError('publisher boundary deadline')
  time.sleep(.01)
 rows=[]
 for _ in range(20):
  try:rows.append(dict(text=path.read_text(),inode=path.stat().st_ino))
  except OSError as error:rows.append(dict(error=type(error).__name__))
 p=subprocess.run(['/usr/bin/apt-get','--print-uris','update'],env=dict(os.environ,APT_CONFIG=str(config)),capture_output=True,text=True,timeout=4)
 observations.append(dict(phase=phase,reads=rows,apt_status=p.returncode,apt_stdout=p.stdout,apt_stderr=p.stderr))
 (control/'reader.json').write_text(json.dumps(observations,indent=2))
 (control/(phase+'.ack')).write_text('read\n')
'''


def exercise_intel_atomic(source, work, run, check):
    root = work / 'intel-atomic-cases'
    root.mkdir()
    quote = lambda value: shlex.quote(str(value))
    models = work / 'provider-models'
    for alias in (False, True):
        for kind in ('reader', 'death-before', 'death-after', 'exit-after',
                     'unsupported-kernel', 'unsupported-filesystem', 'unsupported-arch'):
            name = ('alias-' if alias else 'regular-') + kind
            case = root / name
            apt = case / 'apt'
            (apt / 'sources.list.d').mkdir(parents=True)
            uri = repository(case / 'repository', 'trixie')
            config = apt_config(case)
            path = apt / 'sources.list.d/operator.sources'
            target = path
            if alias:
                target = case / 'target.sources'
                path.symlink_to(target)
            original = f'Types: deb\nURIs: {uri}\nSuites: trixie\nComponents: main\nTrusted: yes\n'
            proposed = original.replace('Components: main\n', 'Components: main non-free\n')
            target.write_text(original)
            target.chmod(0o640)
            os.setxattr(target, 'user.fixture', b'atomic target metadata')
            before = target.stat()
            link_text = os.readlink(path) if alias else None
            (case / 'GPUAtomicBoundary.pm').write_text(BOUNDARY)
            subprocess.run(['mount', '--bind', str(apt), '/etc/apt'], check=True, timeout=10)
            reader = None
            try:
                native = subprocess.run(['/usr/bin/apt-get', 'update', '-qq', '-o', 'APT::Update::Error-Mode=any'],
                                        capture_output=True, env=dict(os.environ, APT_CONFIG=str(config)), timeout=30)
                check(name + ' native input', 0, native.returncode)
                if kind == 'reader':
                    reader = subprocess.Popen([sys.executable, '-B', '-c', READER, str(case), str(path), str(config)],
                                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                (models / 'effects').unlink(missing_ok=True)
                settings = dict(APT_CONFIG=str(config), GPU_TEST_ROOT=str(models), GPU_TEST_INSTALL_SIMULATE='1',
                                GPU_TEST_REFRESH_INDEX='1', PERL5OPT='-I' + str(case) + ' -MGPUAtomicBoundary',
                                GPU_ATOMIC_KIND=kind, GPU_ATOMIC_CONTROL=str(case),
                                GPU_ATOMIC_TARGET=str(target) if alias else '/etc/apt/sources.list.d/operator.sources')
                code = ('export ' + ' '.join(k + '=' + quote(v) for k, v in settings.items())
                        + f' PATH={quote(models / "bin")}:"$PATH"\n'
                        + f'source {quote(source / "tools/pve/gpu-intel.func")}\n'
                        + f'source {quote(models / "transport.func")}\ninstall_intel_tools_in_ct 987654')
                facts = run('intel-atomic-' + name, code)
                check(name + ' actual provider result', kind == 'reader', facts['status'] == 0)
                check(name + ' live path always recoverable after publisher', True, path.is_file())
                content = path.read_text() if path.is_file() else None
                check(name + ' live bytes are complete old or new', True, content in (original, proposed))
                saved = list(target.parent.glob('.gpu-intel-recovery.*/source'))
                survivors = [p for p in [target, *saved] if p.is_file()]
                check(name + ' original inode and bytes retained', True,
                      any(p.stat().st_ino == before.st_ino and p.read_text() == original for p in survivors))
                if alias:
                    check(name + ' alias remains exact', link_text, os.readlink(path))
                if kind == 'reader':
                    stdout, stderr = reader.communicate(timeout=15)
                    check(name + ' concurrent reader completed', (0, ''), (reader.returncode, stderr))
                    observed = json.loads((case / 'reader.json').read_bytes()) if (case / 'reader.json').exists() else []
                    check(name + ' readers saw no absent or partial path', True,
                          len(observed) == 2 and all(r.get('text') in (original, proposed) for v in observed for r in v['reads']))
                    check(name + ' native APT reader retained configured URI', True,
                          all(v['apt_status'] == 0 and str(case / 'repository') in v['apt_stdout'] for v in observed))
                    check(name + ' final candidate published', proposed, content)
                else:
                    effects = (models / 'effects').read_text() if (models / 'effects').exists() else ''
                    check(name + ' no install or false completion', (False, False),
                          ('\napt-get install ' in '\n' + effects, 'Installed Intel' in facts['stdout']))
                if kind.startswith('unsupported'):
                    check(name + ' refusal leaves original live inode unchanged', (before.st_ino, original),
                          (target.stat().st_ino, content))
                    check(name + ' precise unsupported diagnostic', True, 'exchange' in facts['stderr'].lower())
                else:
                    check(name + ' pre-exchange recovery intent visible', True,
                          bool(saved) and 'publication intent' in facts['stderr'] and str(saved[0]).replace(str(apt), '/etc/apt') in facts['stderr'])
                    if kind.endswith('after'):
                        check(name + ' displaced original survives abrupt/normal exit', [(before.st_ino, original)],
                              [(p.stat().st_ino, p.read_text()) for p in saved])
                if path.is_file():
                    check(name + ' active metadata retained', (0o640, b'atomic target metadata'.hex()),
                          (target.stat().st_mode & 0o777, os.getxattr(target, 'user.fixture').hex()))
                (case / 'facts.json').write_text(json.dumps(facts, indent=2))
            finally:
                if reader is not None and reader.poll() is None:
                    # Only this fixture's identified reader process, never a publisher or host process.
                    reader.terminate()
                    reader.communicate(timeout=5)
                subprocess.run(['mount', '--bind', str(work / 'apt'), '/etc/apt'], check=True, timeout=10)
