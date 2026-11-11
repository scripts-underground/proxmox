"""Cold full app hook, real deployment and pending ownership; external producers modeled."""
import hashlib
import ast
import json
import os
import pwd
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
from urllib.parse import quote

ROOT = Path(__file__).resolve().parents[2]
BASELINE = Path(os.environ['EDIT_MIND_BASELINE'])
REFERENCE = Path(os.environ['EDIT_MIND_REFERENCE'])
WORK = Path(tempfile.mkdtemp(prefix='edit-mind-', dir=os.environ['TMPDIR']))
print('EDIT_MIND_EVIDENCE', WORK, flush=True)
assert (REFERENCE/'packages/prisma/schema.prisma').is_file()
checks = 0


def run(argv, **kwargs):
    return subprocess.run(argv, capture_output=True, text=True, timeout=65, **kwargs)


def case(subject, label, fault='none', scenario='default'):
    c = WORK/label
    for name in ('home', 'stage', 'state', 'tmp', 'sbin', 'archive', 'opt/edit-mind/media',
                 'opt/edit-mind/ml-models', 'opt/edit-mind/.data', 'opt/edit-mind/apps/web',
                 'bin', 'etc/systemd/system', 'media'):
        (c/name).mkdir(parents=True, exist_ok=True)
    app = c/'opt/edit-mind'
    (app/'media/film.mp4').write_text('owned media')
    (app/'ml-models/model').write_text('owned model')
    (app/'.env').write_text('HOST_MEDIA_PATH='+str(app/'media')+'\nSESSION_SECRET=unchanged\n')
    (app/'.env.system').write_text('DATABASE_URL=postgresql://fixture:secret@127.0.0.1:55439/fixture?sslmode=disable\n')
    (app/'apps/web/.env.production').write_text('VITE_BACKGROUND_JOBS_URL=http://fixture:4000\n')
    (app/'source.txt').write_text('old source')
    (app/'apps/web/server.cjs').write_text('module.exports = { release: "old" };\n')
    (c/'home/.edit-mind').write_text('1.0\n')
    (c/'archive/release').mkdir()
    (c/'archive/release/source.txt').write_text('new source')
    (c/'archive/release/apps/web').mkdir(parents=True)
    (c/'archive/release/apps/web/server.cjs').write_text('module.exports = { release: "new" };\n')
    for rel in ('.env', '.env.system', '.data/incoming', '.venv/incoming', 'media/film.mp4',
                'ml-models/model', 'apps/web/.env.production'):
        incoming = c/'archive/release'/rel
        incoming.parent.mkdir(parents=True, exist_ok=True)
        incoming.write_text('incoming collision must not replace owned state')
    (app/'.data/progress').write_text('job progress')
    (app/'.venv').mkdir()
    (app/'.venv/state').write_text('persistent interpreter environment')
    (app/'.locations.json').write_text('locations')
    (c/'opt/edit-mind.env.bak').write_text('unowned legacy backup')
    (c/'opt/edit-mind.env.system.bak').write_text('unowned legacy system backup')
    for p in (app/'media/film.mp4', app/'ml-models/model'):
        p.chmod(0o640)
    os.chown(app/'media/film.mp4',12345,23456)
    (app/'media').chmod(0o750)
    (app/'.env').chmod(0o600)
    (app/'.env.system').chmod(0o600)
    for name, command in {
        'web': '/usr/bin/pnpm --filter web start --host 0.0.0.0 --port 3745',
        'jobs': '/usr/bin/pnpm --filter background-jobs start',
        'ml': str(app/'.venv/bin/python')+' '+str(app/'python/main.py')+' --host 0.0.0.0 --port 8765',
        'chroma': str(app/'.venv/bin/chroma')+' run --host 127.0.0.1 --port 8000 --path '+str(app/'.data/chroma'),
    }.items():
        body = '[Unit]\nDescription=Edit-Mind\nAfter=network.target\n[Service]\nType=simple\nUser=root\nWorkingDirectory='+str(app)+'\n'
        if name != 'chroma':
            body += 'EnvironmentFile='+str(app/'.env')+'\nEnvironmentFile='+str(app/'.env.system')+'\n'
        if name == 'ml':
            for key, sub in [('YOLO_CONFIG_DIR','ultralytics'),('DEEPFACE_HOME','deepface'),
                             ('TRANSCRIPTION_MODEL_CACHE','whisper'),('TORCH_HOME','torch'),('HF_HOME','huggingface')]:
                body += 'Environment='+key+'='+str(app/'ml-models'/sub)+'\n'
        (c/'etc/systemd/system'/('edit-mind-'+name+'.service')).write_text(body+'ExecStart='+command+'\nRestart=on-failure\n')
    (c/'bin/systemctl').write_text('''#!/usr/bin/env python3
import os,sys,json
from pathlib import Path
c=Path(os.environ['CASE_ROOT'])
if sys.argv[1]=='show':
 print('FragmentPath='+str(c/'etc/systemd/system'/sys.argv[2]))
 drop=c/'dropin.conf'
 print('DropInPaths='+str(drop) if drop.exists() and sys.argv[2]=='edit-mind-web.service' else 'DropInPaths=')
 print('NeedDaemonReload=no')
elif sys.argv[1]=='show-environment':
 if (c/'manager-native').exists():
  os.execv('/usr/bin/systemctl',['/usr/bin/systemctl',*sys.argv[1:]])
 raw=(c/'manager.json').read_text() if (c/'manager.json').exists() else '{}'
 if '--output=json' in sys.argv:print(raw)
 else:
  for key,value in json.loads(raw).items():print(key+'='+str(value))
else:
 with (c/'python-services').open('a') as f:f.write(' '.join(sys.argv[1:])+'\\n')
''')
    (c/'bin/psql').write_text('''#!/usr/bin/env python3
import os,sys,json
sys.stdin.read()
assert os.environ['PGDATABASE']=='fixture' and os.environ['PGUSER']=='fixture'
assert os.environ['PGSSLMODE']=='disable'
print('[]')
''')
    (c/'bin/pnpm').write_text('''#!/usr/bin/env python3
import os,sys
from pathlib import Path
with (Path(os.environ['CASE_ROOT'])/'exec-builds').open('a') as f:f.write(' '.join(sys.argv[1:])+'\\n')
''')
    for p in (c/'bin').iterdir():
        p.chmod(0o755)
    if scenario.startswith('fresh-'):
        no_python = scenario.endswith('no-python')
        if scenario == 'fresh-conflict-no-python':
            (c/'media/videos').mkdir()
            (c/'media/videos/witness').write_text('different owned media')
        elif scenario == 'fresh-compatible-no-python':
            (c/'media/videos').symlink_to(app/'media')
        elif scenario == 'fresh-dangling-no-python':
            (c/'media/videos').symlink_to(c/'not-present')
        elif scenario == 'fresh-alias-conflict-no-python':
            (c/'other-media').mkdir()
            (c/'other-media/witness').write_text('different owned media')
            (c/'media/videos').symlink_to(c/'other-media')
        elif scenario == 'fresh-file-no-python':
            (c/'media/videos').write_text('owned non-directory')
        def fresh_fact(p):
            s=p.lstat()
            return (s.st_ino,s.st_mode,s.st_uid,s.st_gid,os.readlink(p) if p.is_symlink() else p.read_bytes())
        fresh_owned = {p:fresh_fact(p) for p in [app/'media/film.mp4',*list((c/'media').rglob('*')),
                       *list((c/'other-media').rglob('*'))] if p.is_symlink() or p.is_file()}
        source = subject.read_text()
        install = re.search(r'^function install_script\(\) \{\n.*?^\}', source, re.M | re.S).group()
        install = install.replace('/opt/edit-mind', str(app)).replace('/media/videos', str(c/'media/videos')).replace('/etc/systemd/system', str(c/'etc/systemd/system'))
        setup = '''set -euo pipefail
STD='' LOCAL_IP=127.0.0.1 PG_DB_USER=fixture PG_DB_NAME=fixture PG_DB_PASS=secret
msg_info() { :; }; msg_ok() { :; }; apt() { :; }; setup_ffmpeg() { :; }
setup_postgresql() { :; }; setup_postgresql_db() { PG_DB_USER=fixture PG_DB_PASS=secret PG_DB_NAME=fixture; }
setup_nodejs() { :; }; setup_uv() { :; }; corepack() { :; }; uv() { :; }; pnpm() { :; }
fetch_and_deploy_gh_release() { :; }; systemctl() { :; }
'''
        native_prefix = ''
        if scenario == 'fresh-native-baseline':
            tree = ast.parse((ROOT/'tests/lib/edit_mind_native.py').read_text())
            generator = next(n.value.value for n in ast.walk(tree) if isinstance(n,ast.Assign) and
                             any(isinstance(t,ast.Name) and t.id=='generate' for t in n.targets))
            native_prefix = re.search(r"_write_bundle install install_script .*? '([^']*)' setting_up_container",generator)[1]
            identity_model = 'setup_postgresql_db() { PG_DB_USER=fixture PG_DB_PASS=secret PG_DB_NAME=fixture; }'
            assert setup.count(identity_model) == 1
            setup = setup.replace(identity_model,'')
            setup += chr(10)+'sudo() { : > "'+str(c/'sql-produced')+'"; };'+chr(10)
        if no_python:
            path = c/'fresh-bin'
            path.mkdir()
            for executable in Path('/usr/bin').iterdir():
                if executable.is_file() and not executable.name.startswith('python'):
                    (path/executable.name).symlink_to(executable)
            setup += '''
if command -v python3 >/dev/null; then exit 99; fi
printf 'FRESH_NO_PYTHON_CONFIRMED\\n'
apt() { printf provisioned > APT_MARKER; ln -s /usr/bin/python3 PYTHON_LINK; }
fetch_and_deploy_gh_release() { printf downloaded > DOWNLOAD_MARKER; }
'''.replace('APT_MARKER',str(c/'fresh-apt')).replace('PYTHON_LINK',str(path/'python3')).replace('DOWNLOAD_MARKER',str(c/'fresh-download'))
        fresh_stage = c/'fresh-stage'
        fresh_stage.mkdir()
        for name in ('core.func','error_handler.func','tools.func'):
            shutil.copyfile(ROOT/'misc'/name,fresh_stage/name)
        (fresh_stage/'install.func').write_text('pkg_install() { :; }; setup_lxc() { :; }\n')
        (c/'fresh-models.sh').write_text(setup)
        (fresh_stage/'github.func').write_text('clone_and_deploy_gh_commit() { :; }\nsource '+str(c/'fresh-models.sh')+'\n')
        (c/'install-hook.sh').write_text(install+'\n')
        emit = '''set -euo pipefail
source "$ROOT/misc/bundle.func"
source "$CASE_ROOT/install-hook.sh"
APP=Edit-Mind NSAPP=edit-mind REPO_BASE=https://fixture.invalid
var_lxc_tmpdir="$CASE_ROOT/tmp"
_write_bundle install install_script "$CASE_ROOT/fresh-stage" 'install_script' > "$CASE_ROOT/sbin/install"
'''
        if native_prefix:
            emit = emit.replace("'install_script' >",repr(native_prefix)+" 'install_script' >")
        emitted = run(['bash','-c',emit],env=dict(os.environ,ROOT=str(ROOT),CASE_ROOT=str(c)))
        assert emitted.returncode == 0, (emitted.stdout,emitted.stderr)
        if no_python:
            p = c/'sbin/install'
            fixed = 'export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"'
            assert p.read_text().count(fixed) == 1
            p.write_text(p.read_text().replace(fixed,'export PATH="'+str(path)+'"'))
        shutil.copyfile(c/'sbin/install',c/'install-frozen.sh')
        result = run(['bash',str(c/'sbin/install')],env=dict(PATH=os.environ['PATH'],HOME=str(c/'home'),TMPDIR=str(c/'tmp'),
                     VERBOSE='yes',BUILD_LOG=str(c/'install-active.log'),DEBUG_LOGFILE=str(c/'install-error.log')))
        (c/'install-stdout').write_text(result.stdout)
        (c/'install-stderr').write_text(result.stderr)
        if scenario == 'fresh-native-baseline':
            return dict(status=result.returncode,real_pg_helper=True,sql_produced=(c/'sql-produced').exists(),
                        normal_application_credential=(c/'home/edit-mind.creds').is_file(),case=str(c))
        if no_python:
            assert 'FRESH_NO_PYTHON_CONFIRMED' in result.stdout, (result.stdout,result.stderr)
            return dict(status=result.returncode,apt=(c/'fresh-apt').exists(),downloaded=(c/'fresh-download').exists(),
                        media=(c/'media/videos').is_dir() and (c/'media/videos').resolve() == (app/'media').resolve(),
                        conflict=(c/'media/videos/witness').is_file(),case=str(c),
                        untouched=all(os.path.lexists(p) and fresh_fact(p)==fact for p,fact in fresh_owned.items()))
        assert result.returncode == 0, (result.stdout, result.stderr)
        # Isolated model endpoint only; all other env/unit bytes are actual installer output.
        p = app/'.env.system'
        p.write_text(p.read_text().replace(':5432/fixture', ':55439/fixture?sslmode=disable'))
    db_paths = []
    with (app/'.env.system').open('a') as f:
        f.write('PROCESSED_VIDEOS_DIR='+str(app/'.data')+'\nTHUMBNAILS_PATH='+str(app/'.data/.thumbnails')+'\n')
    if scenario.startswith('manager-'):
        manager={'TMPDIR':str(c/'tmp')}
        if scenario=='manager-quoted':manager['TMPDIR']=str(c/'tmp literal "quotes"')
        elif scenario=='manager-production-temp':manager['TMPDIR']='/tmp'
        elif scenario=='manager-reset':
            with (c/'etc/systemd/system/edit-mind-web.service').open('a') as f:f.write('Environment=TMPDIR='+str(c/'discarded')+'\nEnvironment=\n')
        elif scenario=='manager-unit':
            with (c/'etc/systemd/system/edit-mind-ml.service').open('a') as f:f.write('Environment="TMPDIR='+str(c/'unit tmp')+'"'+chr(10))
            with (app/'.env.system').open('a') as f:f.write('TMPDIR="'+str(c/'file tmp')+'"'+chr(10))
        elif scenario=='manager-race':(c/'manager-race').touch()
        elif scenario=='manager-native':(c/'manager-native').touch()
        elif scenario.startswith('manager-field-'):manager[scenario.removeprefix('manager-field-')]='uncharacterized'
        elif scenario=='manager-app':manager['TMPDIR']=str(app/'apps/web/build')
        elif scenario=='manager-relative':manager['TMPDIR']='relative'
        elif scenario=='manager-empty':manager['TMPDIR']=''
        elif scenario=='manager-alias':
            (c/'temporary-alias').symlink_to(app/'apps/web/build');manager['TMPDIR']=str(c/'temporary-alias')
        (c/'manager.json').write_text(json.dumps(manager) if scenario!='manager-malformed' else '["TMPDIR=ambiguous"]')
    elif scenario == 'custom':
        with (app/'.env.system').open('a') as f:
            for key, value in [('FACES_DIR', 'custom faces'), ('UNKNOWN_FACES_DIR', 'unknown faces'),
                               ('STITCHED_VIDEOS_DIR', 'stitch outputs'), ('EXPORTS_DIR', 'exports'),
                               ('XENOVA_MODEL_CACHE_DIR', 'node models'),
                               ('TRANSCRIPTION_MODEL_CACHE', 'python models'),
                               ('HF_HOME', str(app/'alias models'))]:
                f.write(key+'='+value+'\n')
        for cwd in (app/'apps/web', app/'apps/background-jobs', app):
            locations = ('custom faces', 'unknown faces', 'python models', '.locations.json') if cwd == app else (
                'custom faces', 'unknown faces', 'stitch outputs', 'exports', 'node models', '.locations.json')
            for rel in locations:
                p = cwd/rel
                if p.suffix == '.json':
                    p.parent.mkdir(parents=True, exist_ok=True)
                    p.write_text('package locations')
                else:
                    p.mkdir(parents=True, exist_ok=True)
                    (p/'sentinel').write_text('owned '+str(p))
        (app/'model store').mkdir()
        (app/'model store/model').write_text('in-tree alias referent')
        (app/'alias models').symlink_to('model store')
        (c/'external').mkdir()
        (c/'external/witness').write_text('external witness')
        (app/'external alias').symlink_to(c/'external')
        with (app/'.env.system').open('a') as f:
            f.write('KNOWN_FACES_FILE='+str(app/'external alias/witness')+'\n')
        for rel in ('db only/folder/film.mp4', 'detached/job.mp4', 'detached/thumb.jpg',
                    'detached/export.mp4', 'detached/chat.mp4'):
            p = app/rel
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text('database-only '+rel)
            db_paths.append(str(p.parent) if 'folder/' in rel else str(p))
        db_paths += ['relative db/file.mp4', 'https://example.invalid/remote.mp4']
        for cwd in (app/'apps/web', app/'apps/background-jobs', app):
            (cwd/'relative db').mkdir(parents=True, exist_ok=True)
            (cwd/'relative db/file.mp4').write_text('relative database path')
        for p in app.rglob('*'):
            if p.is_file() and p.name not in {'.env', '.env.system', '.env.production', 'source.txt', 'server.cjs'}:
                rel = p.relative_to(app)
                incoming = c/'archive/release'/rel
                incoming.parent.mkdir(parents=True, exist_ok=True)
                incoming.write_text('incoming default')
    elif scenario in {'env-whitespace','env-quoted','dotdot','dotdot-code'}:
        if scenario.startswith('env-'):
            value = ' \tfaces \t' if scenario == 'env-whitespace' else ' \t" faces " \t'
            selected = 'faces' if scenario == 'env-whitespace' else ' faces '
            for cwd in (app,app/'apps/web',app/'apps/background-jobs'):
                (cwd/selected).mkdir(parents=True)
                (cwd/selected/'witness').write_text('consumer selected face bytes')
            consumer_path = app/selected/'witness'
        else:
            destination = 'store/deeper' if scenario == 'dotdot' else 'apps/web/build/deeper'
            (app/destination).mkdir(parents=True)
            (app/'alias').symlink_to(destination)
            consumer_path = (app/destination).parent/'faces/witness'
            consumer_path.parent.mkdir()
            consumer_path.write_text('consumer selected face bytes')
            value = 'alias/../faces'
        with (app/'.env.system').open('a') as f:f.write('FACES_DIR='+value+'\n')
        # Use a real systemd EnvironmentFile consumer and Python Path traversal.
        # Neither the modeled unit reader nor resolver chooses this witness.
        def actual_reader():
            reader = '''import json,os;from pathlib import Path
p=Path(os.environ['FACES_DIR'])/'witness'
s=p.stat();print(json.dumps([p.read_text(),s.st_ino,s.st_mode,s.st_uid,s.st_gid]))'''
            proof = run(['/usr/bin/systemd-run','--quiet','--wait','--pipe',
                         '--unit=su-edit-mind-review-'+str(os.getpid())+'-'+label,
                         '--property=WorkingDirectory='+str(app),
                         '--property=EnvironmentFile='+str(app/'.env.system'),'/usr/bin/python3','-c',reader])
            return proof
        before_reader = actual_reader()
        assert before_reader.returncode == 0, (before_reader.stdout,before_reader.stderr)
        s=consumer_path.stat()
        assert json.loads(before_reader.stdout) == ['consumer selected face bytes',s.st_ino,s.st_mode,s.st_uid,s.st_gid]
        (c/'actual-reader-before.json').write_text(before_reader.stdout)
    elif scenario == 'compatible':
        (c/'media/videos').symlink_to(app/'media')
    elif scenario == 'conflict':
        (c/'media/videos').mkdir()
        (c/'media/videos/witness').write_text('different owned media')
    elif scenario == 'missing':
        (app/'.env').unlink()
    elif scenario == 'ambiguous':
        with (app/'.env').open('a') as f:f.write('HF_HOME="unterminated\n')
    elif scenario == 'overlap':
        with (app/'.env.system').open('a') as f:f.write('EXPORTS_DIR='+str(app/'apps/web/build')+'\n')
    elif scenario == 'db-overlap':
        db_paths = [str(app/'python/main.py')]
    elif scenario == 'root':
        with (app/'.env.system').open('a') as f:f.write('FACES_DIR='+str(app)+'\n')
    elif scenario == 'uri-option':
        with (app/'.env.system').open('a') as f:f.write('DATABASE_URL=postgresql://fixture:secret@127.0.0.1/fixture?host=/other\n')
    elif scenario == 'tls':
        with (app/'.env.system').open('a') as f:f.write('DATABASE_URL=postgresql://fixture:secret@127.0.0.1/fixture?sslmode=require\n')
    elif scenario == 'uri-redaction':
        with (app/'.env.system').open('a') as f:f.write('DATABASE_URL=postgresql://fixture:private-password-sentinel@127.0.0.1/fixture?private-query-sentinel\n')
    elif scenario == 'wrapper':
        p = c/'etc/systemd/system/edit-mind-web.service'
        p.write_text(p.read_text().replace('ExecStart=/usr/bin/pnpm', 'ExecStart=/usr/bin/env pnpm'))
    elif scenario == 'namespace':
        with (c/'etc/systemd/system/edit-mind-web.service').open('a') as f:f.write('RootDirectory=/different\n')
    elif scenario == 'word-quotes':
        with (c/'etc/systemd/system/edit-mind-web.service').open('a') as f:f.write('Environment=HF_HOME=unquoted"joined"\n')
    elif scenario == 'dropin':
        (app/'custom.env').write_text('XENOVA_MODEL_CACHE_DIR=dropin models\n')
        (app/'apps/web/dropin models').mkdir(parents=True)
        (app/'apps/web/dropin models/sentinel').write_text('dropin owned model')
        (c/'dropin.conf').write_text('[Service]\nEnvironment="XENOVA_MODEL_CACHE_DIR=ignored unit default"\nEnvironmentFile='+str(app/'custom.env')+'\n')
    elif scenario == 'dotenv':
        for cwd in (app/'apps/web',app/'apps/background-jobs'):
            cwd.mkdir(parents=True,exist_ok=True)
            (cwd/'.env').write_text('XENOVA_MODEL_CACHE_DIR=dotenv models\n')
            (cwd/'dotenv models').mkdir()
            (cwd/'dotenv models/sentinel').write_text('dotenv owned model')
    elif scenario == 'symlink-code':
        (app/'bad-alias').symlink_to('apps/web/build')
        with (app/'.env.system').open('a') as f:f.write('HF_HOME='+str(app/'bad-alias')+'\n')
    elif scenario == 'loop':
        (app/'bad-alias').symlink_to('bad-alias')
        with (app/'.env.system').open('a') as f:f.write('HF_HOME='+str(app/'bad-alias')+'\n')
    elif scenario == 'caller':
        (app/'caller keep').mkdir()
        (app/'caller keep/sentinel').write_text('caller retained state')
        (app/'legacy-keep').write_text('legacy caller retained state')
    (c/'db-roots.json').write_text(json.dumps(db_paths))
    if scenario == 'sql':
        (c/'sql-fail').touch()
    if scenario == 'race':
        (c/'race').touch()
    (c/'bin/psql').write_text('''#!/usr/bin/env python3
import os,sys,json
from pathlib import Path
c=Path(__file__).resolve().parents[1]
sql=sys.stdin.read()
assert 'BEGIN READ ONLY' in sql and '"public"."Folder"' in sql
assert os.environ['PGDATABASE']=='fixture' and os.environ['PGUSER']=='fixture'
assert os.environ['PGSSLMODE']=='disable'
if (c/'sql-fail').exists():sys.exit(2)
print((c/'db-roots.json').read_text())
''')
    (c/'bin/pnpm').write_text('''#!/usr/bin/env python3
import os,sys
from pathlib import Path
with (Path(os.environ['CASE_ROOT'])/'exec-builds').open('a') as f:f.write(' '.join(sys.argv[1:])+'\\n')
if 'migrate:deploy' in sys.argv:
 (Path(os.environ['CASE_ROOT'])/'effective-temporary.json').write_text(__import__('json').dumps(os.environ.get('TMPDIR')))
if os.environ.get('FAULT')=='migrate':sys.exit(45)
''')
    retained = {str(p.relative_to(app)): (p.read_bytes(), p.stat().st_ino, p.stat().st_mode,
                p.stat().st_uid, p.stat().st_gid) for p in app.rglob('*') if p.is_file() and p.name not in {'source.txt','server.cjs'}}
    links = {str(p.relative_to(app)): (os.readlink(p), p.lstat().st_ino) for p in app.rglob('*') if p.is_symlink()}
    directories = {str(p.relative_to(app)): (p.stat().st_ino,p.stat().st_mode,p.stat().st_uid,p.stat().st_gid)
                   for p in app.rglob('*') if p.is_dir() and not p.is_symlink()}
    # Repack after all incoming collision cases have been populated.
    subprocess.run(['tar', '-czf', str(c/'release.tar.gz'), '-C', str(c/'archive'), 'release'], check=True)
    retained = {str(p.relative_to(app)): (p.read_bytes(), p.stat().st_ino, p.stat().st_mode,
                p.stat().st_uid, p.stat().st_gid) for p in app.rglob('*') if p.is_file() and p.name not in {'source.txt','server.cjs'}}
    subprocess.run(['tar', '-czf', str(c/'release.tar.gz'), '-C', str(c/'archive'), 'release'], check=True)
    (c/'stage/core.func').write_text((ROOT/'misc/core.func').read_text().replace(
        '/var/lib/scripts-underground/update-pending', str(c/'state')).replace(
        '/var/lib/scripts-underground/maintenance-locks', str(c/'locks')))
    (c/'stage/tools.func').write_text((ROOT/'misc/tools.func').read_text().replace(
        '/opt/$app', str(c/'opt')+'/$app'))
    shutil.copyfile(ROOT/'misc/error_handler.func', c/'stage/error_handler.func')
    (c/'stage/install.func').write_text('pkg_install() { :; }; setup_lxc() { :; }\n')
    models = r'''
header_info() { :; }
check_container_storage() { :; }
check_container_resources() { :; }
cleanup_lxc() { :; }
stop_spinner() { :; }
msg_info() { :; }
msg_ok() { printf 'OK %s\n' "$*"; }
msg_error() { printf 'ERROR %s\n' "$*" >&2; }
msg_warn() { printf 'WARN %s\n' "$*"; }
ensure_dependencies() { :; }
getent() { return 0; }
get_system_arch() { printf amd64; }
curl() {
  local out='' format=''
  while (($#)); do
    case "$1" in -o) out="$2"; shift ;; -w) format="$2"; shift ;; esac
    shift
  done
  printf '{"tag_name":"v2.0","tarball_url":"https://fixture.invalid/source.tar.gz"}' > "$out"
  [[ -z "$format" ]] || printf 200
}
curl_download() { printf download >> "$CASE_ROOT/downloads"; command cp "$CASE_ROOT/release.tar.gz" "$1"; }
systemctl() {
  if [[ "$1" == stop && -f "$CASE_ROOT/manager-race" ]]; then printf '{"TMPDIR":"%s/changed-temporary-root"}' "$CASE_ROOT" > "$CASE_ROOT/manager.json"; fi
  printf '%s\n' "$*" >> "$CASE_ROOT/services"
  if [[ "$1" == stop && -f "$CASE_ROOT/race" ]]; then printf 'FACES_DIR=changed-root\n' >> "$CASE_ROOT/opt/edit-mind/.env.system"; fi
  if [[ "$1" == start && "$FAULT" == start ]]; then return 44; fi
}
pnpm() {
  printf '%s\n' "$*" >> "$CASE_ROOT/builds"
  if [[ "$FAULT" == build && "$*" == 'run build:web' ]]; then return 42; fi
  if [[ "$FAULT" == install && "$*" == 'install --prefer-frozen-lockfile' ]]; then return 41; fi
}
cp() {
  if [[ "$FAULT" == publish && "$*" == *deploy-source* && "${!#}" == "$CASE_ROOT/opt/edit-mind/"* ]]; then return 43; fi
  command cp "$@"
}
'''
    if scenario == 'caller':
        models += "\ndeclare -a CLEAN_INSTALL_KEEP_PATHS=('caller keep')\nCLEAN_INSTALL_KEEP=legacy-keep\n"
    elif scenario == 'invalid-caller':
        models += "\nCLEAN_INSTALL_KEEP_PATHS=.\n"
    elif scenario == 'glob-caller':
        models += "\ndeclare -a CLEAN_INSTALL_KEEP_PATHS=('unsafe*')\n"
    elif scenario == 'readonly-caller':
        models += "\ndeclare -ar CLEAN_INSTALL_KEEP_PATHS=('media')\n"
    (c/'models.sh').write_text(models)
    (c/'stage/github.func').write_text('clone_and_deploy_gh_commit() { :; }\nsource '+str(c/'models.sh')+'\n')
    text = subject.read_text()
    match = re.search(r'^function update_script\(\) \{\n.*?^\}', text, re.M | re.S)
    assert match
    hook = match.group().replace('/opt/edit-mind', str(app)).replace('/media/videos', str(c/'media/videos'))
    (c/'hook.sh').write_text(hook+'\n')
    generate = '''set -euo pipefail
source "$ROOT/misc/bundle.func"
source "$CASE_ROOT/hook.sh"
APP=Edit-Mind NSAPP=edit-mind REPO_BASE=https://fixture.invalid
var_lxc_tmpdir="$CASE_ROOT/tmp"
_write_bundle update update_script "$CASE_ROOT/stage" 'run_update_script "$@"' > "$CASE_ROOT/sbin/update"
'''
    env = dict(os.environ, ROOT=str(ROOT), CASE_ROOT=str(c))
    r = run(['bash', '-c', generate], env=env)
    assert r.returncode == 0, (r.stdout, r.stderr)
    bundle = c/'sbin/update'
    # Bundle PATH is fixed by its real owner; project only external executables
    # into this fixture namespace, never replace parser/deployer/pending functions.
    fixed_path = 'export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"'
    emitted = bundle.read_text()
    assert emitted.count(fixed_path) == 1
    bundle.write_text(emitted.replace(fixed_path, 'export PATH="'+str(c/'bin')+':/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"'))
    env = dict(PATH=str(c/'bin')+':'+os.environ['PATH'], HOME=str(c/'home'), TMPDIR=str(c/'tmp'), CASE_ROOT=str(c),
               BUILD_LOG=str(c/'active.log'), DEBUG_LOGFILE=str(c/'error.log'), VERBOSE='yes', FAULT=fault)
    if scenario == 'manager-native':
        prior = json.loads(subprocess.check_output(['/usr/bin/systemctl','show-environment','--output=json'],text=True,timeout=20))
        value = str(c/'tmp literal "quotes"')
        try:
            subprocess.run(['/usr/bin/systemctl','set-environment','TMPDIR='+value],check=True,timeout=20)
            observe = 'import json,os;print(json.dumps(os.environ["TMPDIR"]))'
            for suffix, props, expected in [('manager',[],value),
                    ('unit',['--property=Environment=TMPDIR='+str(c/'unit-tmp')],str(c/'unit-tmp')),
                    ('file',['--property=Environment=TMPDIR='+str(c/'unit-tmp'),
                             '--property=EnvironmentFile='+str(c/'temporary.env')],str(c/'file-tmp'))]:
                (c/'temporary.env').write_text('TMPDIR='+str(c/'file-tmp')+'\n')
                p=run(['/usr/bin/systemd-run','--quiet','--wait','--pipe',
                       '--unit=su-edit-mind-temp-'+str(os.getpid())+'-'+suffix,*props,'/usr/bin/python3','-c',observe])
                assert p.returncode==0 and json.loads(p.stdout)==expected,(p.stdout,p.stderr)
            r = run(['bash', str(c/'sbin/update')], env=env)
        finally:
            command=['/usr/bin/systemctl','set-environment','TMPDIR='+prior['TMPDIR']] if 'TMPDIR' in prior else ['/usr/bin/systemctl','unset-environment','TMPDIR']
            subprocess.run(command,check=True,timeout=20)
            assert json.loads(subprocess.check_output(['/usr/bin/systemctl','show-environment','--output=json'],text=True,timeout=20))==prior
    else:
        r = run(['bash', str(c/'sbin/update')], env=env)
    (c/'stdout').write_text(r.stdout)
    (c/'stderr').write_text(r.stderr)
    if scenario.startswith('manager-') and r.returncode==0:
        expected = str(c/'file tmp') if scenario=='manager-unit' else value if scenario=='manager-native' else manager['TMPDIR']
        assert json.loads((c/'effective-temporary.json').read_text())==expected
    survived = all((app/name).exists() and ((app/name).read_bytes(), (app/name).stat().st_ino,
                    (app/name).stat().st_mode, (app/name).stat().st_uid,
                    (app/name).stat().st_gid) == fact for name, fact in retained.items())
    survived = survived and all((app/name).is_symlink() and (os.readlink(app/name), (app/name).lstat().st_ino) == fact for name, fact in links.items())
    survived = survived and all((app/name).is_dir() and ((app/name).stat().st_ino,(app/name).stat().st_mode,
                (app/name).stat().st_uid,(app/name).stat().st_gid) == fact for name,fact in directories.items())
    stable_state = all((app/name).exists() and ((app/name).read_bytes(),(app/name).stat().st_ino,
                    (app/name).stat().st_mode,(app/name).stat().st_uid,(app/name).stat().st_gid) == fact
                    for name,fact in retained.items() if name != '.env.system')
    external_ok = not (c/'external/witness').exists() or (c/'external/witness').read_text() == 'external witness'
    legacy_ok = all((c/'opt'/name).exists() and (c/'opt'/name).read_text() == text for name,text in [
        ('edit-mind.env.bak','unowned legacy backup'),('edit-mind.env.system.bak','unowned legacy system backup')])
    result = dict(status=r.returncode, retained=survived, source=(app/'source.txt').read_text(),
                services=(c/'services').read_text() if (c/'services').exists() else '',
                pending=(c/'state/edit-mind').exists(), case=str(c), external=external_ok, legacy=legacy_ok,
                media=(c/'media/videos').is_dir() and (c/'media/videos').resolve() == (app/'media').resolve(),
                marker=(c/'home/.edit-mind').read_text().strip())
    result.update(stable_state=stable_state,downloaded=(c/'downloads').exists(),
                  built=(c/'builds').exists() or (c/'exec-builds').exists(),
                  redacted=not any(secret in r.stdout+r.stderr for secret in ('private-password-sentinel','private-query-sentinel')))
    if scenario in {'env-whitespace','env-quoted','dotdot','dotdot-code'}:
        after_reader = actual_reader()
        (c/'actual-reader-after.stdout').write_text(after_reader.stdout)
        (c/'actual-reader-after.stderr').write_text(after_reader.stderr)
        result['actual_reader_retained'] = after_reader.returncode == 0 and after_reader.stdout == before_reader.stdout
    code_consumer = run([os.environ['EDIT_MIND_NODE'],'-e',
                         'process.stdout.write(require(process.argv[1]).release)',str(app/'apps/web/server.cjs')])
    assert code_consumer.returncode == 0, code_consumer.stderr
    result['code_release'] = code_consumer.stdout
    if fault != 'none' and r.returncode:
        env['FAULT'] = 'none'
        retry = run(['bash', str(c/'sbin/update')], env=env)
        (c/'retry-stdout').write_text(retry.stdout)
        (c/'retry-stderr').write_text(retry.stderr)
        result['retry_status'] = retry.returncode
        result['retry_pending'] = (c/'state/edit-mind').exists()
        result['retry_retained'] = all((app/name).exists() and (app/name).read_bytes() == fact[0] and (app/name).stat().st_ino == fact[1] for name,fact in retained.items())
        result['retry_downloads'] = (c/'downloads').read_text().count('download')
        retry_code = run([os.environ['EDIT_MIND_NODE'],'-e',
                          'process.stdout.write(require(process.argv[1]).release)',str(app/'apps/web/server.cjs')])
        assert retry_code.returncode == 0 and retry_code.stdout == 'new', retry_code.stderr
        result['retry_code_release'] = retry_code.stdout
    return result


