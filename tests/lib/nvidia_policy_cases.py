"""Independent expected policy cases; never use the production checker as oracle."""
import os
from pathlib import Path


def exercise_policy(work, run, check, base, sections):
    root = work / 'configs'
    (root / 'grant.conf').write_text('lxc.cgroup2.devices.allow = c 195:* rwm\n')
    (root / 'nested.conf').write_text(f'lxc.include = {root}/grant.conf\n')
    (root / 'alias.conf').symlink_to('grant.conf')
    (root / 'reset.conf').write_text('lxc.cgroup2.devices.deny = a\n')
    (root / 'clear.conf').write_text('lxc.cgroup2.devices.allow =\n')
    (root / 'clear-all.conf').write_text('lxc.cgroup2 =\n')
    (root / 'cycle.conf').write_text(f'lxc.include = {root}/cycle.conf\n')
    (root / 'bad.conf').write_text('lxc.cgroup2.devices.allow = nonsense\n')
    (root / 'bad-cleared.conf').write_text('lxc.cgroup2.devices.allow = nonsense\nlxc.cgroup2.devices.allow =\n')
    (root / 'device-cleared.conf').write_text('lxc.cgroup2.devices.allow = /nonexistent-device-for-policy rw\nlxc.cgroup2.devices.allow =\n')
    (root / 'unknown-cleared.conf').write_text('lxc.cgroup2.devices.unknown = nonsense\nlxc.cgroup2 =\n')
    (root / 'unreadable.conf').write_text('lxc.cgroup2.devices.deny = a\n')
    (root / 'unreadable.conf').chmod(0)
    os.mkfifo(root / 'fifo.conf')
    for directory in ('commuting.d', 'bad-member.d', 'many-commuting.d', 'same-reset.d', 'conflicting.d', 'reset-grant.d', 'empty-ineffectual.d', 'denylist-ineffectual.d', 'stable.d'):
        (root / directory).mkdir()
    (root / 'commuting.d/z.conf').write_text('lxc.cgroup2.devices.allow = c 195:* rwm\n')
    (root / 'commuting.d/a.conf').write_text('lxc.cgroup2.devices.allow = c 509:* rwm\n')
    (root / 'alias.d').symlink_to('commuting.d')
    (root / 'bad-member.d/child.conf').mkdir()
    (root / 'conflicting.d/z.conf').write_text('lxc.cgroup2.devices.allow = a\n')
    (root / 'conflicting.d/a.conf').write_text('lxc.cgroup2.devices.deny = a\n')
    (root / 'reset-grant.d/z.conf').write_text('lxc.cgroup2.devices.deny = a\n')
    (root / 'reset-grant.d/a.conf').write_text('lxc.cgroup2.devices.allow = c 195:* rwm\n')
    (root / 'empty-ineffectual.d/reset.conf').write_text('lxc.cgroup2.devices.deny = a\n')
    (root / 'empty-ineffectual.d/ineffectual.conf').write_text('lxc.cgroup2.devices.deny = c 1:3 rwm\n')
    (root / 'denylist-ineffectual.d/reset.conf').write_text('lxc.cgroup2.devices.allow = a\n')
    (root / 'denylist-ineffectual.d/ineffectual.conf').write_text('lxc.cgroup2.devices.allow = c 1:3 rwm\n')
    for i in range(7):
        (root / f'many-commuting.d/{i}.conf').write_text(f'lxc.cgroup2.devices.allow = c 195:{i} rwm\n')
    for i in range(2):
        (root / f'same-reset.d/{i}.conf').write_text('lxc.cgroup2.devices.allow = a\n')
    (root / 'stable.d/one.conf').write_text('lxc.cgroup2.devices.allow = c 195:* rwm\n')
    cases = [
        ('reset-erases-allow', 'lxc.cgroup2.devices.allow: c 195:* rwm\nlxc.cgroup2.devices.deny: a\n', True),
        ('denylist-permitted', 'lxc.cgroup2.devices.allow: a\n', True),
        ('denylist-unrelated', 'lxc.cgroup2.devices.allow: a\nlxc.cgroup2.devices.deny: c 5:1 rwm\n', True),
        ('denylist-write', 'lxc.cgroup2.devices.allow: a\nlxc.cgroup2.devices.deny: c 195:* w\n', False),
        ('denylist-combined', 'lxc.cgroup2.devices.allow: a\nlxc.cgroup2.devices.deny: c 195:7 rw\n', False),
        ('opposite-key-denial', 'lxc.cgroup2.devices.allow: a\nlxc.cgroup2.devices.deny: c 195:* rwm\n', False),
        ('access-order-denial', 'lxc.cgroup2.devices.allow: a\nlxc.cgroup2.devices.deny: c 195:* mrw\n', False),
        ('foreign-minor-denial', 'lxc.cgroup2.devices.deny: a\nlxc.cgroup2.devices.allow: c 195:3 rwm\nlxc.cgroup2.devices.deny: c 195:3 rwm\n', False),
        ('ignored-specific-deny', 'lxc.cgroup2.devices.deny: a\nlxc.cgroup2.devices.deny: c 195:3 w\n', True),
        ('nonempty-ineffectual', 'lxc.cgroup2.devices.deny: a\nlxc.cgroup2.devices.deny: c 1:3 rwm\n', True),
        ('access-order-not-same-key', 'lxc.cgroup2.devices.deny: a\nlxc.cgroup2.devices.allow: c 195:* rwm\nlxc.cgroup2.devices.deny: c 195:* mrw\n', True),
        ('octal-major-grant', 'lxc.cgroup2.devices.allow: c 0303:* rwm\n', True),
        ('native-whitespace-grant', 'lxc.cgroup2.devices.allow: c\f195:*\trwm\n', True),
        ('octal-denial', 'lxc.cgroup2.devices.allow: a\nlxc.cgroup2.devices.deny: c 0303:07 w\n', False),
        ('invalid-octal-number', 'lxc.cgroup2.devices.allow: c 0195:* rwm\n', False),
        ('include-grant', f'lxc.include: {root}/grant.conf\n', True),
        ('nested-include', f'lxc.include: {root}/nested.conf\n', True),
        ('symlink-file-include', f'lxc.include: {root}/alias.conf\n', True),
        ('symlink-directory-include', f'lxc.include: {root}/alias.d/\n', True),
        ('directory-member-is-directory', f'lxc.include: {root}/bad-member.d/\n', False),
        ('repeated-include', f'lxc.include: {root}/grant.conf\nlxc.include: {root}/grant.conf\n', True),
        ('include-clear-is-not-undo', f'lxc.include: {root}/grant.conf\nlxc.include:\n', True),
        ('clear-controller', f'lxc.cgroup2.devices.allow: c 195:* rwm\nlxc.include: {root}/clear.conf\n', True),
        ('clear-all-controllers', f'lxc.include: {root}/clear-all.conf\n', True),
        ('invalid-controller-value-cleared', f'lxc.include: {root}/bad-cleared.conf\n', True),
        ('missing-device-rule-cleared', f'lxc.include: {root}/device-cleared.conf\n', True),
        ('unknown-controller-cleared', f'lxc.include: {root}/unknown-cleared.conf\n', True),
        ('generated-device', 'dev0: /dev/nvidia7,gid=44\n', True),
        ('generated-console', 'console: 0\n', True),
        ('device-path-rule', 'lxc.cgroup2.devices.allow: /dev/nvidia7 rwm\n', True),
        ('include-reset', f'lxc.cgroup2.devices.allow: c 195:* rwm\nlxc.include: {root}/reset.conf\n', True),
        ('commuting-directory', f'lxc.include: {root}/commuting.d/\n', True),
        ('many-commuting-directory', f'lxc.include: {root}/many-commuting.d/\n', True),
        ('same-reset-directory', f'lxc.include: {root}/same-reset.d/\n', True),
        ('conflicting-directory', f'lxc.include: {root}/conflicting.d/\n', False),
        ('reset-grant-order', f'lxc.include: {root}/reset-grant.d/\n', False),
        ('empty-versus-ineffectual-order', f'lxc.include: {root}/empty-ineffectual.d/\n', False),
        ('denylist-empty-versus-ineffectual-order', f'lxc.include: {root}/denylist-ineffectual.d/\n', True),
        ('reset-after-directory', f'lxc.include: {root}/conflicting.d/\nlxc.cgroup2.devices.deny: a\n', True),
        ('missing-include', f'lxc.include: {root}/missing.conf\n', False),
        ('optional-missing-directory', f'lxc.include: {root}/absent.d/\n', True),
        ('bad-before-reset', f'lxc.include: {root}/bad.conf\nlxc.cgroup2.devices.deny: a\n', False),
        ('include-cycle', f'lxc.include: {root}/cycle.conf\n', False),
        ('relative-include', 'lxc.include: opaque-relative.conf\n', False),
        ('special-config-file', f'lxc.include: {root}/fifo.conf\n', False),
    ]
    for major in (5, 6, 7):
        for name, inline, allowed in cases:
            label = f'policy-{major}-{name}'
            original = base + inline + sections
            facts = run(label, 'nvidia_lxc_passthrough 987654 7', text=original, major=major)
            check(label + ' decision', allowed, facts['status'] == 0)
            if not allowed:
                check(label + ' original config preserved', original, facts['after'])
            else:
                active = facts['after'].split('[pve:pending]')[0]
                check(label + ' native mount consumer', True, '/dev/nvidia7 dev/nvidia7 ' in active)
                if name.startswith('denylist-'):
                    check(label + ' no ineffective new allow', False,
                          'lxc.cgroup2.devices.allow: c 195:* rwm' in active or
                          'lxc.cgroup2.devices.allow: c 509:* rwm' in active)
                # LXC 5/6/7 cgfsng_devices_activate returns without attaching BPF
                # when the entire native list is empty, even in allowlist mode.
                if name in ('reset-erases-allow', 'include-reset', 'clear-controller',
                            'clear-all-controllers', 'invalid-controller-value-cleared',
                            'missing-device-rule-cleared', 'unknown-controller-cleared',
                            'reset-after-directory'):
                    expected = [line for line in original.splitlines() if line.startswith('lxc.cgroup2')]
                    actual = [line for line in active.splitlines() if line.startswith('lxc.cgroup2')]
                    check(label + ' empty native list keeps device policy unchanged', expected, actual)
                if name == 'nonempty-ineffectual':
                    check(label + ' nonempty native list receives missing grant', True,
                          'lxc.cgroup2.devices.allow: c 195:* rwm' in active)
                if name in ('include-grant', 'nested-include', 'repeated-include', 'include-clear-is-not-undo', 'commuting-directory', 'octal-major-grant', 'native-whitespace-grant', 'symlink-file-include', 'symlink-directory-include'):
                    check(label + ' effective inherited grant reused', False,
                          'lxc.cgroup2.devices.allow: c 195:* rwm' in active)
        # Native parse.c splits CR/LF, stops at the first NUL, and confile.c
        # trims only space/tab. cgfsng classifies every devices* prefix.
        dropin = root / 'common.conf.d/99-native-lexer.conf'
        for name, payload, allowed, appended in [
            ('cr-exact-denial', b'lxc.cgroup2.devices.allow = c 195:* rwm\rlxc.cgroup2.devices.deny = c 195:* rwm\n', False, False),
            ('nul-stops-file', b'\0\nlxc.cgroup2.devices.allow = c 195:* rwm\n', True, True),
            ('vertical-tab-not-trimmed', b'\x0blxc.cgroup2.devices.allow = c 195:* rwm\n', True, True),
            ('devices-prefix-denial', b'lxc.cgroup2.devices.allow = c 195:* rwm\nlxc.cgroup2.devices_allow = c 195:* rwm\n', False, False),
            ('form-feed-not-trimmed', b'\x0clxc.cgroup2.devices.allow = c 195:* rwm\n', True, True),
        ]:
            dropin.write_bytes(payload)
            try:
                original = base + sections
                facts = run(f'lexer-{major}-{name}', 'nvidia_lxc_passthrough 987654 7', text=original, major=major)
                check(f'lexer {major} {name} native decision', allowed, facts['status'] == 0)
                if allowed:
                    active = facts['after'].split('[pve:pending]')[0]
                    check(f'lexer {major} {name} native missing grant', appended,
                          'lxc.cgroup2.devices.allow: c 195:* rwm' in active)
                    check(f'lexer {major} {name} native mount consumer', True, '/dev/nvidia7 dev/nvidia7 ' in active)
                else:
                    check(f'lexer {major} {name} refusal preserves bytes', original, facts['after'])
            finally:
                dropin.unlink()
        for name, inline in [
            ('inline-cr', 'lxc.cgroup2.devices.allow: c 195:* rwm\rlxc.cgroup2.devices.deny = c 195:* rwm\n'),
            ('inline-nul', 'lxc.cgroup2.devices.allow: c 195:* rwm\0\n'),
            ('inline-unknown-prefix', 'lxc.cgroup2.devices_allow: c 195:* rwm\n'),
            ('inline-mount-injection', 'lxc.mount.entry: /dev/foreign2 dev/foreign2 none bind\rlxc.cgroup2.devices.deny = a\n'),
        ]:
            original = base + inline + sections
            facts = run(f'lexer-{major}-{name}', 'nvidia_lxc_passthrough 987654 7', text=original, major=major)
            check(f'lexer {major} {name} refuses projection bypass', True, facts['status'] != 0)
            check(f'lexer {major} {name} preserves original bytes', original, facts['after'])
        for name, inline, allowed in [
            ('readonly-other-minor', 'dev4: /dev/nvidia2,deny-write=1\n', False),
            ('readonly-selected-minor', 'dev5: /dev/nvidia7,deny-write=1\n', False),
            ('readonly-already-permitted', 'dev4: /dev/nvidia2,deny-write=1\nlxc.cgroup2.devices.allow: c 195:* rwm\n', True),
            ('readonly-empty-policy', 'dev4: /dev/nvidia2,deny-write=1\nlxc.cgroup2.devices.deny: a\n', True),
        ]:
            original = base + inline + sections
            facts = run(f'structured-{major}-{name}', 'nvidia_lxc_passthrough 987654 7', text=original, major=major)
            check(f'structured {major} {name} write-intent decision', allowed, facts['status'] == 0)
            if not allowed:
                check(f'structured {major} {name} unchanged on refusal', original, facts['after'])
            else:
                active = facts['after'].split('[pve:pending]')[0]
                check(f'structured {major} {name} retained devN', True, 'dev4: /dev/nvidia2,deny-write=1' in active)
                check(f'structured {major} {name} native mount consumer', True, '/dev/nvidia7 dev/nvidia7 ' in active)
                check(f'structured {major} {name} no added major grant',
                      inline.count('lxc.cgroup2.devices.allow: c 195:* rwm'),
                      active.count('lxc.cgroup2.devices.allow: c 195:* rwm'))
    for scenario, inline in [
        ('dependency-change', f'lxc.include: {root}/changing.conf\n'),
        ('membership-change', f'lxc.include: {root}/stable.d/\n'),
        ('dependency-readback-change', f'lxc.include: {root}/changing.conf\n'),
        ('policy-unreadable', f'lxc.include: {root}/unreadable.conf\n')]:
        (root / 'changing.conf').write_text('lxc.cgroup2.devices.deny = a\n')
        facts = run('policy-' + scenario, 'nvidia_lxc_passthrough 987654 7',
                    text=base + inline + sections, scenario=scenario)
        check('policy ' + scenario + ' refuses', True, facts['status'] != 0)
        if scenario != 'dependency-readback-change':
            check('policy ' + scenario + ' no publication', base + inline + sections, facts['after'])
        check('policy ' + scenario + ' no false success', False, 'configured' in facts['stdout'].lower())
    facts = run('policy-unknown-version', 'nvidia_lxc_passthrough 987654 7', major=8)
    check('uncharacterized LXC version refuses specifically', True, facts['status'] != 0)
    facts = run('policy-v2-unavailable', 'nvidia_lxc_passthrough 987654 7', scenario='v2-unavailable')
    check('unavailable v2 controller refuses before publication', (True, base + sections),
          (facts['status'] != 0, facts['after']))
