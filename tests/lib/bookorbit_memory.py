"""BookOrbit-only, read-only effective memory observation in the outer PVE VM."""
from pathlib import Path
import re


def observe(owner, expected, *, proc=Path('/proc')):
    """Bind owner/PID/root and two complete hierarchy snapshots; fail closed."""
    def identity(path):
        s = path.stat()
        return [s.st_dev, s.st_ino]

    def snapshot():
        binding = owner()
        pid = binding['pid']
        assert type(pid) is int and pid > 1, 'invalid owned init PID'
        p = proc / str(pid)
        birth = (p / 'stat').read_text().rsplit(') ', 1)[1].split()[19]
        assert birth.isascii() and birth.isdecimal(), 'invalid PID birth'
        root = identity(p / 'root')
        assert root == binding['root'], 'owned init root mismatch'
        groups = (p / 'cgroup').read_text().splitlines()
        assert len(groups) == 1 and groups[0].startswith('0::/'), 'ambiguous unified cgroup'
        group = groups[0][3:]
        assert group != '/' and all(v not in ('', '.', '..') for v in group[1:].split('/')), 'escaping cgroup'
        assert not any(c.isspace() for c in group) and '\\' not in group, 'deleted/invalid cgroup'
        mounts = (proc / 'self/mountinfo').read_text()
        unified = [line.split() for line in mounts.splitlines() if ' - cgroup2 ' in line]
        assert len(unified) == 1 and unified[0][3] == '/', 'missing/ambiguous/partial cgroup2 mount'
        mount = Path(re.sub(r'\\([0-7]{3})', lambda m: chr(int(m[1], 8)), unified[0][4]))
        assert mount.is_absolute() and mount.resolve(strict=True) == mount, 'invalid cgroup2 mount'
        return dict(binding=binding, birth=birth, root=root, group=group, mounts=mounts), mount

    def hierarchy(mount, group):
        path = mount / group[1:]
        rows = []
        while True:
            assert path.resolve(strict=True) == path and path.is_dir(), 'missing/escaping hierarchy'
            node = identity(path)
            assert node[0] == mount.stat().st_dev, 'foreign hierarchy mount'
            limit = path / 'memory.max'
            if path == mount and not limit.exists():
                value = None  # Kernel root cgroup alone is exempt from memory control.
            else:
                assert not limit.is_symlink(), 'symlink memory controller'
                value = limit.read_text().strip()
                assert value == 'max' or (value.isascii() and value.isdecimal() and 0 < int(value) < 2**63), 'nonfinite/invalid memory.max'
            rows.append(dict(path=str(path), identity=node, memory_max=value))
            if path == mount:
                return rows
            path = path.parent

    before, mount = snapshot()
    rows = hierarchy(mount, before['group'])
    repeated = hierarchy(mount, before['group'])
    after, final_mount = snapshot()
    assert before == after and mount == final_mount and rows == repeated, 'owned PID/root/hierarchy changed'
    finite = [int(row['memory_max']) for row in rows if row['memory_max'] not in (None, 'max')]
    assert finite, 'no proven finite effective memory limit'
    effective = min(finite)
    assert effective == expected, 'effective native RAM differs from selected allocation'
    return dict(pid=before['binding']['pid'], birth=before['birth'], root=before['root'],
                cgroup=before['group'], hierarchy=rows, effective_memory_max=effective)
