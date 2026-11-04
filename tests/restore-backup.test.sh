#!/usr/bin/env bash
# A failed restore keeps the backup store so the data can still be restored.
set -euo pipefail

ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
source "$ROOT/misc/tools.func"

work=$(mktemp -d)
trap 'printf "Evidence: %s\n" "$work"' EXIT
export HOME="$work/home" BACKUP_DIR="$work/store" NSAPP=restore-probe STD=''
mkdir "$HOME" "$work/data"

msg_info() { :; }
msg_ok() { :; }
msg_warn() { :; }
msg_error() { :; }

printf 'original' > "$work/data/config"
create_backup "$work/data/config"
printf 'changed by the update' > "$work/data/config"

cp() { return 1; }
rc=0
restore_backup || rc=$?
unset -f cp
[[ "$rc" != 0 ]]
[[ -f "$BACKUP_DIR/.manifest" ]]
[[ "$(< "$BACKUP_DIR/files$work/data/config")" == original ]]
printf 'PASS failed restore keeps the backup store\n'

restore_backup
[[ "$(< "$work/data/config")" == original ]]
[[ ! -e "$BACKUP_DIR" ]]
printf 'PASS successful restore returns the data and removes the store\n'

# Native filesystem outcomes; only named command failures below are injected.
# Each invocation cold-loads the public helpers, including conditional callers.
export ROOT work
python3 - << 'PY'
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
import unittest

ROOT = Path(os.environ['ROOT'])
WORK = Path(os.environ['work'])


def snapshot(path):
    """Read final bytes, modes, relative links and in-tree hardlink topology."""
    rows, inodes = {}, {}
    def visit(p, name):
        s = p.lstat()
        mode = stat.S_IMODE(s.st_mode)
        if p.is_symlink():
            rows[name] = ('link', mode, os.readlink(p))
        elif p.is_dir():
            rows[name] = ('dir', mode)
            for child in sorted(p.iterdir()):
                visit(child, name + '/' + child.name)
        else:
            rows[name] = ('file', mode, p.read_bytes())
            inodes.setdefault((s.st_dev, s.st_ino), []).append(name)
    visit(path, '.')
    return rows, sorted(sorted(names) for names in inodes.values() if len(names) > 1)


