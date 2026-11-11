#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/IliasHad/edit-mind

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Edit-Mind"
var_tags="${var_tags:-ai;media;photos}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-32}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  # Refuse a conflicting native media namespace before downloads or package effects.
  # Python is provisioned below; this preflight uses bootstrap Bash/coreutils only.
  local native_media native_target
  if [[ -e /media/videos || -L /media/videos ]]; then
    if [[ ! -d /media/videos || ! -d /opt/edit-mind/media ]] ||
      ! native_media=$(readlink -f -- /media/videos) ||
      ! native_target=$(readlink -f -- /opt/edit-mind/media) ||
      [[ "$native_media" != "$native_target" ]]; then
      msg_error "Edit-Mind: /media/videos conflicts with /opt/edit-mind/media; reconcile existing data first"
      return 65
    fi
  fi
  msg_info "Installing Dependencies"
  $STD apt install -y \
    build-essential \
    cmake \
    redis-server \
    nginx \
    python3 \
    python3-dev \
    libgomp1 \
    libglib2.0-0 \
    libgl1 \
    libsm6 \
    libxext6 \
    libxrender1 \
    openssl
  msg_ok "Installed Dependencies"

  setup_ffmpeg
  PG_VERSION="16" PG_MODULES="pgvector" setup_postgresql
  PG_DB_NAME="editmind" PG_DB_USER="editmind" setup_postgresql_db
  NODE_VERSION="22" setup_nodejs
  UV_PYTHON="3.11" setup_uv

  msg_info "Installing pnpm"
  $STD corepack enable pnpm
  $STD corepack prepare pnpm@10.33.1 --activate
  msg_ok "Installed pnpm"

  fetch_and_deploy_gh_release "edit-mind" "IliasHad/edit-mind" "tarball"

  msg_info "Installing Application Dependencies"
  cd /opt/edit-mind || exit
  $STD pnpm install --prefer-frozen-lockfile
  $STD pnpm --filter prisma generate
  msg_ok "Installed Application Dependencies"

  msg_info "Building Application"
  cat << EOF > /opt/edit-mind/apps/web/.env.production
VITE_BACKGROUND_JOBS_URL=http://${LOCAL_IP}:4000
EOF
  $STD pnpm run build:web
  $STD pnpm rebuild @tailwindcss/oxide rollup onnxruntime-node
  $STD pnpm run build:background-jobs
  msg_ok "Built Application"

  msg_info "Setting up Python ML Environment"
  $STD uv venv --python 3.11 /opt/edit-mind/.venv
  $STD uv pip install --no-cache-dir --python /opt/edit-mind/.venv \
    -r /opt/edit-mind/python/requirements.txt \
    chromadb
  msg_ok "Set up Python ML Environment"

  msg_info "Configuring Application"
  SESSION_SECRET=$(openssl rand -base64 32)
  ENCRYPTION_KEY=$(openssl rand -base64 32)
  mkdir -p /opt/edit-mind/.data /opt/edit-mind/ml-models
  cat << EOF > /opt/edit-mind/.env
SESSION_SECRET=${SESSION_SECRET}
ENCRYPTION_KEY=${ENCRYPTION_KEY}
HOST_MEDIA_PATH=/opt/edit-mind/media
OLLAMA_MODEL=qwen2.5:7b-instruct
USE_OLLAMA_MODEL=false
OLLAMA_HOST=
OLLAMA_PORT=
GEMINI_API_KEY=
USE_GEMINI=false
PORT=3745
BACKGROUND_JOBS_PORT=4000
ML_PORT=8765
REDIS_PORT=6379
POSTGRES_PORT=5432
CHROMA_PORT=8000
EOF
  cat << EOF > /opt/edit-mind/.env.system
