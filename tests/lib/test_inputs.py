"""Closed prerequisite bindings for existing tests; no command/environment policy."""
import os
from pathlib import Path, PurePosixPath
import re
import stat

from test_registry import INPUT_BINDINGS
from test_context import absolute, fields, read_custody, require, safe_parents, sha, source_files


def bindings(context, required=True):
    op=context.operation
    table=INPUT_BINDINGS[op['suite'],op['mode']]
    parameters=op.get('parameters',{})
    require(type(parameters) is dict,'named inputs must be an object')
    require(all(type(k) is str for k in parameters),'named input names must be strings')
    require(not set(parameters)-set(table),'unknown named input: '+','.join(sorted(set(parameters)-set(table))))
    if required:
        for name,rule in table.items():
            require(not rule.required or name in parameters,'required input '+name+' for '+op['suite']+'/'+op['mode'])
    argv=[];env={}
    for name,rule in table.items():
        if name not in parameters:continue
        value=parameters[name]
        if rule.kind in ('file','executable','tree'):
            fields(value,'path sha256')
            path=absolute(value['path'])
            require(type(value['sha256']) is str and re.fullmatch('[a-f0-9]{64}',value['sha256']),'input hash type: '+name)
            # In-source files already have full source custody; external inputs
            # require independent root ancestry, not a caller-owned symlink.
            source=Path(context.document['source']['path'])
            safe_parents(path,root=not path.is_relative_to(source),file=True)
            require(sha(path.read_bytes())==value['sha256'],'input hash mismatch: '+name)
            if rule.kind=='executable':require(path.stat().st_mode&0o111 and os.access(path,os.X_OK),'input executable required: '+name)
            if rule.kind=='tree':
                manifest=read_custody(path);fields(manifest,'root files')
                root=absolute(manifest['root']);safe_parents(root,root=True)
                require(root!=Path('/') and any(root.is_relative_to(Path(p)) for p in (context.document['target']['workspace'],op['runs'])),'input tree path scope: '+name)
                require(type(manifest['files']) is list and manifest['files'],'input tree manifest empty: '+name)
                for row in manifest['files']:
                    fields(row,'path kind mode sha256')
                    p=PurePosixPath(row['path'])
                    require(not p.is_absolute() and str(p)==row['path'] and not set(p.parts)&{'.','..'},'input tree relative path: '+name)
                    safe_parents(root/str(p),root=True,file=True)
                    require(row['kind']=='file' and type(row['mode']) is int and 0<=row['mode']<=0o7777,'input tree kind/mode: '+name)
                    require(type(row['sha256']) is str and re.fullmatch('[a-f0-9]{64}',row['sha256']),'input tree hash: '+name)
                require(source_files(root)==manifest['files'],'input tree bytes/modes mismatch: '+name)
                path=root
            result=str(path)
        elif rule.kind=='integer':
            require(type(value) is int and 0<value<=2**63-1,'input integer range: '+name)
            if name=='large_size':require(value<=1000000,'input size range: '+name)
            result=str(value)
        elif rule.kind=='workspace':
            path=absolute(value);safe_parents(path,root=True)
            require(Path(op['tmpdir']).is_relative_to(path) and path.is_relative_to(Path(op['runs'])),'input budget workspace scope')
            result=str(path)
        else:
            require(rule.kind=='relative' and type(value) is str,'input relative path type: '+name)
            p=PurePosixPath(value)
            require(value and str(p)==value and not p.is_absolute() and not set(p.parts)&{'.','..'} and not any(c in value for c in '\x00\r\n'),'input relative path scope: '+name)
            result=value
        if rule.target=='argv':argv.append(result)
        else:env[rule.target]=result
    if parameters.get('large_size',1024)>=10000:
        require({'budget_workspace','budget_bytes'}<=set(parameters),'large_size requires budget_workspace and budget_bytes')
    return argv,env