old = case(BASELINE, 'old-full-generated')
assert old['status'] == 0 and old['source'] == 'new source' and old['code_release'] == 'new', old
assert not old['retained'], old
assert 'stop edit-mind-web edit-mind-jobs\n' in old['services'], old
assert 'edit-mind-ml' not in old['services'] and 'edit-mind-chroma' not in old['services'], old
print('OLD_FULL_GENERATED_UPDATER_RED', json.dumps(old, sort_keys=True), flush=True)
if (ROOT/'scripts/lxc/edit-mind.sh').read_bytes() == BASELINE.read_bytes():
    raise SystemExit(0)
for scenario in ('default', 'fresh-install', 'custom', 'compatible', 'caller', 'dropin', 'dotenv',
                 'env-whitespace','env-quoted','manager-temp','manager-quoted','manager-unit','manager-native',
                 'manager-production-temp','manager-reset'):
    new = case(ROOT/'scripts/lxc/edit-mind.sh', 'corrected-'+scenario, scenario=scenario)
    assert new['status'] == 0 and new['retained'] and new['source'] == 'new source' and new['code_release'] == 'new', new
    assert new['external'] and new['legacy'] and new['media'] and not new['pending'], new
    assert new.get('actual_reader_retained',True), new
    assert 'stop edit-mind-web\nstop edit-mind-jobs\nstop edit-mind-ml\nstop edit-mind-chroma\n' in new['services'], new
    checks += 1
    print('EDIT_MIND_RETENTION_PASS', json.dumps(new, sort_keys=True), flush=True)
