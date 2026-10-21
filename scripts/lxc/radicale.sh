#!/usr/bin/env bash
# shellcheck disable=SC2034
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://radicale.org/ | Github: https://github.com/Kozea/Radicale

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Radicale"
var_tags="${var_tags:-calendar}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y apache2-utils
  msg_ok "Installed Dependencies"

  PYTHON_VERSION="3.13" setup_uv
  fetch_and_deploy_gh_release "Radicale" "Kozea/Radicale" "tarball" "latest" "/opt/radicale"
  local auth_extras
  auth_extras=$(
    uv run --no-project --python 3.13 python - /opt/radicale/pyproject.toml << 'PY'
import pathlib,sys,tomllib
p=pathlib.Path(sys.argv[1]);meta=tomllib.loads(p.read_text()) if p.exists() else {}
extras=meta.get('project',{}).get('optional-dependencies',{})
if not isinstance(extras,dict):sys.exit(65)
for name in ('bcrypt','argon2'):
 if name in extras and (not isinstance(extras[name],list) or not all(isinstance(v,str) for v in extras[name])):sys.exit(65)
print(' '.join('--extra '+name for name in ('bcrypt','argon2') if extras.get(name)))
PY
  ) || exit 65

  msg_info "Setting up Radicale"
  cd /opt/radicale || exit
  RNDPASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
  $STD htpasswd -c -b -5 /opt/radicale/users admin "$RNDPASS"
  cat << EOF > ~/radicale.creds
Radicale Credentials
Admin User: admin
Admin Password: $RNDPASS
EOF

  mkdir -p /etc/radicale
  cat << EOF > /etc/radicale/config
[server]
hosts = 0.0.0.0:5232

[auth]
type = htpasswd
htpasswd_filename = /opt/radicale/users
htpasswd_encryption = sha512

[storage]
type = multifilesystem
filesystem_folder = /var/lib/radicale/collections

[web]
type = internal
EOF
  msg_ok "Set up Radicale"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/radicale.service
[Unit]
Description=A simple CalDAV (calendar) and CardDAV (contact) server
After=network.target
Requires=network.target

