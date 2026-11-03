"""Audited per-request install runtime data, never an ambient environment copy.

build.func3971–4012 exports these runtime fields; core.func426 and
error_handler.func251–279 consume the session/log, install.func1074/1263/1399
consumes verbose/cache/SSH mode. APP/NSAPP/CTTYPE are otherwise baked in bundles.
Only proven safe fields below may cross the exec/attach boundary. Passwords,
keys, loader variables and creator paths are intentionally not transport fields.
"""
import re
from pathlib import Path

from test_context import require


FIELDS=frozenset(('SESSION_ID','INSTALL_LOG','VERBOSE','MODE','CTID','CTTYPE',
                  'APPLICATION','app','IPV6_METHOD','tz','CACHER','CACHER_IP','SSH_ROOT','DEV_MODE_KEEP'))


def capture(environment):
    return {key:environment[key] for key in sorted(FIELDS) if key in environment}


def validate_timezone(value):
    # build.func maps Etc/* to the literal PVE sentinel host before export.
    # Preserve it even though install.func's zone-file consumer may warn. Other
    # values must be real installed native zone data, including package aliases.
    require(0<len(value)<=255 and re.fullmatch(r'[A-Za-z0-9_+-]+(?:/[A-Za-z0-9_+-]+){0,7}',value),'receiving timezone syntax')
    if value=='host':return
    root=Path('/usr/share/zoneinfo').resolve(strict=True)
    try:
        path=(root/value).resolve(strict=True)
        require(path.is_relative_to(root) and path.is_file(),'receiving timezone zone-file scope')
        with path.open('rb') as stream:require(stream.read(4)==b'TZif','receiving timezone native data required')
    except (OSError,RuntimeError) as error:
        from test_context import AdmissionError
        raise AdmissionError('receiving timezone unavailable') from error


def validate(environment,context,ctid):
    require(type(environment) is dict and set(environment)<=FIELDS,'forbidden receiving environment field')
    require(all(type(v) is str and '\0' not in v for v in environment.values()),'receiving runtime value type')
    e=dict(environment)
    if 'SESSION_ID' in e:require(re.fullmatch('[a-f0-9]{8}',e['SESSION_ID']),'receiving session identity')
    if 'INSTALL_LOG' in e:
        require('SESSION_ID' in e and e['INSTALL_LOG']=='/root/.install-'+e['SESSION_ID']+'.log','receiving log/session path binding')
    if 'CTID' in e:require(e['CTID']==str(ctid),'receiving target binding')
    if 'CTTYPE' in e:require(e['CTTYPE']=='1','receiving unprivileged binding')
    if 'tz' in e:validate_timezone(e['tz'])
    for key,allowed in [('VERBOSE',('yes','no')),('MODE',('default',)),('IPV6_METHOD',('none',)),
                        ('CACHER',('',)),('CACHER_IP',('',)),('SSH_ROOT',('no',)),('DEV_MODE_KEEP',('true','false'))]:
        if key in e:require(e[key] in allowed,'receiving runtime field scope: '+key)
    if 'APPLICATION' in e or 'app' in e:
        source=Path(context.document['source']['path'])/'scripts/lxc'/(context.operation['suite']+'.sh')
        require(source.is_file(),'receiving application source binding absent')
        values=re.findall(r'^APP="([^"\n]+)"$',source.read_text(),re.M)
        require(len(values)==1,'receiving application source identity')
        if 'APPLICATION' in e:require(e['APPLICATION']==values[0],'receiving application binding')
        if 'app' in e:require(e['app']==values[0].lower().replace(' ',''),'receiving normalized app binding')
    return e