for scenario in ('conflict', 'missing', 'ambiguous', 'overlap', 'db-overlap', 'root',
                 'uri-option', 'tls', 'wrapper', 'namespace', 'sql', 'race', 'symlink-code', 'loop',
                  'invalid-caller', 'glob-caller', 'uri-redaction', 'word-quotes', 'readonly-caller',
                  'dotdot','dotdot-code','manager-race','manager-app','manager-alias','manager-relative',
                  'manager-empty','manager-malformed','manager-field-HOME','manager-field-HF_HOME',
                  'manager-field-PGOPTIONS','manager-field-NODE_OPTIONS','manager-field-PYTHONPATH','manager-field-LD_LIBRARY_PATH'):
    refused = case(ROOT/'scripts/lxc/edit-mind.sh', 'refuse-'+scenario, scenario=scenario)
    assert refused['status'] == 65 and refused['source'] == 'old source' and refused['pending'], refused
    assert refused['code_release'] == 'old', refused
    assert not refused['services'] or scenario in {'race','manager-race'}, refused
    assert refused['retained'] or (scenario == 'race' and refused['stable_state']), refused
    assert not refused['downloaded'] and not refused['built'], refused
    assert refused['redacted'], refused
    assert refused.get('actual_reader_retained',True), refused
    checks += 1
    print('EDIT_MIND_REFUSAL_PASS', json.dumps(refused, sort_keys=True), flush=True)
