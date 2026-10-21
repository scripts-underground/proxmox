#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://docs.paperless-ngx.com/ | Github: https://github.com/paperless-ngx/paperless-ngx

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Paperless-ngx"
var_tags="${var_tags:-document;management}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-3072}"
var_disk="${var_disk:-12}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies (Patience)"
  $STD apt install -y \
    redis \
    build-essential \
    imagemagick \
    fonts-liberation \
    optipng \
    libpq-dev \
    libmagic-dev \
    libzbar0t64 \
    poppler-utils \
    default-libmysqlclient-dev \
    automake \
    libtool \
    pkg-config \
    libtiff-dev \
    libpng-dev \
    libleptonica-dev \
    unpaper \
    icc-profiles-free \
    qpdf \
    libleptonica6 \
    libxml2 \
    pngquant \
    zlib1g \
    tesseract-ocr \
    tesseract-ocr-eng \
    ghostscript
  msg_ok "Installed Dependencies"

  PG_VERSION="16" setup_postgresql
  PG_DB_NAME="paperlessdb" PG_DB_USER="paperless" setup_postgresql_db
  PYTHON_VERSION="3.13" setup_uv
  fetch_and_deploy_gh_release "paperless" "paperless-ngx/paperless-ngx" "prebuild" "v2.20.15" "/opt/paperless" "paperless*tar.xz"

  msg_info "Setup Paperless-ngx"
  cd /opt/paperless || exit
  rm -rf /opt/paperless/docker
  $STD uv sync --all-extras
  local selected_tag
  selected_tag="${var_appversion:-v2.20.15}"
  curl -fsSL "https://raw.githubusercontent.com/paperless-ngx/paperless-ngx/$selected_tag/paperless.conf.example" -o /opt/paperless/paperless.conf
  mkdir -p /opt/paperless_data/{consume,data,media,trash}
  mkdir -p /opt/paperless/static
  SECRET_KEY="$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32)"
  cat << EOF > ~/paperless-ngx.creds

Paperless-ngx Secret Key: $SECRET_KEY
Paperless-ngx WebUI User: admin
Paperless-ngx WebUI Password: $PG_DB_PASS
EOF
  sed -i \
    -e 's|#PAPERLESS_REDIS=redis://localhost:6379|PAPERLESS_REDIS=redis://localhost:6379|' \
    -e "s|#PAPERLESS_CONSUMPTION_DIR=../consume|PAPERLESS_CONSUMPTION_DIR=/opt/paperless_data/consume|" \
    -e "s|#PAPERLESS_DATA_DIR=../data|PAPERLESS_DATA_DIR=/opt/paperless_data/data|" \
    -e "s|#PAPERLESS_MEDIA_ROOT=../media|PAPERLESS_MEDIA_ROOT=/opt/paperless_data/media|" \
    -e "s|#PAPERLESS_EMPTY_TRASH_DIR=|PAPERLESS_EMPTY_TRASH_DIR=/opt/paperless_data/trash|" \
    -e "s|#PAPERLESS_STATICDIR=../static|PAPERLESS_STATICDIR=/opt/paperless/static|" \
    -e 's|#PAPERLESS_DBHOST=localhost|PAPERLESS_DBHOST=localhost|' \
    -e 's|#PAPERLESS_DBPORT=5432|PAPERLESS_DBPORT=5432|' \
    -e "s|#PAPERLESS_DBNAME=paperless|PAPERLESS_DBNAME=$PG_DB_NAME|" \
    -e "s|#PAPERLESS_DBUSER=paperless|PAPERLESS_DBUSER=$PG_DB_USER|" \
    -e "s|#PAPERLESS_DBPASS=paperless|PAPERLESS_DBPASS=$PG_DB_PASS|" \
    -e "s|#PAPERLESS_SECRET_KEY=change-me|PAPERLESS_SECRET_KEY=$SECRET_KEY|" \
    /opt/paperless/paperless.conf
  cd /opt/paperless/src || exit
  # Paperless loads this file with python-dotenv itself. Shell sourcing corrupts
  # valid unquoted JSON/regex settings and is not its configuration grammar.
  $STD uv run -- python manage.py migrate
  msg_ok "Setup Paperless-ngx"

  msg_info "Setting up admin Paperless-ngx User & Password"
  $STD uv run -- python /opt/paperless/src/manage.py shell << EOF
