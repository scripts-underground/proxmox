"""Edit-Mind-only sampled RX guard. Not a hard byte limiter or Broker policy."""
import os
from pathlib import Path
import signal
import subprocess
import threading
import time
from contextlib import contextmanager


class TrialStopped(RuntimeError):
    pass


class Guard:
    CEILING = 16 * 1024**3
    STOP_RX = 14 * 1024**3
    INTERVAL = 0.1
    SECONDS = 3600

    def __init__(self, native, clock=time.monotonic):
        self.native, self.clock = native, clock
        self.started = clock()
        self.reason = None
        self.last = 0
        self.maximum = 0
        self.pid = None
        self.identity = None
        self.starting_at = None
        self.exit = threading.Event()
        self.thread = None
        self.stage = 'before-create'
        self.containment_lock = threading.Lock()
        self.containment_status = None
        self.retaining = False
        self.routes = threading.local()
        self.retention_process = native._process if hasattr(native, '_process') else None
        self.monitor_complete = False
        self.retention_state = 'unknown'
        self.final_status = None

    @contextmanager
    def route(self, name):
        if name not in {'normal', 'emergency', 'retention'}:
            raise TrialStopped('unknown native operation route')
        previous = getattr(self.routes, 'name', 'normal')
        self.routes.name = name
        try:
            yield
        finally:
            self.routes.name = previous

    def call(self, tool, args):
        route = getattr(self.routes, 'name', 'normal')
        if route == 'emergency':
            return self.emergency(tool, args)
        if route == 'retention':
            return self.retention_process(tool, args)
        return self.process(tool, args)

    def emergency(self, tool, args):
        command = ['/usr/bin/timeout', '2s', '/usr/sbin/ip', 'link', 'set', 'dev', 'eth0', 'down']
        expected = ['exec', str(self.native.owner.spec.ctid), '--', *self.native.receiving_argv(command)]
        if tool != 'pct' or args != expected:
            raise TrialStopped('only exact owned network containment may bypass a tripped guard')
        return subprocess.run([self.native.PROGRAMS[tool], *args], capture_output=True,
                              text=True, timeout=4, umask=0o022)

    def observe(self, received):
        previous = self.last
        self.last = received
        self.maximum = max(self.maximum, received)
        if self.reason:
            return
        if self.clock() - self.started >= self.SECONDS:
            self.reason = 'operation-deadline'
        elif received < previous:
            self.reason = 'RX-counter-reset'
        elif received >= self.STOP_RX:
            self.reason = 'RX-soft-threshold'

    def counter(self):
        n = self.native
        if n.owner.current is None:
            return 0
        if self.pid is None:
            if self.starting_at is None:
                return 0
            n.owner.checked()
            p = subprocess.run(['/usr/bin/lxc-info', '-n', str(n.owner.spec.ctid), '-pH'],
                               capture_output=True, text=True, timeout=2)
            # An owned but not yet started CT has no network traffic.
            if p.returncode or not p.stdout.strip() or int(p.stdout.strip()) <= 0:
                if self.clock()-self.starting_at < 5:
                    return 0
                raise TrialStopped('CT-init-counter-bind-deadline')
            self.pid = int(p.stdout.strip())
            proc = Path('/proc') / str(self.pid)
            self.identity = (proc.joinpath('stat').read_text().split(') ', 1)[1].split()[19],
                             os.readlink(proc/'ns/net'))
        proc = Path('/proc') / str(self.pid)
        identity = (proc.joinpath('stat').read_text().split(') ', 1)[1].split()[19],
                    os.readlink(proc/'ns/net'))
        if identity != self.identity:
            raise TrialStopped('CT-init-identity-changed')
        mac = (proc/'root/sys/class/net/eth0/address').read_text().strip()
        if mac.lower() != n.owner.spec.mac.lower():
            raise TrialStopped('CT-interface-MAC-changed')
        lines = [line.split(':', 1)[1].split() for line in (proc/'net/dev').read_text().splitlines()
                 if ':' in line and line.split(':', 1)[0].strip() == 'eth0']
        if len(lines) != 1:
            raise TrialStopped('CT-interface-counter-unavailable')
        return int(lines[0][0])

    def sample(self):
        try:
            self.observe(self.counter())
        except FileNotFoundError:
            if self.retaining:
                # Normal typed shutdown may remove the interface. The caller
                # must still prove stopped state before ending accounting.
                self.observe(self.last)
            else:
                self.reason = 'guard-observation-failed:FileNotFoundError'
        except (OSError, ValueError, subprocess.SubprocessError, TrialStopped) as error:
            self.reason = 'guard-observation-failed:' + type(error).__name__

    def check(self):
        self.sample()
        if self.reason:
            raise TrialStopped(self.reason)

    def __enter__(self):
        def watch():
            while not self.exit.wait(self.INTERVAL):
                self.sample()
                if self.reason:
                    if self.native.owner.current is not None:
                        try:self.contain()
                        except Exception as error:
                            self.native.run.record('edit-mind-containment-failure',dict(error=type(error).__name__))
        self.thread = threading.Thread(target=watch, daemon=True)
        self.thread.start()
        return self

    def finish(self, original_status):
        """The existing owner alone stops/preserves, under live RX monitoring."""
        n = self.native
        self.retaining = True
        try:
            with self.route('retention'):
                result = n.owner.finish(original_status)
            if original_status and n.owner.cleanup_status == 0:
                self.retention_state = 'stopped'
            elif not original_status and result == 75 and n.owner.pending is not None:
                self.retention_state = 'stopped'
            elif not original_status and result == 0:
                self.retention_state = 'absent'
        except Exception as error:
            n.run.record('edit-mind-retention-unknown',dict(error=type(error).__name__,original_status=original_status))
            result = original_status or 70
        if self.retention_state == 'unknown' and n.owner.current is not None:
            self.reason = self.reason or 'retention-stop-unverified'
            try:self.contain()
            except Exception as error:
                n.run.record('edit-mind-containment-failure',dict(error=type(error).__name__))
        # A late budget failure cannot turn a producer0/pending75 into a clean
        # qualification. Preserve the real owner's result separately and never
        # replace an original producer error or repeat its stop.
        self.final_status = original_status or (125 if self.reason and result == 75 else result)
        n.run.record('edit-mind-owner-finish',dict(original_status=original_status,owner_status=result,
            status=self.final_status,retention=self.retention_state,guard=self.reason,rx_max=self.maximum))
        return self.final_status

    def __exit__(self, kind, value, traceback):
        self.sample()
        self.exit.set()
        self.thread.join(timeout=10)
        if self.thread.is_alive():
            self.native.run.record('edit-mind-monitor-completion',dict(complete=False,retention='unknown'))
            if not self.final_status:raise TrialStopped('guard collector did not terminate')
            return
        self.monitor_complete = True
        self.native.run.record('edit-mind-monitor-completion',dict(complete=True,
            retention=self.retention_state,guard=self.reason,rx_max=self.maximum,status=self.final_status))

    def process(self, tool, args):
        """Replace only this app's native subprocess boundary, not typed policy."""
        self.check()
        n = self.native
        limit = min(1800, max(1, int(self.SECONDS - (self.clock() - self.started))))
        if args[0] in ('status', 'config', 'push', 'pull', 'set'):
            limit = min(limit, 30)
        if args[0] in ('start', 'create'):
            limit = min(limit, 150)
        self.stage = tool + ':' + args[0]
        if tool=='pct' and args[0]=='start':
            self.starting_at=self.clock()
        n.run.record('edit-mind-command-intent', dict(tool=tool, argv=args, seconds=limit))
        end = self.clock() + limit
        with subprocess.Popen([n.PROGRAMS[tool], *args], stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, text=True, start_new_session=True,
                              umask=0o022, env=dict(os.environ, TMPDIR=n.run.context.operation['tmpdir'])) as child:
            while True:
                try:
                    out, err = child.communicate(timeout=self.INTERVAL)
                    status = child.returncode
                    break
                except subprocess.TimeoutExpired:
                    self.sample()
                    if self.clock() >= end and not self.reason:
                        self.reason = 'command-deadline:' + self.stage
                    if not self.reason:
                        continue
                    os.killpg(child.pid, signal.SIGTERM)
                    try:
                        out, err = child.communicate(timeout=2)
                    except subprocess.TimeoutExpired:
                        os.killpg(child.pid, signal.SIGKILL)
                        out, err = child.communicate(timeout=2)
                    status = 124 if 'deadline' in self.reason else 125
                    break
        n.run.record('edit-mind-command-result', dict(tool=tool, argv=args, status=status,
                                                     stdout=out, stderr=err, guard=self.reason,
                                                     rx_max=self.maximum, stage=self.stage))
        return subprocess.CompletedProcess(args, status, out, err)

    def contain(self):
        """Failure only: typed owned-CT link down, then ordinary owner retention."""
        with self.containment_lock:
            if self.containment_status is not None:
                return self.containment_status
            self.containment_status = 70  # One attempt, including failed containment.
            n = self.native
            n.owner.checked()
            with self.route('emergency'):
                result = n.dispatch('pct', ['exec', str(n.owner.spec.ctid), '--',
                                            '/usr/bin/timeout', '2s', '/usr/sbin/ip', 'link', 'set', 'dev', 'eth0', 'down'])
                self.containment_status=result.returncode
                n.run.record('edit-mind-egress-containment', dict(status=result.returncode,
                    reason=self.reason, stage=self.stage, rx_max=self.maximum,
                    ceiling=self.CEILING, soft_threshold=self.STOP_RX, exact_hard_cap=False))
                return result.returncode