for fault, status in [('install',41),('build',42),('start',44),('migrate',45),('publish',252)]:
    failed = case(ROOT/'scripts/lxc/edit-mind.sh', 'failure-'+fault, fault=fault)
    assert failed['status'] == status and failed['retained'] and failed['pending'], failed
    assert failed['retry_status'] == 0 and not failed['retry_pending'] and failed['retry_retained'], failed
    if fault != 'publish':
        assert failed['marker'] == '2.0' and failed['retry_downloads'] == 2, failed
    checks += 1
    print('EDIT_MIND_PENDING_RETRY_PASS', json.dumps(failed, sort_keys=True), flush=True)
for scenario in ('fresh-absent-no-python','fresh-compatible-no-python','fresh-conflict-no-python',
                 'fresh-dangling-no-python','fresh-alias-conflict-no-python','fresh-file-no-python'):
    fresh = case(ROOT/'scripts/lxc/edit-mind.sh',scenario,scenario=scenario)
    assert fresh['untouched'], fresh
    if scenario in {'fresh-absent-no-python','fresh-compatible-no-python'}:
        assert fresh['status'] == 0 and fresh['apt'] and fresh['downloaded'] and fresh['media'], fresh
    else:
        assert fresh['status'] == 65 and not fresh['apt'] and not fresh['downloaded'], fresh
    checks += 1
    print('EDIT_MIND_FRESH_PREREQUISITE_PASS',json.dumps(fresh,sort_keys=True),flush=True)