[Service]
WorkingDirectory=/opt/radicale
ExecStart=/usr/local/bin/uv run ${auth_extras:+$auth_extras }-m radicale --config /etc/radicale/config
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now radicale
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:5232${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/radicale ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  PYTHON_VERSION="3.13" setup_uv
  local keep_file auth_extras unit_changed updated=no
  keep_file=$(mktemp) || exit $?
  # Match Radicale's RawConfigParser/filepath semantics. Preserve configured
  # credentials/storage/config inside the source root, including literal spaces.
  uv run --no-project --python 3.13 python - /etc/systemd/system/radicale.service /etc/radicale/config /opt/radicale > "$keep_file" << 'PY' || {
import configparser,os,pathlib,shlex,sys
unit,default,root=map(pathlib.Path,sys.argv[1:]);lines=unit.read_text().splitlines()
commands=[line.split('=',1)[1] for line in lines if line.startswith('ExecStart=')]
if len(commands)!=1:sys.exit(65)
args=shlex.split(commands[0]);config=str(default)
for i,arg in enumerate(args):
 if arg=='--config':config=args[i+1]
 elif arg.startswith('--config='):config=arg.split('=',1)[1]
cwd=next((line.split('=',1)[1] for line in lines if line.startswith('WorkingDirectory=')),str(root))
os.chdir(cwd);p=pathlib.Path(os.path.abspath(os.path.expanduser(config)))
parser=configparser.RawConfigParser()
if not parser.read(p):sys.exit(65)
values=[str(p),parser.get('auth','htpasswd_filename',fallback=''),parser.get('storage','filesystem_folder',fallback='')]
for value in values:
 if not value:continue
 path=pathlib.Path(os.path.abspath(os.path.expanduser(value)))
 if path==root:sys.exit(65)
 if root in path.parents:sys.stdout.buffer.write(os.fsencode(str(path.relative_to(root)))+b'\0')
PY
    rm -f -- "$keep_file"
    exit 65
  }
  local -a configured_paths=()
  mapfile -d '' -t configured_paths < "$keep_file"
  rm -f -- "$keep_file"
  local -a CLEAN_INSTALL_KEEP_PATHS=("${CLEAN_INSTALL_KEEP_PATHS[@]}" users "${configured_paths[@]}")
  if check_for_gh_release "Radicale" "Kozea/Radicale"; then
    msg_info "Stopping Service"
    systemctl stop radicale
    msg_ok "Stopped Service"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "Radicale" "Kozea/Radicale" "tarball" "latest" "/opt/radicale"
    updated=yes
  fi
  auth_extras=$(
    uv run --no-project --python 3.13 python - /opt/radicale/pyproject.toml << 'PY'
import pathlib,sys,tomllib
p=pathlib.Path(sys.argv[1]);meta=tomllib.loads(p.read_text()) if p.exists() else {}
extras=meta.get('project',{}).get('optional-dependencies',{})
if not isinstance(extras,dict):sys.exit(65)
for name in ('bcrypt','argon2'):
 if name in extras and (not isinstance(extras[name],list) or not all(isinstance(v,str) for v in extras[name])):sys.exit(65)
print(' '.join('--extra '+name for name in ('bcrypt','argon2') if extras.get(name)))
PY
  ) || exit 65
  unit_changed=$(
    uv run --no-project --python 3.13 python - /etc/systemd/system/radicale.service "$auth_extras" << 'PY'
import os,pathlib,re,shlex,stat,sys,tempfile
p=pathlib.Path(sys.argv[1]).resolve(strict=True);text=p.read_text();lines=text.splitlines(True);found=0
for i,line in enumerate(lines):
 if not line.startswith('ExecStart='):continue
 found+=1;value=line.rstrip('\r\n')
 match=re.fullmatch(r'(ExecStart=/usr/local/bin/uv run)(.*?)( -m radicale(?:[ \t].*)?)',value)
 if match:
  args=shlex.split(match[2]);kept=[];n=0
  while n<len(args):
   if args[n]=='--extra' and n+1<len(args) and args[n+1] in ('bcrypt','argon2'):n+=2;continue
   if args[n] in ('--extra=bcrypt','--extra=argon2'):n+=1;continue
   kept.append(args[n]);n+=1
  flags=shlex.join(kept+shlex.split(sys.argv[2]))
  lines[i]=match[1]+(' '+flags if flags else '')+match[3]+'\n'
 elif shlex.split(value.split('=',1)[1])==['/opt/radicale/start.sh']:
  lines[i]='ExecStart=/usr/local/bin/uv run '+(sys.argv[2]+' ' if sys.argv[2] else '')+'-m radicale --config /etc/radicale/config\n'
 else:sys.exit(65)
if found!=1:sys.exit(65)
new=''.join(lines)
if '[Unit]' not in new:new='[Unit]\n'+new
if not any(line.startswith('WorkingDirectory=') for line in lines):new=new.replace('[Service]\n','[Service]\nWorkingDirectory=/opt/radicale\n',1)
if new==text:print('no');sys.exit(0)
s=p.stat();fd,name=tempfile.mkstemp(prefix='.radicale-unit.',dir=p.parent)
try:
 with os.fdopen(fd,'w') as f:f.write(new);f.flush();os.fchmod(f.fileno(),stat.S_IMODE(s.st_mode));os.fchown(f.fileno(),s.st_uid,s.st_gid)
 os.replace(name,p)
finally:
 if os.path.exists(name):os.unlink(name)
print('yes')
PY
  ) || exit 65
  if [[ "$unit_changed" == yes ]]; then systemctl daemon-reload; fi
  if [[ "$updated" == yes ]]; then
    msg_info "Starting Service"
    systemctl start radicale
    msg_ok "Started Service"
    msg_ok "Updated Successfully!"
  elif [[ "$unit_changed" == yes ]]; then
    systemctl restart radicale
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