from django.contrib.auth import get_user_model
UserModel = get_user_model()
user = UserModel.objects.create_user('admin', password='$PG_DB_PASS')
user.is_superuser = True
user.is_staff = True
user.save()
EOF
  msg_ok "Set up admin Paperless-ngx User & Password"

  setup_nltk "snowball_data stopwords punkt_tab" "/usr/share/nltk_data"
  for policy_file in /etc/ImageMagick-6/policy.xml /etc/ImageMagick-7/policy.xml; do
    if [[ -f "$policy_file" ]]; then
      sed -i -e 's/rights="none" pattern="PDF"/rights="read|write" pattern="PDF"/' "$policy_file"
    fi
  done

  msg_info "Creating Services"
  cat << EOF > /etc/systemd/system/paperless-scheduler.service
[Unit]
Description=Paperless Celery beat
Requires=redis.service

[Service]
WorkingDirectory=/opt/paperless/src
ExecStart=uv run -- celery --app paperless beat --loglevel INFO
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  cat << EOF > /etc/systemd/system/paperless-task-queue.service
[Unit]
Description=Paperless Celery Workers
Requires=redis.service
After=postgresql.service

[Service]
WorkingDirectory=/opt/paperless/src
ExecStart=uv run -- celery --app paperless worker --loglevel INFO
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  cat << EOF > /etc/systemd/system/paperless-consumer.service
[Unit]
Description=Paperless consumer
Requires=redis.service

[Service]
WorkingDirectory=/opt/paperless/src
ExecStartPre=/bin/sleep 2
ExecStart=uv run -- python manage.py document_consumer
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  cat << EOF > /etc/systemd/system/paperless-webserver.service
[Unit]
Description=Paperless webserver
After=network.target
Wants=network.target
Requires=redis.service

[Service]
WorkingDirectory=/opt/paperless/src
ExecStart=uv run -- granian --interface asgi --ws "paperless.asgi:application"
Restart=on-failure
RestartSec=5
Environment=GRANIAN_HOST=::
Environment=GRANIAN_PORT=8000
Environment=GRANIAN_WORKERS=1

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now paperless-webserver paperless-scheduler paperless-task-queue paperless-consumer
  msg_ok "Created Services"

  read -r -p "${TAB3}Would you like to add Adminer? <y/N> " prompt || true
  if [[ "${prompt,,}" =~ ^(y|yes)$ ]]; then
    setup_adminer
  fi
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8000${CL}"
  echo -e "${INFO}${YW}Run 'cat paperless-ngx.creds' inside the container for login details.${CL}"
}