native = case(ROOT/'scripts/lxc/edit-mind.sh','fresh-native-baseline',scenario='fresh-native-baseline')
assert native['status']==0 and native['sql_produced'] and native['normal_application_credential'], native
checks += 1
print('EDIT_MIND_EMPTY_RECEIVER_REAL_PG_HELPER_PASS',json.dumps(native,sort_keys=True),flush=True)
print('EDIT_MIND_COLD_CASES_PASS cases='+str(checks)+' failures=0', flush=True)

# Native adapter proof, separate from modeled archives/package/service producers.
# Private Debian PostgreSQL binaries are closed named inputs, not installed services.
PG = Path(os.environ['EDIT_MIND_PG_TOOLS'])
native = Path(tempfile.mkdtemp(prefix='edit-mind-pg-', dir=PG.parents[2]/'tools'))
tester = pwd.getpwnam('tester')
os.chown(native, tester.pw_uid, tester.pw_gid)
native.chmod(0o700)
data, log = native/'data', native/'postgres.log'
env = dict(os.environ, PGHOST='127.0.0.1', PGPORT='55439', PGUSER='tester', PGDATABASE='postgres')
for key in list(env):
    if key.startswith('PG') and key not in {'PGHOST','PGPORT','PGUSER','PGDATABASE'}:
        del env[key]


