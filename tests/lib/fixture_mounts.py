"""Private metadata fixture projection with object and nested-mount readback."""
import json
from pathlib import Path
import re
import subprocess
import sys

MANAGED = Path('/var/lib/scripts-underground')


def identity(path):
    s = Path(path).stat()
    return [s.st_dev, s.st_ino]


def mount_graph(paths):
    # mountinfo's documented octal escapes, not SOURCE bracket stripping.
    def decode(value):
        return re.sub(r'\\([0-7]{3})', lambda m: chr(int(m[1], 8)), value)
    rows = []
    for line in Path('/proc/self/mountinfo').read_text().splitlines():
        left, right = line.split(' - ', 1)
        fields, filesystem = left.split(), right.split()
        target = Path(decode(fields[4]))
        if any(p.is_relative_to(target) or target.is_relative_to(p) for p in paths):
            rows.append(dict(target=str(target), root=decode(fields[3]), device=fields[2],
                             fstype=filesystem[0], source=decode(filesystem[1])))
    return sorted(rows, key=lambda r: (r['target'], r['root'], r['device']))


def preserve(metadata, receipt, paths, whole=False):
    metadata, receipt = Path(metadata), Path(receipt)
    paths = [Path(p).resolve(strict=True) for p in paths]
    if not paths or not metadata.is_dir() or any(p == MANAGED for p in paths):
        raise ValueError('unsafe fixture projection')
    # Snapshot before cloning: staging mounts are outputs, never required input.
    graph = mount_graph(paths)
    # Pin each originally mounted subtree as well as the requested endpoints.
    # A foreign overmount must not pass merely because the old row is still
    # present underneath it in mountinfo.
    objects = {str(p): identity(p) for p in [*paths, *(Path(row['target']) for row in graph)]}
    snapshot = dict(objects=objects, mounts=graph, paths=[str(p) for p in paths])
    if whole:
        if any(metadata.iterdir()):
            raise ValueError('fixture projection target not empty')
        subprocess.run(['/bin/mount', '--rbind', str(MANAGED), str(metadata)], check=True, timeout=20)
    else:
        children = sorted({p.relative_to(MANAGED).parts[0] for p in paths if p.is_relative_to(MANAGED)})
        for child in children:
            target = metadata/child
            target.mkdir()  # exclusive staging, never adopt a preexisting mount
            subprocess.run(['/bin/mount', '--rbind', str(MANAGED/child), str(target)], check=True, timeout=20)
    # Only the mounts actually created for this projection may be added to the
    # original input graph. Translate their staging paths to consumer paths.
    staging = [row for row in mount_graph([metadata]) if Path(row['target']).is_relative_to(metadata)]
    snapshot['projection_mounts'] = staging + [dict(row, target=str(MANAGED/Path(row['target']).relative_to(metadata)))
                                              for row in staging]
    with receipt.open('x') as stream:
        json.dump(snapshot, stream, sort_keys=True)


def verify(receipt):
    snapshot = json.loads(Path(receipt).read_text())
    paths = [Path(p) for p in snapshot['paths']]
    if any(identity(p) != expected for p, expected in snapshot['objects'].items()):
        raise ValueError('fixture source/TMPDIR object changed')
    current = mount_graph(paths)
    if any(row not in current for row in snapshot['mounts']):
        raise ValueError('fixture source/TMPDIR nested mount graph changed')
    allowed = snapshot['mounts'] + snapshot['projection_mounts']
    if any(row not in allowed and any(Path(row['target']).is_relative_to(p) for p in paths) for row in current):
        raise ValueError('fixture source/TMPDIR unexpected nested mount added')


if __name__ == '__main__':
    try:
        if sys.argv[1] in ('preserve', 'preserve-root'):
            preserve(sys.argv[2], sys.argv[3], sys.argv[4:], whole=sys.argv[1] == 'preserve-root')
        elif sys.argv[1] == 'verify' and len(sys.argv) == 3:
            verify(sys.argv[2])
        else:
            raise ValueError('unknown fixture projection operation')
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print('Cannot preserve source/temp paths under managed metadata: '+str(error), file=sys.stderr)
        raise SystemExit(65)
