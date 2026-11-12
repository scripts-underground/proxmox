"""Deterministic full-observer fixtures; run only in the assigned VM."""
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from bookorbit_memory import observe


class MemoryObserver(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='bookorbit-memory.', dir=os.environ['TMPDIR'])
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.proc = self.base / 'proc'
        self.mount = self.base / 'cgroup'
        self.leaf = self.mount / 'owned/child'
        self.leaf.mkdir(parents=True)
        (self.proc / 'self').mkdir(parents=True)
        self.pid = self.proc / '123'
        self.pid.mkdir()
        (self.pid / 'root').mkdir()
        self.birth()
        (self.pid / 'cgroup').write_text('0::/owned/child\n')
        (self.proc / 'self/mountinfo').write_text(f'35 27 0:29 / {self.mount} rw - cgroup2 cgroup2 rw\n')
        (self.mount / 'owned/memory.max').write_text('4096\n')
        (self.leaf / 'memory.max').write_text('max\n')
        s = (self.pid / 'root').stat()
        self.binding = dict(pid=123, root=[s.st_dev, s.st_ino], creation='owned-LVID-token')
        self.calls = 0

    def birth(self, value='100'):
        (self.pid / 'stat').write_text('123 (owned init) ' + ' '.join(['S'] + ['0'] * 18 + [value]))

    def owner(self):
        self.calls += 1
        return self.binding.copy()

    def run_observer(self, expected=4096):
        return observe(self.owner, expected, proc=self.proc)

    def test_old_leaf_red(self):
        with self.assertRaises(ValueError):
            int((self.leaf / 'memory.max').read_text())
        self.assertEqual(self.run_observer()['effective_memory_max'], 4096)

    def test_finite_leaf(self):
        (self.leaf / 'memory.max').write_text('2048')
        self.assertEqual(self.run_observer(2048)['effective_memory_max'], 2048)

    def test_unlimited_leaf_finite_parent(self):
        self.assertEqual(self.run_observer()['hierarchy'][0]['memory_max'], 'max')

    def test_multiple_ancestor_minimum(self):
        (self.mount / 'memory.max').write_text('1024')
        self.assertEqual(self.run_observer(1024)['effective_memory_max'], 1024)

    def test_all_max(self):
        (self.mount / 'owned/memory.max').write_text('max')
        with self.assertRaisesRegex(AssertionError, 'finite'): self.run_observer()

    def test_wrong_selected(self):
        with self.assertRaisesRegex(AssertionError, 'differs'): self.run_observer(8192)

    def test_foreign_root(self):
        self.binding['root'] = [0, 0]
        with self.assertRaisesRegex(AssertionError, 'root mismatch'): self.run_observer()

    def test_missing_controller(self):
        (self.mount / 'owned/memory.max').unlink()
        with self.assertRaises(FileNotFoundError): self.run_observer()

    def test_invalid_limits(self):
        for value in ('nan', 'inf', '-1', '0', '', '18446744073709551615'):
            with self.subTest(value=value):
                (self.leaf / 'memory.max').write_text(value)
                with self.assertRaises(AssertionError): self.run_observer()

    def test_bad_cgroup(self):
        for value in ('0::/../escape', '0::/owned/child (deleted)', '0::/missing', '1:memory:/owned', '0::/owned\n0::/other'):
            with self.subTest(value=value):
                (self.pid / 'cgroup').write_text(value)
                with self.assertRaises((AssertionError, FileNotFoundError)): self.run_observer()

    def test_symlink_escape(self):
        (self.pid / 'cgroup').write_text('0::/alias')
        (self.mount / 'alias').symlink_to(self.leaf)
        with self.assertRaisesRegex(AssertionError, 'escaping'): self.run_observer()

    def test_mount_ambiguity_and_partial(self):
        p = self.proc / 'self/mountinfo'; original = p.read_text()
        for text in ('', original + original, original.replace(' / ', ' /owned ', 1)):
            p.write_text(text)
            with self.assertRaises(AssertionError): self.run_observer()

    def changing(self, mutate):
        original = self.owner
        def owner():
            result = original()
            if self.calls == 2: mutate()
            return result
        self.owner = owner
        with self.assertRaises((AssertionError, FileNotFoundError)): self.run_observer()

    def test_pid_birth_change(self): self.changing(lambda: self.birth('101'))
    def test_reparent(self): self.changing(lambda: (self.pid / 'cgroup').write_text('0::/owned'))
    def test_root_change(self): self.changing(lambda: (self.pid / 'root').rename(self.pid / 'oldroot'))
    def test_mount_change(self): self.changing(lambda: (self.proc / 'self/mountinfo').write_text(''))
    def test_pid_change(self):
        original = self.owner
        def owner():
            result = original()
            if self.calls == 2: result['pid'] = 124
            return result
        self.owner = owner
        with self.assertRaises(FileNotFoundError): self.run_observer()
    def test_owner_change(self):
        original = self.owner
        def owner():
            result = original()
            if self.calls == 2: result['creation'] = 'foreign'
            return result
        self.owner = owner
        with self.assertRaisesRegex(AssertionError, 'changed'): self.run_observer()

    def test_unreadable(self):
        original = Path.read_text
        def read(path, *args, **kwargs):
            if path == self.leaf / 'memory.max': raise PermissionError('fixture denial')
            return original(path, *args, **kwargs)
        with patch.object(Path, 'read_text', read), self.assertRaises(PermissionError): self.run_observer()

    def test_hierarchy_change(self):
        original = Path.read_text; count = 0
        def read(path, *args, **kwargs):
            nonlocal count
            if path == self.leaf / 'memory.max':
                count += 1
                if count == 2: return '2048'
            return original(path, *args, **kwargs)
        with patch.object(Path, 'read_text', read), self.assertRaisesRegex(AssertionError, 'changed'): self.run_observer()


if __name__ == '__main__':
    unittest.main(verbosity=2)