def pg_user(args, timeout=40):
    p = subprocess.run(['runuser','-u','tester','--',*map(str,args)], env=env,
                       capture_output=True, text=True, timeout=timeout)
    assert p.returncode == 0, (p.returncode,p.stdout,p.stderr)
    return p.stdout


def sql(text):
    p = subprocess.run([str(PG/'psql'),'-X','-w','-qAt','-v','ON_ERROR_STOP=1'], input=text,
                       env=env, capture_output=True, text=True, timeout=20)
    assert p.returncode == 0, (p.returncode,p.stdout,p.stderr)
    return p.stdout


started = False
try:
    password_file = native/'bootstrap-password'
    password_file.write_text('synthetic-bootstrap\n')
    os.chown(password_file,tester.pw_uid,tester.pw_gid)
    password_file.chmod(0o600)
    pg_user([PG/'initdb','-D',data,'-L',PG/'usr/share/postgresql/17','--no-locale','-E','UTF8',
             '--auth-host=scram-sha-256','--auth-local=trust','--pwfile='+str(password_file)])
    pg_user([PG/'pg_ctl','-D',data,'-l',log,'-o',"-h 127.0.0.1 -p 55439 -c unix_socket_directories=''",'-w','start'])
    started = True
    env['PGPASSWORD'] = 'synthetic-bootstrap'
    sql('CREATE DATABASE edit_fixture; CREATE ROLE "fixture user" LOGIN PASSWORD \'p:a%@ss\';')
    env['PGDATABASE'] = 'edit_fixture'
    fields = [('Folder',['path']),('Job',['videoPath','thumbnailPath']),('Video',['source','thumbnailUrl']),
              ('ChatMessage',['stitchedVideoPath']),('Export',['filePath'])]
    schema = 'media schema'
    sql('CREATE SCHEMA "'+schema+'";')
    expected = []
    for table, cols in fields:
        sql('CREATE TABLE "'+schema+'"."'+table+'" ('+','.join('"'+col+'" text' for col in cols)+');')
        values = [str(native/(table+' '+col)) for col in cols]
        expected.extend(values)
        sql('INSERT INTO "'+schema+'"."'+table+'" VALUES ('+','.join("'"+v.replace("'","''")+"'" for v in values)+');')
    sql('GRANT CONNECT ON DATABASE edit_fixture TO "fixture user"; GRANT USAGE ON SCHEMA "'+schema+'" TO "fixture user"; GRANT SELECT ON ALL TABLES IN SCHEMA "'+schema+'" TO "fixture user";')
    source = (ROOT/'scripts/lxc/edit-mind.sh').read_text()
    resolver = source.split("    python3 - \"$@\" << 'PY'\n",1)[1].split('\nPY',1)[0]
    definitions = resolver.split('\ntry:\n    mode = sys.argv[1]',1)[0]
    namespace = {}
    exec(compile(definitions,'actual-edit-mind-resolver','exec'),namespace)
    old_path = os.environ['PATH']
    os.environ['PATH'] = str(PG)+':'+old_path
    uri = 'postgresql://fixture%20user:p%3Aa%25%40ss@127.0.0.1:55439/edit_fixture?schema='+quote(schema)+'&sslmode=disable'
    actual = namespace['database'](uri)
    assert actual == sorted(expected), actual
    for bad in [uri.replace('media%20schema','absent'), uri.replace('/edit_fixture?','/missing_database?'),
                uri.replace('p%3Aa%25%40ss','wrong-password'),
                uri.replace('sslmode=disable','sslmode=require')]:
        try:
            namespace['database'](bad)
        except ValueError:
            pass
        else:
            raise AssertionError('native adapter accepted wrong database/schema/TLS')
    # Compare supported EnvironmentFile quoting and precedence with real systemd.
    envfile = native/'literal.env'
    envfile.write_text('HF_HOME="env model path"\nEMPTY=\nLITERAL=contains spaces\n'
                       'SPACE= faces \t\nTAB=\tfaces\t\nQUOTED= \t" faces " \t\n'
                       "SINGLE= ' faces ' \t\nEMPTY_SPACE= \t\nEMPTY_QUOTED= '' \t\n")
    parsed = namespace['env_file'](envfile)
    proof = subprocess.run(['systemd-run','--quiet','--wait','--pipe',
                            '--unit=su-edit-mind-env-'+str(os.getpid()),
                            '--property=EnvironmentFile='+str(envfile),
                            '--setenv=HF_HOME=unit-default','/usr/bin/env'],
                           capture_output=True,text=True,timeout=30)
    assert proof.returncode == 0, (proof.stdout,proof.stderr)
    observed = dict(line.split('=',1) for line in proof.stdout.splitlines() if '=' in line)
    assert all(observed[k] == v for k,v in parsed.items())
    os.environ['PATH'] = old_path
    print('EDIT_MIND_NATIVE_SQL_PARSER_PASS paths='+str(len(actual))+' selected_database=edit_fixture selected_schema='+schema+' wrong_database_schema_password_tls_refusals=4 native_systemd_precedence=pass',flush=True)