DATABASE_URL=postgresql://${PG_DB_USER}:${PG_DB_PASS}@127.0.0.1:5432/${PG_DB_NAME}
REDIS_URL=redis://127.0.0.1:6379
REDIS_HOST=127.0.0.1
CHROMA_HOST=127.0.0.1
IS_PERSISTENT=TRUE
ML_HOST=127.0.0.1
PROCESSED_VIDEOS_DIR=/opt/edit-mind/.data
THUMBNAILS_PATH=/opt/edit-mind/.data/.thumbnails
STITCHED_VIDEOS_DIR=/opt/edit-mind/.data/.stitched-videos
FACES_DIR=/opt/edit-mind/.data/.faces
UNKNOWN_FACES_DIR=/opt/edit-mind/.data/.unknown_faces
KNOWN_FACES_FILE=/opt/edit-mind/.data/.faces.json
KNOWN_FACES_FILE_LOADED=/opt/edit-mind/.data/.known_faces.json
BACKGROUND_JOBS_URL=http://127.0.0.1:4000
NODE_ENV=production
ANONYMIZED_TELEMETRY=FALSE
WEB_APP_URL=http://${LOCAL_IP}:3745
EOF
  mkdir -p /opt/edit-mind/media
  python3 - << 'PY'
import os
from pathlib import Path
media, target = Path('/media/videos'), Path('/opt/edit-mind/media')
if os.path.lexists(media):
    if not media.is_dir() or media.resolve() != target.resolve():
        raise SystemExit('Edit-Mind: native media mapping changed during install')
else:
    media.parent.mkdir(parents=True, exist_ok=True)
    media.symlink_to(target, target_is_directory=True)
PY
  (
    export DATABASE_URL="postgresql://${PG_DB_USER}:${PG_DB_PASS}@127.0.0.1:5432/${PG_DB_NAME}"
    export SESSION_SECRET ENCRYPTION_KEY NODE_ENV=production
    $STD pnpm --filter prisma migrate:deploy
    $STD pnpm --filter db seed
  )
  msg_ok "Configured Application"

  msg_info "Creating Services"
  cat << EOF > /etc/systemd/system/edit-mind-chroma.service
[Unit]
Description=Edit-Mind ChromaDB
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/edit-mind
Environment=IS_PERSISTENT=TRUE
ExecStart=/opt/edit-mind/.venv/bin/chroma run --host 127.0.0.1 --port 8000 --path /opt/edit-mind/.data/chroma
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  cat << EOF > /etc/systemd/system/edit-mind-ml.service
[Unit]
Description=Edit-Mind ML Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/edit-mind
EnvironmentFile=/opt/edit-mind/.env
EnvironmentFile=/opt/edit-mind/.env.system
Environment=YOLO_CONFIG_DIR=/opt/edit-mind/ml-models/ultralytics
Environment=DEEPFACE_HOME=/opt/edit-mind/ml-models/deepface
Environment=TRANSCRIPTION_MODEL_CACHE=/opt/edit-mind/ml-models/whisper
Environment=TORCH_HOME=/opt/edit-mind/ml-models/torch
Environment=HF_HOME=/opt/edit-mind/ml-models/huggingface
ExecStart=/opt/edit-mind/.venv/bin/python /opt/edit-mind/python/main.py --host 0.0.0.0 --port 8765
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

  cat << EOF > /etc/systemd/system/edit-mind-jobs.service
