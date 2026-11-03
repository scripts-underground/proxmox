#!/usr/bin/python3 -B
"""Typed IPC stub bound over native commands only in the owned mount namespace."""
import json
import os
from pathlib import Path
import socket
import sys

try:
    # Locator only: the broker independently checks kernel consumer lineage,
    # source/context and the fixed receiving schema. This flag grants no effects.
    sys.path.insert(0,str(Path(os.environ['SU_TEST_SOURCE_ROOT'])/'tests/lib'))
    from receiving_context import capture
    tool=Path(sys.argv[0]).name
    environment=capture(os.environ) if tool=='lxc-attach' or (tool=='pct' and sys.argv[1:2]==['exec']) else {}
    with socket.socket(socket.AF_UNIX) as sock:
        sock.settimeout(3600)
        address = os.environ['SU_TEST_NATIVE_SOCKET']
        sock.connect('\0' + address[1:] if address.startswith('@') else address)
        sock.sendall(json.dumps(dict(tool=tool, argv=sys.argv[1:],environment=environment)).encode() + b'\n')
        with sock.makefile('rb') as stream:
            result = json.loads(stream.readline(64 * 1024 * 1024))
    sys.stdout.write(result['stdout'])
    sys.stderr.write(result['stderr'])
    raise SystemExit(result['status'])
except (OSError, ValueError, KeyError) as error:
    print('NATIVE_REFUSED:', error, file=sys.stderr)
    raise SystemExit(65)