finally:
    if started:
        pg_user([PG/'pg_ctl','-D',data,'-w','-m','fast','stop'])

# Actual upstream path validator; only its unrelated logging dependency is modeled.
validator = (REFERENCE/'packages/shared/src/services/pathValidator.ts').read_text()
assert validator.count("import { logger } from './logger'") == 1
validator = validator.replace("import { logger } from './logger'", 'const logger = { warn(...args: unknown[]) {}, error(...args: unknown[]) {} }')
module = WORK/'pathValidator.mts'
module.write_text(validator)
media = WORK/'corrected-default/media/videos'
consumer = '''import { createPathValidator } from MODULE;
import fs from 'node:fs';
const base=BASE;
const validator=createPathValidator(base);
for (const input of [base+'/film.mp4',fs.realpathSync(base)+'/film.mp4']) {
 const first=validator.validatePath(input);
 if (!first.isValid) throw new Error('lexical path rejected');
 const real=fs.realpathSync(first.sanitizedPath);
 if (!validator.validatePath(real).isValid) throw new Error('canonical path rejected');
 if (fs.readFileSync(real,'utf8')!=='owned media') throw new Error('media bytes changed');
}
console.log('ACTUAL_UPSTREAM_MEDIA_VALIDATOR_PASS lexical_and_canonical_reads=2');
'''.replace('MODULE',json.dumps(module.as_uri())).replace('BASE',json.dumps(str(media)))
proof = subprocess.run([os.environ['EDIT_MIND_NODE'],'--experimental-strip-types','--input-type=module','-e',consumer],capture_output=True,text=True,timeout=30)
assert proof.returncode == 0, (proof.stdout,proof.stderr)
print(proof.stdout,end='',flush=True)
print('EDIT_MIND_FOCUSED_PASS cases='+str(checks)+' failures=0 native_sql=pass native_systemd_parser=pass actual_media_validator=pass', flush=True)