class BackupOutcomes(unittest.TestCase):
    def setUp(self):
        self.base = Path(tempfile.mkdtemp(prefix='backup-outcome.', dir=WORK))
        self.store = self.base / 'store'
        self.live = self.base / 'live data'
        self.live.mkdir(mode=0o750)
        (self.live / 'config').write_bytes(b'original\x00config\n')
        (self.live / 'config').chmod(0o640)
        (self.live / '.hidden').write_bytes(b'hidden')
        os.link(self.live / 'config', self.live / 'hardlink')
        (self.live / 'relative').symlink_to('config')
        (self.live / 'dangling').symlink_to('absent')
        self.original = snapshot(self.live)
        self.dest = Path(str(self.store) + '/files' + str(self.live))

    def call(self, body, inject=''):
        code = '''set -euo pipefail
source "$ROOT/misc/tools.func"
msg_info() { :; }; msg_ok() { :; }; msg_warn() { :; }; msg_error() { :; }
''' + inject + '\n' + body
        env = dict(os.environ, BACKUP_DIR=str(self.store), LIVE=str(self.live), DEST=str(self.dest))
        result = subprocess.run(['bash', '-c', code], env=env, capture_output=True, timeout=20)
        with (self.base / 'calls.log').open('ab') as f:
            f.write(code.encode() + b'\nSTATUS=' + str(result.returncode).encode() + b'\n' + result.stdout + result.stderr)
        return result.returncode

    def retained(self):
        return sorted(self.base.glob('store.incomplete.*/object'))

    def consume(self, path=None, expected=None):
        path = path or self.live
        expected = expected or self.original
        if path.is_dir() and not path.is_symlink():
            shutil.rmtree(path)
        else:
            path.unlink(missing_ok=True)
        path.write_bytes(b'wrong update topology')
        self.assertEqual(self.call('restore_backup'), 0)
        self.assertEqual(snapshot(path), expected)
        self.assertFalse(self.store.exists())

    def test_partial_directory_failure_retry_restores_original(self):
        fault = '''cp() {
  command mkdir -p "$DEST"
  command cp -a -- "$LIVE/config" "$DEST/config"
  builtin printf stale > "$DEST/stale"
  return 43
}'''
        failed_status = self.call('if create_backup "$LIVE"; then exit 90; fi', fault)
        partial = snapshot(self.dest)
        self.assertEqual(self.call('create_backup "$LIVE"'), 0)
        (self.live / 'config').write_bytes(b'partially updated')
        self.assertEqual(self.call('create_backup "$LIVE"'), 0)
        self.consume()
        self.assertEqual(failed_status, 43)
        self.assertEqual(len(self.retained()), 1)
        self.assertEqual(snapshot(self.retained()[0]), partial)

    def test_unmanifested_file_and_links_retry(self):
        for name in ('config', 'relative', 'dangling'):
            with self.subTest(name=name):
                path = self.live / name
                expected = snapshot(path)
                dest = Path(str(self.store) + '/files' + str(path))
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.symlink_to(self.base / 'external')
                (self.base / 'external').write_bytes(b'untouched outside target')
                self.assertEqual(self.call('create_backup "$LIVE/' + name + '"'), 0)
                self.assertEqual(snapshot(dest), expected)
                self.consume(path, expected)
                self.assertEqual((self.base / 'external').read_bytes(), b'untouched outside target')
        self.assertEqual(len(self.retained()), 3)
        self.assertTrue(all(p.is_symlink() for p in self.retained()))

    def test_create_manifest_lookup_failure_is_fatal(self):
        self.assertEqual(self.call('if create_backup "$LIVE"; then exit 90; fi', 'grep() { return 42; }'), 42)
        self.assertFalse(self.dest.exists())
        self.assertEqual(self.call('create_backup "$LIVE"'), 0)
        self.consume()

    def test_create_manifest_read_failure_retains_store(self):
        self.assertEqual(self.call('create_backup "$LIVE/config"'), 0)
        before = snapshot(self.store)
        self.assertEqual(self.call('if create_backup "$LIVE"; then exit 90; fi', 'cat() { return 44; }'), 44)
        self.assertEqual(snapshot(self.store), before)
        self.assertEqual(self.call('create_backup "$LIVE"'), 0)
        self.consume()

    def test_manifest_write_failure_retry(self):
        # Inject failed append in both old echo and checked printf versions;
        # actual copy operations still complete on disk.
        fault = '''echo() { [[ "$*" != "$LIVE" ]] || return 46; builtin echo "$@"; }
printf() { [[ "${2:-}" != "$LIVE" ]] || return 46; builtin printf "$@"; }'''
        self.assertEqual(self.call('if create_backup "$LIVE"; then exit 90; fi', fault), 46)
        copied = snapshot(self.dest)
        self.assertEqual(self.call('create_backup "$LIVE"'), 0)
        self.assertEqual(len(self.retained()), 1)
        self.consume()
        self.assertEqual(snapshot(self.retained()[0]), copied)

    def test_restore_native_manifest_read_failure(self):
        self.assertEqual(self.call('create_backup "$LIVE"'), 0)
        manifest = self.store / '.manifest'
        manifest.unlink()
        # Actual kernel EIO reading process memory at offset0, not a cat mock.
        manifest.symlink_to('/proc/self/mem')
        result = self.call('restore_backup')
        self.assertNotEqual(result, 0)
        self.assertTrue(manifest.is_symlink())
        self.assertEqual(snapshot(self.dest), self.original)
        manifest.unlink()
        manifest.write_text(str(self.live) + '\n')
        self.consume()

    def test_restore_partial_read_status_and_originals(self):
        self.assertEqual(self.call('create_backup "$LIVE"'), 0)
        before = snapshot(self.store)
        fault = 'cat() { builtin printf "%s\\n" "$LIVE"; return 48; }'
        self.assertEqual(self.call('restore_backup', fault), 48)
        self.assertEqual(snapshot(self.store), before)
        self.consume()

    def test_restore_missing_certified_object_is_not_success(self):
        self.assertEqual(self.call('create_backup "$LIVE"'), 0)
        saved = self.base / 'saved'
        self.dest.rename(saved)
        self.assertEqual(self.call('restore_backup'), 252)
        self.assertTrue((self.store / '.manifest').exists())
        saved.rename(self.dest)
        self.consume()

    def test_restore_retains_unknown_file_directory_and_dangling_link(self):
        self.assertEqual(self.call('create_backup "$LIVE"'), 0)
        unknown = self.store / 'files' / 'unknown'
        unknown.mkdir(mode=0o710)
        (unknown / '.partial').write_bytes(b'uncertified original')
        (unknown / 'dangling').symlink_to('missing')
        (self.store / '.unknown').write_bytes(b'unknown root data')
        before = snapshot(self.store)
        self.consume()
        self.assertEqual(len(self.retained()), 1)
        self.assertEqual(snapshot(self.retained()[0]), before)

    def test_restore_copy_failure_status_and_retry(self):
        self.assertEqual(self.call('create_backup "$LIVE"'), 0)
        self.assertEqual(self.call('restore_backup', 'cp() { return 47; }'), 47)
        self.assertEqual(snapshot(self.dest), self.original)
        self.assertEqual(self.call('restore_backup'), 0)
        self.assertEqual(snapshot(self.live), self.original)
        self.assertFalse(self.store.exists())

    def test_creation_failures_are_fatal_with_original_status(self):
        for command, status in (('mkdir', 51), ('touch', 52)):
            with self.subTest(command=command):
                self.assertEqual(self.call('if create_backup "$LIVE"; then exit 90; fi', command + '() { return ' + str(status) + '; }'), status)
        self.assertEqual(self.call('create_backup "$LIVE"'), 0)
        self.consume()

    def test_no_paths_missing_source_and_missing_store_are_noops(self):
        self.assertEqual(self.call('create_backup; restore_backup'), 0)
        self.assertFalse(self.store.exists())
        self.assertEqual(self.call('create_backup "$LIVE/missing"'), 0)
        self.assertEqual(self.call('restore_backup'), 0)
        self.assertFalse(self.store.exists())
        self.assertEqual(snapshot(self.live), self.original)

    def test_parent_first_changed_child_is_not_recopied(self):
        self.assertEqual(self.call('create_backup "$LIVE"'), 0)
        (self.live / 'config').write_bytes(b'changed since certification')
        self.assertEqual(self.call('create_backup "$LIVE/config" "$LIVE/relative"'), 0)
        self.consume()

    def test_child_first_changed_child_extends_parent_coverage(self):
        child = self.live / 'protected'
        child.mkdir(mode=0o710)
        (child / 'value').write_bytes(b'first certified child')
        (child / 'value').chmod(0o600)
        os.link(child / 'value', child / 'second')
        (child / 'dangling').symlink_to('missing')
        self.original = snapshot(self.live)
        self.assertEqual(self.call('create_backup "$LIVE/protected"'), 0)
        (self.dest / 'uncertified').write_bytes(b'uncertified original retained')
        (child / 'value').write_bytes(b'changed live child')
        child.chmod(0o755)
        self.assertEqual(self.call('create_backup "$LIVE"'), 0)
        self.consume()
        self.assertTrue(any((p / 'uncertified').is_file() and (p / 'uncertified').read_bytes() == b'uncertified original retained'
                            for p in self.retained()))

    def test_same_call_child_first_and_parent_first_overlap(self):
        for args in ('"$LIVE/config" "$LIVE"', '"$LIVE" "$LIVE/config"'):
            with self.subTest(args=args):
                self.assertEqual(self.call('create_backup ' + args), 0)
                self.consume()

    def test_failed_parent_extension_keeps_certified_child_for_retry(self):
        self.assertEqual(self.call('create_backup "$LIVE/config"'), 0)
        child_before = snapshot(self.dest / 'config')
        (self.live / 'config').write_bytes(b'changed before failed extension')
        # Real partial preparation followed by a named copy fault.
        fault = '''cp() {
  command cp "$@"
  return 57
}'''
        self.assertEqual(self.call('create_backup "$LIVE"', fault), 57)
        self.assertEqual(snapshot(self.dest / 'config'), child_before)
        self.assertEqual(self.call('create_backup "$LIVE"'), 0)
        self.consume()

    def test_legacy_redundant_manifest_restores_ancestor_once(self):
        self.assertEqual(self.call('create_backup "$LIVE"'), 0)
        manifest = self.store / '.manifest'
        manifest.write_text(str(self.live / 'config') + '\n' + str(self.live) + '\n' + str(self.live / 'config') + '\n')
        self.consume()

    def test_saved_symlink_ancestor_is_never_traversed(self):
        external = self.base / 'external'
        external.mkdir()
        (external / 'data').write_bytes(b'outside original')
        (self.live / 'outside').symlink_to(external, target_is_directory=True)
        self.original = snapshot(self.live)
        self.assertEqual(self.call('create_backup "$LIVE"'), 0)
        before = snapshot(self.store)
        self.assertEqual(self.call('create_backup "$LIVE/outside/data"'), 252)
        self.assertEqual(snapshot(self.store), before)
        self.assertEqual((external / 'data').read_bytes(), b'outside original')
        self.consume()

    def test_failed_extension_publication_restores_active_coverage_then_retries(self):
        self.assertEqual(self.call('create_backup "$LIVE/config"'), 0)
        original_child = snapshot(self.dest / 'config')
        (self.live / 'config').write_bytes(b'changed live before publication')
        fault = '''mv() {
  for arg in "$@"; do [[ "$arg" != *.prepare.*/object ]] || return 58; done
  command mv "$@"
}'''
        self.assertEqual(self.call('create_backup "$LIVE"', fault), 58)
        self.assertEqual(snapshot(self.dest / 'config'), original_child)
        self.assertEqual(self.call('create_backup "$LIVE"'), 0)
        self.consume()

    def test_partial_manifest_write_does_not_certify_or_poison_retry(self):
        fault = '''echo() {
  if [[ "$*" == "$LIVE" ]]; then builtin printf '%s' "${LIVE:0:12}"; return 61; fi
  builtin echo "$@"
}
printf() {
  if [[ "${2:-}" == "$LIVE" ]]; then builtin printf '%s' "${LIVE:0:12}"; return 61; fi
  builtin printf "$@"
}'''
        self.assertEqual(self.call('if create_backup "$LIVE"; then exit 90; fi', fault), 61)
        self.assertEqual((self.store / '.manifest').read_text(), '')
        self.assertEqual(snapshot(self.dest), self.original)
        self.assertEqual(self.call('create_backup "$LIVE"'), 0)
        self.consume()

    def test_incompatible_saved_ancestor_refuses_without_following_live_link(self):
        folder = self.live / 'folder'
        folder.mkdir()
        (folder / 'config').write_bytes(b'certified nested original')
        self.assertEqual(self.call('create_backup "$LIVE/folder/config"'), 0)
        before = snapshot(self.store)
        shutil.rmtree(folder)
        external = self.base / 'external'
        external.mkdir()
        (external / 'config').write_bytes(b'external data')
        folder.symlink_to(external, target_is_directory=True)
        self.assertEqual(self.call('create_backup "$LIVE"'), 252)
        self.assertEqual(snapshot(self.store), before)
        self.assertEqual((external / 'config').read_bytes(), b'external data')


result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(BackupOutcomes))
print('BACKUP_OUTCOMES cases=%s failures=%s errors=%s; native filesystem, labeled command fault injection; evidence=%s' %
      (result.testsRun, len(result.failures), len(result.errors), WORK), flush=True)
raise SystemExit(0 if result.wasSuccessful() else 1)
PY