function update_script() {
  # This hook is bundled alone. Keep its read-only validator self-contained and
  # run it before resource maintenance, provisioning, source fetch or service work.
  local target="${var_appversion:-v2.20.15}" config_python=/usr/bin/python3 plan expected_sha convert due=no checker_rc
  [[ -d /opt/paperless && -f /opt/paperless/paperless.conf ]] || {
    msg_error "Missing existing Paperless source/configuration"
    exit 65
  }
  if [[ -x /opt/paperless/.venv/bin/python ]]; then
    config_python=/opt/paperless/.venv/bin/python
  elif [[ -x /opt/paperless/venv/bin/python ]]; then config_python=/opt/paperless/venv/bin/python; fi
  if [[ "$target" == latest ]]; then
    target=$(curl -fsSL https://api.github.com/repos/paperless-ngx/paperless-ngx/releases/latest | jq -er '.tag_name') || exit 250
  fi
  function paperless_config_format() {
    "$config_python" -B - /opt/paperless/paperless.conf /opt/paperless "$target" "$1" "${2:-}" << 'PY'
import fnmatch,hashlib,io,json,os,pathlib,re,stat,sys,tempfile
from dotenv import dotenv_values,set_key
from dotenv.parser import parse_stream
p,root=map(pathlib.Path,sys.argv[1:3]);target,mode,expected=sys.argv[3:];raw=p.read_bytes();text=raw.decode();sha=hashlib.sha256(raw).hexdigest()
def fail(message):
 print('Paperless configuration preflight: '+message,file=sys.stderr);sys.exit(65)
if any(binding.error for binding in parse_stream(io.StringIO(text))):fail('malformed dotenv; correct the existing file before updating')
values=dotenv_values(stream=io.StringIO(text));patterns=None
try:
 if 'PAPERLESS_CONSUMER_IGNORE_PATTERNS' in values:
  patterns=json.loads(values['PAPERLESS_CONSUMER_IGNORE_PATTERNS'])
  if not isinstance(patterns,list) or not all(isinstance(x,str) for x in patterns):raise ValueError()
except (TypeError,ValueError):fail('ignore patterns must be a JSON string array')
markers=re.findall(r'^# scripts-underground: consumer-ignore-format=(.*)$',text,re.M)
if len(markers)>1 or (markers and markers[0] not in ('glob-v2','regex-v3')):fail('ambiguous format provenance; retain settings and resolve the marker')
match=re.fullmatch(r'v?(\d+)\.\d+\.\d+',target)
if not match or int(match[1]) not in (2,3):fail('select an explicit supported v2/v3 release')
major=int(match[1]);fmt=markers[0] if markers else None;version='';new_patterns=[];new_dirs=[];existing_dirs=[]
try:
 if 'PAPERLESS_CONSUMER_IGNORE_DIRS' in values:
  existing_dirs=json.loads(values['PAPERLESS_CONSUMER_IGNORE_DIRS'])
  if not isinstance(existing_dirs,list) or not all(isinstance(x,str) for x in existing_dirs):raise ValueError()
except (TypeError,ValueError):fail('ignore directories must be a JSON string array')
if major==3 or fmt or (root/'pyproject.toml').exists():
 try:
  try:import tomllib
  except ImportError:import tomli as tomllib
  version=tomllib.loads((root/'pyproject.toml').read_text())['project']['version']
  if not re.fullmatch(r'\d+\.\d+\.\d+',version):raise ValueError()
 except (OSError,KeyError,TypeError,ValueError):fail('installed source version/format is unproven; repair its metadata before an override')
 if not fmt:fmt='glob-v2' if version.startswith('2.') else 'regex-v3' if version.startswith('3.') else None
 if not fmt:fail('unknown installed source format')
 if major==2 and (fmt=='regex-v3' or version.startswith('3.')):fail('refusing a v3 configuration/source downgrade; retain the explicit v3 release')
 if major==3 and version.startswith('2.') and version!='2.20.15':fail('upgrade to v2.20.15 before requesting v3, as required by upstream')
 if mode=='apply' and not version.startswith('3.'):fail('selected v3 source is not installed; glob settings retained')
convert=major==3 and fmt=='glob-v2' and patterns is not None
if major==3 and fmt=='regex-v3' and patterns is not None:
 try:
  for pattern in patterns:re.compile(pattern)
 except re.error:fail('invalid explicit regex; no glob guess was applied')
if convert:
 for pattern in patterns:
  if pattern.endswith('/*'):
    directory=pattern[:-2]
    if directory and '/' not in directory and not any(c in directory for c in '*?[') and not pathlib.PurePath(directory).suffix:
     # v2 trims the consumption root; v3 watchfiles checks every absolute
     # path component. The same literal name in that root would ignore ALL
     # documents after conversion, rather than just a descendant directory.
     consume=pathlib.Path(os.path.abspath(str(root/'src'/os.path.expanduser(values.get('PAPERLESS_CONSUMPTION_DIR') or '../consume'))))
     if directory in consume.parts or directory in consume.resolve().parts:
      fail('directory glob '+repr(pattern)+' collides with the consumption root in v3; keep v2.20.15 or explicitly configure the intended v3 rules')
     new_dirs.append(directory);continue
  last_class=pattern[pattern.rfind('['):] if '[' in pattern and pattern.endswith(']') else ''
  if '/' in pattern or pattern.endswith(('*','?')) or (last_class and fnmatch.fnmatchcase('/',last_class)):
   fail('directory glob '+repr(pattern)+' cannot be represented exactly in v3; keep v2.20.15 or explicitly configure the intended v3 file/directory rules')
  new_patterns.append(fnmatch.translate(pattern))
keeps=[]
for key in ('PAPERLESS_DATA_DIR','PAPERLESS_MEDIA_ROOT','PAPERLESS_CONSUMPTION_DIR','PAPERLESS_EMPTY_TRASH_DIR'):
 value=values.get(key)
 if not value:continue
 path=pathlib.Path(os.path.abspath(str(root/'src'/os.path.expanduser(value))))
 if path==root:fail(key+' cannot share the application source root')
 if root in path.parents:keeps.append(str(path.relative_to(root)))
if mode!='inspect':
 if expected!=sha:fail('configuration changed concurrently; user changes retained')
 if mode=='tag' and convert and not markers:text+='' if text.endswith('\n') else '\n';text+='# scripts-underground: consumer-ignore-format=glob-v2\n'
 elif mode=='apply' and convert:
  fd,name=tempfile.mkstemp(prefix='.paperless-format.',dir=p.parent);os.close(fd);q=pathlib.Path(name)
  try:
   # Dotenv unescapes backslashes even in single-quoted values. Preserve JSON's
   # own escapes through that outer grammar before the app calls json.loads.
   q.write_text(text);set_key(str(q),'PAPERLESS_CONSUMER_IGNORE_PATTERNS',json.dumps(new_patterns).replace('\\','\\\\'),quote_mode='always')
   if new_dirs:set_key(str(q),'PAPERLESS_CONSUMER_IGNORE_DIRS',json.dumps(list(dict.fromkeys(existing_dirs+new_dirs))).replace('\\','\\\\'),quote_mode='always')
   text=re.sub(r'^# scripts-underground: consumer-ignore-format=glob-v2$', '# scripts-underground: consumer-ignore-format=regex-v3',q.read_text(),flags=re.M)
  finally:q.unlink()
 s=p.stat();fd,name=tempfile.mkstemp(prefix='.paperless-conf.',dir=p.parent)
 try:
  with os.fdopen(fd,'w') as f:f.write(text);f.flush();os.fchmod(f.fileno(),stat.S_IMODE(s.st_mode));os.fchown(f.fileno(),s.st_uid,s.st_gid)
  os.replace(name,p)
 finally:
  if os.path.exists(name):os.unlink(name)
 sha=hashlib.sha256(p.read_bytes()).hexdigest()
print(json.dumps({'sha':sha,'convert':convert,'keeps':keeps}))
PY
  }
  plan=$(paperless_config_format inspect) || exit 65
  expected_sha=$(jq -er '.sha' <<< "$plan") || exit 65
  convert=$(jq -r '.convert' <<< "$plan")
  local var_appversion="$target"
  header_info
  check_container_storage
  check_container_resources
  if check_for_gh_release "paperless" "paperless-ngx/paperless-ngx" "$target" "v3 requires an explicit override"; then due=yes; else
    checker_rc=$?
    [[ "$checker_rc" == 1 ]] || exit "$checker_rc"
  fi
  if [[ "$due" == yes || "$convert" == true ]]; then
    if ! grep -q 'uv run' /etc/systemd/system/paperless-webserver.service; then
      local confirm
      read -rp 'Have you created a snapshot before migrating to uv? [y/N]: ' confirm || true
      [[ "${confirm:-}" =~ ^([yY]|[yY][eE][sS])$ ]] || exit 65
    fi
    local -a configured_paths=()
    local paths_file
    paths_file=$(mktemp) || exit $?
    jq -j '.keeps[] | .+"\u0000"' <<< "$plan" > "$paths_file" || exit 65
    mapfile -d '' -t configured_paths < "$paths_file"
    rm -f -- "$paths_file"
    local -a CLEAN_INSTALL_KEEP_PATHS=("${CLEAN_INSTALL_KEEP_PATHS[@]}" paperless.conf data media consume trash venv "${configured_paths[@]}")
    systemctl stop paperless-consumer paperless-webserver paperless-scheduler paperless-task-queue
    if [[ "$convert" == true ]]; then
      plan=$(paperless_config_format tag "$expected_sha") || exit 65
      expected_sha=$(jq -r '.sha' <<< "$plan")
    fi
    PYTHON_VERSION="3.13" setup_uv
    var_appversion="$target" CLEAN_INSTALL=1 fetch_and_deploy_gh_release "paperless" "paperless-ngx/paperless-ngx" prebuild "$target" /opt/paperless 'paperless*tar.xz'
    var_appversion='' CLEAN_INSTALL=1 fetch_and_deploy_gh_release jbig2enc ie13/jbig2enc tarball latest /opt/jbig2enc
    . /etc/os-release
    if [[ "$VERSION_CODENAME" == bookworm ]]; then setup_gs; else ensure_dependencies ghostscript; fi
    cd /opt/paperless || exit
    $STD uv sync --all-extras
    if [[ "$convert" == true ]]; then paperless_config_format apply "$expected_sha" > /dev/null || exit 65; fi
    cd /opt/paperless/src || exit
    $STD uv run -- python manage.py migrate
    setup_nltk "snowball_data stopwords punkt_tab" /usr/share/nltk_data
  fi
  # Read every base/drop-in directive before adding defaults. Explicit Restart=no
  # and an independently configured RestartSec are both user-owned choices.
  local service unit_text
  for service in consumer scheduler task-queue webserver; do
    unit_text=$(systemctl cat -- "paperless-$service.service") || exit $?
    "$config_python" -B - "$service" "$unit_text" << 'PY' || exit 65
import configparser,os,pathlib,sys
service,text=sys.argv[1:];cfg=configparser.RawConfigParser(strict=False);cfg.optionxform=str;cfg.read_string(text)
if cfg.has_option('Service','Restart'):sys.exit(0)
p=pathlib.Path('/etc/systemd/system')/('paperless-'+service+'.service.d')/'10-scripts-underground-restart.conf'
p.parent.mkdir(parents=True,exist_ok=True)
body='[Service]\nRestart=on-failure\n'+('' if cfg.has_option('Service','RestartSec') else 'RestartSec=5\n')
try:
 fd=os.open(p,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o644)
except FileExistsError:sys.exit(0)
with os.fdopen(fd,'w') as f:f.write(body)
PY
  done
  systemctl daemon-reload
  if [[ "$due" == yes || "$convert" == true ]]; then systemctl start paperless-consumer paperless-webserver paperless-scheduler paperless-task-queue; fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