[Unit]
Description=Edit-Mind Background Jobs
After=network.target postgresql.service redis-server.service edit-mind-chroma.service edit-mind-ml.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/edit-mind
EnvironmentFile=/opt/edit-mind/.env
EnvironmentFile=/opt/edit-mind/.env.system
ExecStart=/usr/bin/pnpm --filter background-jobs start
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  cat << EOF > /etc/systemd/system/edit-mind-web.service
[Unit]
Description=Edit-Mind Web Application
After=network.target postgresql.service redis-server.service edit-mind-chroma.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/edit-mind
EnvironmentFile=/opt/edit-mind/.env
EnvironmentFile=/opt/edit-mind/.env.system
ExecStart=/usr/bin/pnpm --filter web start --host 0.0.0.0 --port 3745
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now edit-mind-chroma
  systemctl enable -q --now edit-mind-ml
  systemctl enable -q --now edit-mind-jobs
  systemctl enable -q --now edit-mind-web
  msg_ok "Created Services"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3745${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  # Captured in the generated updater: discovery must survive missing node_modules.
  function edit_mind_state() {
    python3 - "$@" << 'PY'
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
from urllib.parse import parse_qsl, unquote, urlsplit

APP_ROOT = Path('/opt/edit-mind')
MEDIA = Path('/media/videos')

class Refusal(ValueError):
    """Only source-owned diagnostics may cross the configuration boundary."""

def require(ok, message):
    if not ok:
        raise Refusal(message)

def literal(value):
    require(not any(c in value for c in '\\$`\x00\r\n'),
            'unsupported escape, expansion or multiline configuration')
    return value

def words(value):
    require('%' not in value, 'unsupported systemd specifier expansion')
    token = r'''(?:[^\s'"\\]+|"[^"\\]*"|'[^'\\]*')'''
    require(not value or re.fullmatch(token+r'(?:\s+'+token+r')*', value),
            'unsupported systemd word quoting; quote complete words only')
    return shlex.split(literal(value), comments=False, posix=True)

def query(*argv):
    p = subprocess.run(argv, capture_output=True, text=True, timeout=20)
    require(p.returncode == 0, 'cannot observe effective service configuration')
    return p.stdout.strip()

fingerprints = {}
roots = set()
keeps = set()

def contents(path):
    p = Path(path)
    require(p.is_absolute() and p.is_file(), 'required configuration file unavailable')
    data = p.read_bytes()
    require(len(data) <= 1048576, 'configuration file exceeds supported bound')
    fingerprints[str(p)] = hashlib.sha256(data).hexdigest()
    return data.decode('utf-8')

def assignment(text):
    require('=' in text, 'expected literal KEY=value assignment')
    key, value = text.split('=', 1)
    require(re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', key), 'invalid environment name')
    return key, literal(value)

def env_file(path):
    result = {}
    for line in contents(path).splitlines():
        line = line.strip()
        if not line or line.startswith(('#', ';')):
            continue
        key, value = assignment(line)
        # EnvironmentFile discards unquoted edge whitespace; Environment= does not.
        value = value.strip(' \t')
        if value.startswith(('"', "'")):
            require(len(value) >= 2 and value[-1] == value[0] and value[0] not in value[1:-1],
                    'unsupported EnvironmentFile quoting')
            value = value[1:-1]
        else:
            require(not any(c in value for c in "\"'"), 'unsupported EnvironmentFile quoting')
        result[key] = value
    return result

def absolute(value, cwd):
    literal(value)
    require(value and not value.startswith('~'), 'empty or home-relative persistent path')
    # Do not erase symlink/.. traversal before the owning validation boundary.
    return Path(os.path.join(str(cwd), value))

def protected(path):
    require('..' not in path.parts, 'unsupported parent traversal in persistent path')
    # Preserve lexical aliases as well as referents. Never copy external data.
    for component in (path, *path.parents):
        if component.is_symlink():
            component.resolve(strict=True)  # Refuse loops and unknown/dangling mappings.
    for p in (path, path.resolve()):
        require(p != APP_ROOT and p not in APP_ROOT.parents,
                'persistent path overlaps application root or ancestor')
        roots.add(str(p))
        if not p.is_relative_to(APP_ROOT):
            continue
        rel = p.relative_to(APP_ROOT)
        parts = rel.parts
        require(not any(any(c in part for c in '*?[]\\\r\n') for part in parts),
                'persistent path cannot be represented as a literal keep')
        require(not set(parts) & {'node_modules', 'build', 'dist', 'src', '.git', '__pycache__', 'tests', 'server', 'migrations'},
                'persistent path overlaps code, dependencies or generated output')
        python_config = str(rel) in {'python/.env', 'python/services/.env', 'python/services/analysis/.env'}
        require(python_config or parts[0] not in {'python', 'scripts', 'patches', 'docker', 'docs', 'tests'},
                'persistent path overlaps application code')
        require(not (parts[0] in {'apps', 'packages'} and len(parts) < 3),
                'persistent path overlaps package code')
        require(not (len(parts) >= 3 and parts[0] == 'apps' and parts[2] in {'app', 'public', 'server.js', 'package.json'}),
                'persistent path overlaps package source')
        require(not any(part.endswith(('.ts', '.tsx', '.js', '.mjs', '.cjs', '.py', '.prisma')) or
                        part in {'package.json', 'pnpm-lock.yaml', 'pnpm-workspace.yaml', 'tsconfig.json'}
                        for part in parts),
                'persistent path overlaps application source')
        keeps.add(str(rel))

def root(value, cwd):
    protected(absolute(value, cwd))

def temporary(value):
    require(isinstance(value, str) and value.startswith('/') and
            not any(ord(c) < 32 or ord(c) == 127 for c in value), 'unsupported temporary-workspace value')
    path = Path(value)
    require('..' not in path.parts, 'unsupported temporary-workspace traversal')
    for component in (path, *path.parents):
        if component.is_symlink():
            component.resolve(strict=True)
    for candidate in (path, path.resolve()):
        require(candidate != APP_ROOT and candidate not in APP_ROOT.parents and
                not candidate.is_relative_to(APP_ROOT), 'temporary workspace overlaps application tree or ancestor')
    # Temporary workspace is deliberately not a durable root or deployment keep.
    return value

def service(name, manager):
    props = {}
    for line in query('systemctl', 'show', 'edit-mind-'+name+'.service',
                      '-p', 'FragmentPath', '-p', 'DropInPaths', '-p', 'NeedDaemonReload').splitlines():
        key, value = line.split('=', 1)
        props[key] = value
    require(props.get('NeedDaemonReload') == 'no', 'service changes need daemon-reload before update')
    fragment = props.get('FragmentPath', '')
    require(fragment, 'application service fragment unavailable')
    paths = [fragment] + words(props.get('DropInPaths', ''))
    baseline = {key: value for key, value in manager.items() if key == 'TMPDIR'}
    env, envfiles, command, cwd = dict(baseline), [], None, None
    allowed = {'Type', 'User', 'Group', 'WorkingDirectory', 'Environment', 'EnvironmentFile',
               'ExecStart', 'Restart', 'RestartSec', 'TimeoutStartSec', 'TimeoutStopSec'}
    for path in paths:
        section = None
        for line in contents(path).splitlines():
            line = line.strip()
            if not line or line.startswith(('#', ';')):
                continue
            if line.startswith('[') and line.endswith(']'):
                section = line[1:-1]
                require(section in {'Unit', 'Service', 'Install'}, 'unsupported service section')
                continue
            require('=' in line, 'unsupported multiline unit syntax')
            key, value = line.split('=', 1)
            key, value = key.strip(), value.strip()
            if section != 'Service':
                require(key in {'Description', 'After', 'Before', 'Wants', 'Requires', 'WantedBy'},
                        'unsupported unit dependency directive')
                continue
            require(key in allowed, 'unsupported service directive: '+key)
            if key == 'Environment':
                if not value:
                    env = dict(baseline)
                for item in words(value):
                    k, v = assignment(item)
                    env[k] = v
            elif key == 'EnvironmentFile':
                if not value:
                    envfiles = []
                else:
                    items = words(value)
                    require(len(items) == 1 and items[0].startswith('/'), 'unsupported EnvironmentFile path')
                    envfiles.append(items[0])
            elif key == 'ExecStart':
                if not value:
                    command = None
                else:
                    require(command is None, 'ambiguous multiple ExecStart commands')
                    command = words(value)
            elif key == 'WorkingDirectory':
                require(value.startswith('/'), 'WorkingDirectory must be an absolute literal')
                cwd = Path(value)
            elif key in {'User', 'Group'}:
                require(value == 'root', 'unsupported service user or group')
            elif key == 'Type':
                require(value == 'simple', 'unsupported service type')
    require(cwd == APP_ROOT and command, 'unsupported service CWD or missing command')
    for path in envfiles:
        env.update(env_file(path))
        protected(Path(path))
    require(not set(env) & {'NODE_OPTIONS', 'PYTHONPATH', 'LD_PRELOAD', 'LD_LIBRARY_PATH'},
            'unsupported runtime wrapper configuration')
    require(not any(k.startswith('PG') for k in env), 'unsupported ambient PostgreSQL configuration')
    if name in {'web', 'jobs'}:
        package = 'web' if name == 'web' else 'background-jobs'
        require(command[:4] == ['/usr/bin/pnpm', '--filter', package, 'start'],
                'unsupported Node service wrapper')
        tail = command[4:]
        require(name == 'web' or not tail, 'unsupported jobs startup options')
        require(not tail or (len(tail) == 4 and tail[0] == '--host' and tail[2] == '--port'
                            and tail[3].isdigit()), 'unsupported web startup options')
        cwd = APP_ROOT/'apps'/package
    elif name == 'ml':
        require(command[:2] == [str(APP_ROOT/'.venv/bin/python'), str(APP_ROOT/'python/main.py')],
                'unsupported Python service wrapper')
        tail = command[2:]
        require(len(tail) == 4 and tail[0] == '--host' and tail[2] == '--port' and tail[3].isdigit(),
                'unsupported Python startup options')
    else:
        require(command[:2] == [str(APP_ROOT/'.venv/bin/chroma'), 'run'], 'unsupported Chroma wrapper')
        tail = command[2:]
        require(len(tail) == 6 and set(tail[::2]) == {'--host', '--port', '--path'},
                'unsupported Chroma startup options')
        options = dict(zip(tail[::2], tail[1::2]))
        require(options['--port'].isdigit(), 'unsupported Chroma port')
        root(options['--path'], cwd)
    # dotenv/config fills absent Node keys; Python's two load_dotenv() calls
    # search from main.py and face_recognizer.py, not the updater's CWD.
    fallbacks = []
    if name in {'web', 'jobs'}:
        fallbacks = [cwd/'.env']
    elif name == 'ml':
        for candidates in ((APP_ROOT/'python/.env', APP_ROOT/'.env'),
                           (APP_ROOT/'python/services/analysis/.env', APP_ROOT/'python/services/.env',
                            APP_ROOT/'python/.env', APP_ROOT/'.env')):
            fallbacks += [next((p for p in candidates if p.exists()), APP_ROOT/'.env')]
    for path in fallbacks:
        protected(path)
        if path.exists():
            values = env_file(path)
            require(not any('#' in value for value in values.values()), 'unsupported dotenv inline comment syntax')
            for key, value in values.items():
                env.setdefault(key, value)
    require(not set(env) & {'NODE_OPTIONS', 'PYTHONPATH', 'LD_PRELOAD', 'LD_LIBRARY_PATH'} and
            not any(k.startswith('PG') for k in env), 'unsupported dotenv driver or wrapper configuration')
    require(not set(env) & {'XDG_CACHE_HOME', 'HF_HUB_CACHE', 'HUGGINGFACE_HUB_CACHE',
                           'TRANSFORMERS_CACHE', 'PYTHONHOME'} and env.get('HOME', '/root') == '/root',
            'unsupported dependency cache/home override; configure the native cache fields explicitly')
    if 'TMPDIR' in env:
        temporary(env['TMPDIR'])
    return dict(env=env, cwd=str(cwd), argv=command)

def decode(value):
    require(not re.search(r'%(?![0-9A-Fa-f]{2})', value), 'malformed PostgreSQL URL escape')
    value = unquote(value, errors='strict')
    require(not any(c in value for c in '\x00\r\n'), 'invalid PostgreSQL URL field')
    return value

def database(url):
    require(not any(ord(c) <= 32 for c in url), 'unsupported whitespace in PostgreSQL URL')
    u = urlsplit(url)
    require(u.scheme in {'postgresql', 'postgres'} and not u.fragment and u.hostname and
            u.username and u.password is not None and u.path.startswith('/'),
            'DATABASE_URL must select an explicit PostgreSQL host, user and database')
    require(re.fullmatch(r'[A-Za-z0-9.:-]+', u.hostname) and (u.port is None or 1 <= u.port <= 65535),
            'unsupported PostgreSQL host')
    decode(u.query)
    options = parse_qsl(u.query, keep_blank_values=True, strict_parsing=True, errors='strict')
    require(len(dict(options)) == len(options) and set(dict(options)) <= {'schema', 'sslmode'},
            'unsupported or duplicate Prisma connection option')
    options = dict(options)
    # Prisma TLS trust semantics are not silently mapped to libpq's different modes.
    tls = options.get('sslmode', 'prefer')
    require(tls in {'disable', 'prefer'}, 'unsupported TLS mapping; no downgrade attempted')
    # Quaint6 dbname() returns the first raw URL path segment, not a decoded name.
    db = u.path[1:]
    require(re.fullmatch(r'[A-Za-z0-9_.-]+', db), 'unsupported PostgreSQL database name')
    schema = options.get('schema', 'public')
    require(re.fullmatch(r'[A-Za-z_][A-Za-z0-9_ ]*', schema) and len(schema.encode()) <= 63,
            'invalid PostgreSQL schema')
    env = dict(PATH=os.environ['PATH'], HOME='/nonexistent', PGHOST=u.hostname,
               PGPORT=str(u.port or 5432), PGUSER=decode(u.username), PGPASSWORD=decode(u.password),
               PGDATABASE=db, PGSSLMODE=tls, PGGSSENCMODE='disable', PGCONNECT_TIMEOUT='5', PGPASSFILE='/dev/null',
               PGSERVICEFILE='/dev/null', PGOPTIONS='-c default_transaction_read_only=on -c statement_timeout=10000')
    ident = '"'+schema.replace('"', '""')+'"'
    fields = [('Folder', 'path'), ('Job', 'videoPath'), ('Job', 'thumbnailPath'),
              ('Video', 'source'), ('Video', 'thumbnailUrl'), ('ChatMessage', 'stitchedVideoPath'),
              ('Export', 'filePath')]
    selects = ['SELECT "'+col+'" AS path FROM '+ident+'."'+table+'"' for table, col in fields]
    sql = 'BEGIN READ ONLY; SELECT COALESCE(json_agg(left(path,4097) ORDER BY path),\'[]\'::json) FROM (' + \
          'SELECT path FROM (' + ' UNION '.join(selects) + ') AS all_roots ' + \
          'WHERE path IS NOT NULL AND path <> \'\' LIMIT 10001) AS roots; COMMIT;'
    p = subprocess.run(['psql', '-X', '-w', '-qAt', '-v', 'ON_ERROR_STOP=1'], input=sql,
                       env=env, capture_output=True, text=True, timeout=20)
    require(p.returncode == 0, 'configured PostgreSQL/schema inventory unavailable; no fallback attempted')
    paths = json.loads(p.stdout)
    require(isinstance(paths, list) and len(paths) <= 10000 and
            all(isinstance(v, str) and len(v) <= 4096 for v in paths),
            'PostgreSQL root inventory exceeds supported 10000 paths / 4096 characters')
    return paths

def discover():
    require(APP_ROOT.is_dir() and APP_ROOT.resolve() == APP_ROOT, 'unsupported application-root alias')
    for keep in sys.argv[2:]:
        require(keep and not keep.startswith('/') and not keep.endswith('/') and
                '//' not in keep and not set(keep.split('/')) & {'.', '..'}, 'invalid caller keep')
        root(keep, APP_ROOT)
    # Manager-provided path/driver fields would otherwise escape the unit grammar.
    def manager_pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, 'duplicate manager environment field')
            result[key] = value
        return result
    manager = json.loads(query('systemctl', 'show-environment', '--output=json'), object_pairs_hook=manager_pairs)
    require(type(manager) is dict and all(type(v) is str for v in manager.values()),
            'unsupported manager environment JSON grammar')
    for key in manager:
        require(key in {'LANG', 'LANGUAGE', 'LC_ALL', 'PATH', 'TMPDIR'} or key.startswith('LC_'),
                 'unsupported manager environment; configure application units explicitly')
    if 'TMPDIR' in manager:
        temporary(manager['TMPDIR'])
    for rel in ('.env', '.env.system', '.data', '.venv', 'media', 'ml-models',
                '.locations.json', 'apps/web/.env.production'):
        protected(APP_ROOT/rel)
    # Parse mandatory legacy config even when a unit deliberately resets its files.
    env_file(APP_ROOT/'.env')
    env_file(APP_ROOT/'.env.system')
    contents(APP_ROOT/'apps/web/.env.production')
    units = {name: service(name, manager) for name in ('web', 'jobs', 'ml', 'chroma')}
    require(units['web']['env'].get('DATABASE_URL') == units['jobs']['env'].get('DATABASE_URL'),
            'web/jobs database mappings differ; reconcile before update')
    urls = set()
    host = set()
    js = {'PROCESSED_VIDEOS_DIR': '.results', 'THUMBNAILS_PATH': '.thumbnails',
          'FACES_DIR': '.faces', 'UNKNOWN_FACES_DIR': '.unknown_faces',
          'STITCHED_VIDEOS_DIR': 'output-videos', 'EXPORTS_DIR': '/app/data/.exports',
          'XENOVA_MODEL_CACHE_DIR': '/ml-models/embedding-models'}
    for name, unit in units.items():
        e, cwd = unit['env'], Path(unit['cwd'])
        if name in {'web', 'jobs'}:
            require(e.get('DATABASE_URL'), 'missing effective DATABASE_URL')
            urls.add(e['DATABASE_URL'])
            root('.locations.json', cwd)
            for key, default in js.items():
                root(e.get(key) or default, cwd)
            # Additional native readers have different defaults/anchors.
            root(e.get('THUMBNAILS_PATH') or '/app/data/.thumbnails', cwd)
            root(e.get('FACES_DIR') or '.faces_db', cwd)
            root(e.get('THUMBNAILS_PATH') or '.thumbnails', MEDIA)
        if name == 'ml':
            defaults = {'YOLO_CONFIG_DIR': '/ml-models/ultralytics', 'DEEPFACE_HOME': '/root',
                        'TRANSCRIPTION_MODEL_CACHE': 'ml-models/.whisper', 'TORCH_HOME': '/root/.cache/torch',
                        'HF_HOME': '/ml-models/huggingface', 'THUMBNAILS_PATH': '/app/data/.thumbnails/',
                        'FACES_DIR': '.faces', 'UNKNOWN_FACES_DIR': '.unknown_faces'}
            for key, default in defaults.items():
                root(e.get(key, default), cwd)
        for key in ('KNOWN_FACES_FILE', 'KNOWN_FACES_FILE_LOADED'):
            if e.get(key):
                root(e[key], cwd)
        if e.get('HOST_MEDIA_PATH'):
            value = absolute(e['HOST_MEDIA_PATH'], cwd)
            protected(value)
            host.add(str(value))
        require(e.get('USE_EXTERNAL_HOST', '').lower() not in {'1', 'true'},
                'external-host path translation is unsupported by native media wiring')
    require(len(host) == 1, 'missing or ambiguous native HOST_MEDIA_PATH')
    target = Path(next(iter(host)))
    require(target.is_dir(), 'configured native media directory unavailable')
    protected(MEDIA)
    require(not os.path.lexists(MEDIA) or (MEDIA.is_dir() and MEDIA.resolve() == target.resolve()),
            '/media/videos conflicts with HOST_MEDIA_PATH; reconcile existing data without overwriting it')
    for url in urls:
        for value in database(url):
            if re.match(r'^https?://', value):
                continue
            if value.startswith('file:'):
                u = urlsplit(value)
                require(u.netloc in {'', 'localhost'} and not u.query and not u.fragment,
                        'unsupported database file URL')
                value = decode(u.path)
            require(not re.match(r'^[A-Za-z][A-Za-z0-9+.-]*:', value), 'unsupported database path scheme')
            for name in ('web', 'jobs', 'ml'):
                root(value, units[name]['cwd'])
    return dict(keeps=sorted(keeps), roots=sorted(roots), files=fingerprints, units=units, manager=manager,
                media_target=str(target), media_exists=os.path.lexists(MEDIA))

try:
    mode = sys.argv[1]
    if mode == 'discover':
        print(json.dumps(discover(), sort_keys=True))
    else:
        plan = json.loads(Path(sys.argv[2]).read_text())
        if mode == 'keeps':
            sys.stdout.buffer.write(b''.join(p.encode()+b'\0' for p in plan['keeps']))
        elif mode == 'media':
            target = Path(plan['media_target'])
            require(target.is_dir(), 'native media target disappeared')
            if os.path.lexists(MEDIA):
                require(MEDIA.is_dir() and MEDIA.resolve() == target.resolve(), 'native media mapping changed')
            else:
                MEDIA.parent.mkdir(parents=True, exist_ok=True)
                MEDIA.symlink_to(target, target_is_directory=True)
        elif mode == 'migrate':
            env = dict(os.environ)
            for key in list(env):
                if key.startswith('PG') or key in {'NODE_OPTIONS', 'LD_PRELOAD', 'LD_LIBRARY_PATH'}:
                    del env[key]
            env.update(plan['units']['web']['env'])
            os.execvpe('pnpm', ['pnpm', '--filter', 'prisma', 'migrate:deploy'], env)
        else:
            raise ValueError('unknown state operation')
except (OSError, ValueError, RuntimeError, KeyError, subprocess.SubprocessError) as error:
    # Do not print input text, credentials, subprocess stderr or DATABASE_URL.
    print('Edit-Mind persistence refused: '+str(error) if isinstance(error, Refusal)
          else 'Edit-Mind persistence refused: inventory unavailable', file=sys.stderr)
    sys.exit(65)
PY
  }

  if [[ ! -d /opt/edit-mind ]]; then
    msg_error "No ${APP} Installation Found!"
    exit 65
  fi

  if check_for_gh_release "edit-mind" "IliasHad/edit-mind"; then
    local before after keep_file declaration service
    local -a caller_keeps=()
    case "${CLEAN_INSTALL_KEEP:-}" in *$'\n'* | *$'\r'* | *$'\t'*) exit 65 ;; esac
    read -r -a caller_keeps <<< "${CLEAN_INSTALL_KEEP:-}"
    if declaration=$(declare -p CLEAN_INSTALL_KEEP_PATHS 2> /dev/null); then
      [[ "$declaration" =~ ^declare\ -[^[:space:]]*a[^[:space:]]*\  ]] || exit 65
      [[ ! "$declaration" =~ ^declare\ -[^[:space:]]*r ]] || exit 65
      caller_keeps+=("${CLEAN_INSTALL_KEEP_PATHS[@]}")
    fi
    before=$(mktemp)
    after=$(mktemp)
    keep_file=$(mktemp)
    chmod 0600 "$before" "$after" "$keep_file"
    edit_mind_state discover "${caller_keeps[@]}" > "$before"

    msg_info "Stopping Services"
    for service in edit-mind-web edit-mind-jobs edit-mind-ml edit-mind-chroma; do
      systemctl stop "$service"
    done
    msg_ok "Stopped Services"

    edit_mind_state discover "${caller_keeps[@]}" > "$after"
    if ! cmp -s "$before" "$after"; then
      msg_error "Edit-Mind configuration or database paths changed while quiescing; retry after reconciling writers"
      exit 65
    fi
    edit_mind_state keeps "$before" > "$keep_file"
    local -a discovered_keeps=()
    mapfile -d '' -t discovered_keeps < "$keep_file"
    CLEAN_INSTALL_KEEP_PATHS+=("${discovered_keeps[@]}")
    edit_mind_state media "$before"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "edit-mind" "IliasHad/edit-mind" "tarball"

    msg_info "Rebuilding Application"
    cd /opt/edit-mind || exit
    $STD pnpm install --prefer-frozen-lockfile
    $STD pnpm --filter prisma generate
    $STD pnpm run build:web
    $STD pnpm rebuild @tailwindcss/oxide rollup onnxruntime-node
    $STD pnpm run build:background-jobs
    msg_ok "Rebuilt Application"

    msg_info "Running Migrations"
    cd /opt/edit-mind || exit
    edit_mind_state migrate "$before"
    msg_ok "Ran Migrations"

    msg_info "Starting Services"
    for service in edit-mind-chroma edit-mind-ml edit-mind-jobs edit-mind-web; do
      systemctl start "$service"
      systemctl is-active --quiet "$service"
    done
    rm -f "$before" "$after" "$keep_file"
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc") --script-id "edit-mind" -- "$@"
