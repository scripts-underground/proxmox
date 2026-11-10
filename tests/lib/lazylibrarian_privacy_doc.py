"""Extract the sole canonical operator procedure, never a copied test version."""
from pathlib import Path


def procedure(root):
    text = (Path(root) / 'docs/lazylibrarian-private-config.md').read_text()
    begin = '<!-- lazylibrarian-private-config:begin -->'
    end = '<!-- lazylibrarian-private-config:end -->'
    if text.count(begin) != 1 or text.count(end) != 1:
        raise ValueError('unique privacy procedure markers required')
    block = text.split(begin)[1].split(end)[0]
    lines = block.strip().splitlines()
    if len(lines) < 4 or lines[0] != '```bash' or lines[-1] != '```' or block.count('```') != 2:
        raise ValueError('one fenced Bash privacy procedure required')
    body = '\n'.join(lines[1:-1]) + '\n'
    if not body.startswith('python3 - "${CONFIG_FILE:?') or not body.endswith('\nPY\n'):
        raise ValueError('expected explicit-path Python procedure')
    return body
