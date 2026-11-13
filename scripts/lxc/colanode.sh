#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://colanode.com/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Colanode"
var_tags="${var_tags:-collaboration;notes;chat}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-16}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    build-essential \
    redis-server \
    nginx
  msg_ok "Installed Dependencies"

  PG_VERSION="17" PG_MODULES="pgvector" setup_postgresql
  PG_DB_NAME="colanode_db" PG_DB_USER="colanode" PG_DB_EXTENSIONS="vector" setup_postgresql_db
  NODE_VERSION="22" setup_nodejs

  fetch_and_deploy_gh_release "colanode" "colanode/colanode" "tarball"

  msg_info "Building Application"
  cd /opt/colanode || exit
  export NODE_OPTIONS="--max-old-space-size=4096"
  $STD npm install
  $STD npm run build -w @colanode/core
  $STD npm run build -w @colanode/crdt
  $STD npm run build -w @colanode/server
  $STD npm run build -w @colanode/client
  $STD npm run build -w @colanode/ui
  $STD npm run build -w @colanode/web
  $STD npm prune --production
  unset NODE_OPTIONS
  msg_ok "Built Application"

  msg_info "Configuring Application"
  mkdir -p /var/lib/colanode/storage /var/www/colanode
  cp -r /opt/colanode/apps/web/dist/. /var/www/colanode/
  cat << EOF > /opt/colanode/.env
POSTGRES_URL=postgresql://${PG_DB_USER}:${PG_DB_PASS}@127.0.0.1:5432/${PG_DB_NAME}
REDIS_URL=redis://127.0.0.1:6379
NODE_ENV=production
EOF
  msg_ok "Configured Application"

  msg_info "Configuring Nginx"
  create_self_signed_cert "colanode"
  cp /etc/ssl/colanode/colanode.crt /var/www/colanode/colanode.crt
  cat << EOF > /etc/nginx/sites-available/colanode
server {
    listen 4000 ssl;
    server_name _;
    root /var/www/colanode;
    index index.html;

    ssl_certificate /etc/ssl/colanode/colanode.crt;
    ssl_certificate_key /etc/ssl/colanode/colanode.key;

    add_header Cross-Origin-Opener-Policy "same-origin" always;
    add_header Cross-Origin-Embedder-Policy "require-corp" always;

    location ~ ^/(config|client)(/.*)?$ {
        client_max_body_size 0;
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location = /colanode.crt {
        default_type application/x-x509-ca-cert;
    }

    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
EOF
  ln -sf /etc/nginx/sites-available/colanode /etc/nginx/sites-enabled/colanode
  rm -f /etc/nginx/sites-enabled/default
  systemctl reload nginx
  msg_ok "Configured Nginx"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/colanode-server.service
[Unit]
Description=Colanode Server
After=network.target postgresql.service redis-server.service
Requires=postgresql.service redis-server.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/colanode
EnvironmentFile=/opt/colanode/.env
ExecStart=/usr/bin/node apps/server/dist/index.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now colanode-server
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URLs:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}https://${IP}:4000${CL} (Web UI)"
  echo -e "${INFO}${YW} Before using: import the self-signed cert into your browser:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}https://${IP}:4000/colanode.crt${CL}"
  echo -e "${INFO}${YW} Server URL to use inside the app:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}https://${IP}:4000/config${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/colanode ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  local stage rc=0 cleanup_rc=0 due=0 old_version='' old_source selected_version='' selected_tag='' latest_version=''
  local recovery_file="$HOME/.colanode-update-recovery" prior_stage='' recovery_published=0
  local -a inherited_keeps=("${CLEAN_INSTALL_KEEP_PATHS[@]}")
  local -a CLEAN_INSTALL_KEEP_PATHS=("${inherited_keeps[@]}" .env data)
  stage=$(mktemp -d /opt/.colanode-build.XXXXXX) || exit $?
  if [[ -e "$recovery_file" || -L "$recovery_file" ]]; then
    if [[ ! -f "$recovery_file" || -L "$recovery_file" ]]; then
      msg_error "Invalid Colanode recovery record: $recovery_file"
      _deploy_remove_owned_trees "$stage" || msg_error "Retained Colanode stage: $stage"
      exit 65
    fi
    prior_stage=$(< "$recovery_file")
    if [[ "$prior_stage" != /opt/.colanode-build.* || "$prior_stage" == */*/*/* || ! -d "$prior_stage" || -L "$prior_stage" || ! -f "$prior_stage/recovery.json" ]]; then
      msg_error "Invalid Colanode recovery stage: $prior_stage"
      _deploy_remove_owned_trees "$stage" || msg_error "Retained Colanode stage: $stage"
      exit 65
    fi
  fi
  if [[ -f "$HOME/.colanode" ]]; then
    old_version=$(< "$HOME/.colanode")
  elif [[ -f /opt/colanode_version.txt ]]; then
    old_version=$(< /opt/colanode_version.txt)
  fi
  old_version=$(_gh_version_from_tag "$old_version") || rc=$?
  if [[ "$rc" == 0 ]]; then selected_tag=$(get_latest_github_release "colanode/colanode" false) || rc=$?; fi
  if [[ "$rc" == 0 ]]; then latest_version=$(_gh_version_from_tag "$selected_tag") || rc=$?; fi
  if [[ "$rc" == 0 ]]; then
    [[ -n "$selected_tag" && -n "$latest_version" ]] || rc=250
  fi
  if [[ "$rc" == 0 ]]; then
    if [[ -z "$old_version" || "$old_version" != "$latest_version" || "${UPDATE_FORCE:-}" == 1 ]]; then due=1; fi
    old_source="$stage/no-old-source"

    # Hooks are transported individually. Keep the staged operation and its
    # cleanup in this hook, and explicitly propagate every failure.
    function colanode_update_staged() {
      local tag entry
      mkdir -p "$stage/home" "$stage/old-home" || return $?
      if [[ -n "$old_version" ]]; then
        if HOME="$stage/old-home" var_appversion='' FORCE_DEPLOY=1 CLEAN_INSTALL=0 \
          fetch_and_deploy_gh_release "colanode" "colanode/colanode" "tarball" "$old_version" "$stage/old"; then
          old_source="$stage/old"
        else
          msg_warn "Installed release source unavailable; proceeding without old-source comparison"
        fi
      else
        msg_warn "Installed release marker unavailable; proceeding without old-source comparison"
      fi
      tag="${var_appversion:-$selected_tag}"
      HOME="$stage/home" FORCE_DEPLOY=1 CLEAN_INSTALL=0 \
        fetch_and_deploy_gh_release "colanode" "colanode/colanode" "tarball" "$tag" "$stage/new" '' '' "$stage/selected.json" || return $?
      selected_version=$(< "$stage/home/.colanode") || return $?
      [[ -n "$selected_version" && -s "$stage/selected.json" ]] || return 65

      msg_info "Building Colanode in a private directory"
      (
        cd "$stage/new" || exit $?
        export NODE_OPTIONS="--max-old-space-size=4096"
        $STD npm install || exit $?
        $STD npm run build -w @colanode/core || exit $?
        $STD npm run build -w @colanode/crdt || exit $?
        $STD npm run build -w @colanode/server || exit $?
        $STD npm run build -w @colanode/client || exit $?
        $STD npm run build -w @colanode/ui || exit $?
        $STD npm run build -w @colanode/web || exit $?
        $STD npm prune --production || exit $?
      ) || return $?

      # Supply inherited keep paths as literal NUL-delimited data. The checker
      # reports actual conflicts; it never sources or interprets unit files.
      : > "$stage/keeps" || return $?
      for entry in "${CLEAN_INSTALL_KEEP_PATHS[@]}"; do printf '%s\0' "$entry" >> "$stage/keeps" || return $?; done
      local -a legacy_keeps=()
      read -r -a legacy_keeps <<< "${CLEAN_INSTALL_KEEP:-}"
      for entry in "${legacy_keeps[@]}"; do printf '%s\0' "$entry" >> "$stage/keeps" || return $?; done
      node - "$old_source" "$stage/new" /opt/colanode /var/www/colanode "$stage/keeps" "$stage/recovery.json" "${prior_stage:+$prior_stage/recovery.json}" << 'JS' || return $?
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const [oldRoot, incoming, live, web, keepFile, recordFile, priorFile] = process.argv.slice(2);
const hasBaseline = fs.existsSync(oldRoot);
const keeps = fs.readFileSync(keepFile).toString().split('\0').filter(Boolean);
const stat = p => { try { return fs.lstatSync(p); } catch (e) { if (e.code === 'ENOENT' || e.code === 'ENOTDIR') return null; throw e; } };
const identity = p => {
  const s = stat(p);
  if (!s) return null;
  if (s.isSymbolicLink()) return {type:'link', target:fs.readlinkSync(p)};
  if (s.isFile()) return {type:'file', mode:s.mode & 0o7777, hash:crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex')};
  return {type:s.isDirectory() ? 'directory' : 'other'};
};
const equalIdentity = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const prior = priorFile ? JSON.parse(fs.readFileSync(priorFile, 'utf8')) : {app:{}, web:{}};
if (priorFile && (prior.kind !== 'colanode-publication-v1' || !prior.app || !prior.web)) throw Error('Invalid Colanode recovery manifest');
const next = {kind:'colanode-publication-v1', app:{}, web:{}};
const same = (a, b) => {
  const x = stat(a), y = stat(b);
  if (!x || !y) return false;
  if (x.isSymbolicLink() && y.isSymbolicLink()) return fs.readlinkSync(a) === fs.readlinkSync(b);
  return x.isFile() && y.isFile() && (x.mode & 0o111) === (y.mode & 0o111) && fs.readFileSync(a).equals(fs.readFileSync(b));
};
const lockPath = path.join(live, 'package-lock.json');
let packages = {};
try { packages = JSON.parse(fs.readFileSync(lockPath, 'utf8')).packages || {}; } catch (_) {
  try { packages = JSON.parse(fs.readFileSync(path.join(incoming, 'package-lock.json'), 'utf8')).packages || {}; } catch (_) { packages = {}; }
}
const mountRoots = fs.readFileSync('/proc/self/mountinfo', 'utf8').split('\n').filter(Boolean).map(line => line.split(' ')[4].replace(/\\(040|011|012|134)/g, (_, n) => ({'040':' ', '011':'\t', '012':'\n', '134':'\\'})[n]));
const inMount = (p, root) => mountRoots.some(m => m.startsWith(root + '/') && (p === m || p.startsWith(m + '/')));
const copiedAsset = rel => {
  const name = path.basename(rel);
  if (!/^apps\/(web\/public|desktop\/assets|mobile\/assets)\//.test(rel)) return null;
  if (name === 'emojis.db') return `assets/emojis/${rel.startsWith('apps/web/') ? 'emojis.min.db' : 'emojis.db'}`;
  if (name === 'icons.db') return `assets/icons/${rel.startsWith('apps/web/') ? 'icons.min.db' : 'icons.db'}`;
  if (name === 'emojis.svg') return 'assets/emojis/emojis.svg';
  if (name === 'icons.svg') return 'assets/icons/icons.svg';
  if (['satoshi-variable.woff2', 'satoshi-variable-italic.woff2', 'antonio.ttf'].includes(name)) return `assets/fonts/${name}`;
  if (name === 'favicon.ico') return 'assets/images/colanode-logo.ico';
  if (/^colanode-logo(?:-192\.jpg|-512\.jpg|\.png|\.ico|\.icns)$/.test(name)) return `assets/images/${name}`;
  return null;
};
const generated = rel => {
  if (/^packages\/(core|crdt|client|ui)\/(dist\/|tsconfig\.tsbuildinfo$)/.test(rel)) return true;
  if (/^apps\/(server|web)\/(dist\/|tsconfig\.tsbuildinfo$)/.test(rel)) return true;
  const parts = rel.split('/');
  for (let i = 0; i < parts.length; i++) {
    if (parts[i] !== 'node_modules' || !parts[i + 1]) continue;
    if (parts[i + 1] === '.package-lock.json' && i + 2 === parts.length) return true;
    if (parts[i + 1] === '.bin') return true;
    const end = i + (parts[i + 1].startsWith('@') ? 3 : 2);
    return Boolean(packages[parts.slice(0, end).join('/')]);
  }
  return false;
};
const conflict = p => { console.error(`Colanode update conflict: ${p}`); process.exitCode = 65; };
function scan(src, dst, rel = '', webMode = false) {
  for (const name of fs.readdirSync(src)) {
    const r = rel ? `${rel}/${name}` : name;
    const from = path.join(src, name), to = path.join(dst, name);
    const s = fs.lstatSync(from), d = stat(to);
    if (s.isDirectory() && !d) { scan(from, to, r, webMode); continue; }
    if (!s.isDirectory()) {
      const scope = webMode ? 'web' : 'app';
      next[scope][r] = {before:identity(to), after:identity(from)};
    }
    if (!d) continue;
    if (inMount(to, webMode ? web : live)) { conflict(to); continue; }
    if (!webMode && keeps.some(k => r === k || r.startsWith(k + '/'))) { conflict(to); continue; }
    if (s.isDirectory() && d.isDirectory()) { scan(from, to, r, webMode); continue; }
    if (s.isDirectory() !== d.isDirectory() || s.isSymbolicLink() !== d.isSymbolicLink()) { conflict(to); continue; }
    const previous = prior[webMode ? 'web' : 'app'][r];
    if (previous && (equalIdentity(identity(to), previous.after) || equalIdentity(identity(to), previous.before))) continue;
    if (webMode) {
      if (!same(to, path.join(live, 'apps/web/dist', r))) conflict(to);
      continue;
    }
    if (r === 'package-lock.json') continue;
    const copied = copiedAsset(r);
    if (copied && same(to, path.join(oldRoot, copied))) continue;
    const oldArtifact = path.join(oldRoot, r);
    if (stat(oldArtifact)) { if (!same(to, oldArtifact)) conflict(to); continue; }
    if (s.isSymbolicLink()) { if (!same(to, from)) conflict(to); continue; }
    if (!hasBaseline) continue;
    if (!generated(r)) conflict(to);
  }
}
scan(incoming, live);
scan(path.join(incoming, 'apps/web/dist'), web, '', true);
if (!process.exitCode) fs.writeFileSync(recordFile, JSON.stringify(next), {mode:0o600});
JS
      [[ -d "$stage/new/apps/web/dist" ]] || return 65
      local recovery_tmp recovery_rc
      recovery_tmp=$(mktemp "$HOME/.colanode-recovery.XXXXXX") || return $?
      printf '%s\n' "$stage" > "$recovery_tmp" || {
        recovery_rc=$?
        rm -f -- "$recovery_tmp"
        return "$recovery_rc"
      }
      mv -f -- "$recovery_tmp" "$recovery_file" || {
        recovery_rc=$?
        rm -f -- "$recovery_tmp"
        return "$recovery_rc"
      }
      recovery_published=1
      msg_info "Publishing Colanode"
      systemctl stop colanode-server || return $?
      _deploy_replace_contents "$stage/new" /opt/colanode 0 || return $?
      _deploy_replace_contents "$stage/new/apps/web/dist" /var/www/colanode 0 || return $?
      systemctl start colanode-server || return $?
    }

    function colanode_repair_nginx() {
      # Match only the literal historical generated site. Customized sites and
      # unusual link topologies remain operator-owned and are not rewritten.
      cat > "$stage/nginx-original" << 'NGINX'
server {
    listen 4000 ssl;
    server_name _;
    root /var/www/colanode;
    index index.html;

    ssl_certificate /etc/ssl/colanode/colanode.crt;
    ssl_certificate_key /etc/ssl/colanode/colanode.key;

    add_header Cross-Origin-Opener-Policy "same-origin" always;
    add_header Cross-Origin-Embedder-Policy "require-corp" always;

    location ~ ^/(config|client)(/.*)?$ {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location = /colanode.crt {
        default_type application/x-x509-ca-cert;
    }

    location / {
        try_files $uri $uri/ /index.html;
    }
}
NGINX
      local site=/etc/nginx/sites-available/colanode site_stage site_rc=0 enabled_entry enabled_count=0
      if [[ -f "$site" && ! -L "$site" ]] && [[ "$(stat -c %h "$site")" == 1 ]] && cmp -s "$site" "$stage/nginx-original"; then
        site_stage=$(mktemp -d /etc/nginx/sites-available/.colanode-update.XXXXXX) || return $?
        cp -a -- "$site" "$site_stage/original" || return $?
        cp -a -- "$site" "$site_stage/candidate" || return $?
        sed -e '/location ~ \^\/(config|client)/a\        client_max_body_size 0;' \
          -e 's/proxy_set_header Host \$host;/proxy_set_header Host $http_host;/' \
          "$stage/nginx-original" > "$site_stage/body" || return $?
        cat "$site_stage/body" > "$site_stage/candidate" || return $?
        # Debian's main configuration includes this directory. Recreate only
        # its directory entries as links, substituting the candidate for the
        # active site, then validate the complete nginx configuration before
        # publishing. Other includes still use their original absolute paths.
        mkdir "$site_stage/enabled" || return $?
        : > "$site_stage/selected-entries" || return $?
        find /etc/nginx/sites-enabled -mindepth 1 -maxdepth 1 -print0 > "$site_stage/entries" || return $?
        while IFS= read -r -d '' enabled_entry; do
          if [[ "$enabled_entry" -ef "$site" ]]; then
            ln -s -- "$site_stage/candidate" "$site_stage/enabled/${enabled_entry##*/}" || return $?
            printf '%s\0' "$site_stage/enabled/${enabled_entry##*/}" >> "$site_stage/selected-entries" || return $?
            enabled_count=$((enabled_count + 1))
          else
            ln -s -- "$enabled_entry" "$site_stage/enabled/${enabled_entry##*/}" || return $?
          fi
        done < "$site_stage/entries"
        if [[ "$enabled_count" == 0 ]] || ! grep -Fq '/etc/nginx/sites-enabled/*' /etc/nginx/nginx.conf; then
          msg_warn "Cannot validate the generated Colanode site through the active nginx configuration; site unchanged"
          _deploy_remove_owned_trees "$site_stage" || return $?
          return 0
        fi
        sed "s|/etc/nginx/sites-enabled/\\*|$site_stage/enabled/*|g" /etc/nginx/nginx.conf > "$site_stage/nginx.conf" || return $?
        if nginx -T -c "$site_stage/nginx.conf" > "$site_stage/dump"; then :; else
          site_rc=$?
          msg_error "Colanode nginx validation failed; candidate retained at $site_stage/candidate"
          return "$site_rc"
        fi
        while IFS= read -r -d '' enabled_entry; do
          if ! grep -Fxq "# configuration file $enabled_entry:" "$site_stage/dump"; then
            msg_error "Cannot establish that nginx validated $enabled_entry"
            return 65
          fi
        done < "$site_stage/selected-entries"
        if grep -Fxq "# configuration file $site:" "$site_stage/dump"; then
          msg_error "Colanode site is also included outside the validated site directory"
          return 65
        fi
        cmp -s "$site" "$site_stage/original" || {
          msg_error "Colanode nginx site changed during update"
          return 65
        }
        mv -f -- "$site_stage/candidate" "$site" || return $?
        systemctl reload nginx || site_rc=$?
        if [[ "$site_rc" != 0 ]]; then
          if cmp -s "$site" "$site_stage/body"; then
            mv -f -- "$site_stage/original" "$site" || msg_error "Restore nginx site from $site_stage/original"
          else
            msg_error "Colanode nginx site changed; original retained at $site_stage/original"
          fi
          return "$site_rc"
        fi
        _deploy_remove_owned_trees "$site_stage" || return $?
      else
        msg_warn "Custom or missing Colanode nginx site: check Host and client_max_body_size directives"
      fi
    }

    if [[ "$due" == 1 ]]; then colanode_update_staged || rc=$?; fi
    if [[ "$rc" == 0 ]]; then colanode_repair_nginx || rc=$?; fi
    if [[ "$rc" == 0 ]] && { [[ -n "$selected_version" ]] || [[ ! -f "$HOME/.colanode" && -n "$old_version" ]]; }; then
      local marker_stage marker_value="${selected_version:-$old_version}"
      marker_stage=$(mktemp "$HOME/.colanode-marker.XXXXXX") || rc=$?
      if [[ "$rc" == 0 ]]; then
        printf '%s\n' "$marker_value" > "$marker_stage" && mv -f -- "$marker_stage" "$HOME/.colanode" || rc=$?
        if [[ "$rc" != 0 ]]; then rm -f -- "$marker_stage" || msg_error "Retained marker stage: $marker_stage"; fi
      fi
    fi
    [[ "$rc" != 0 || "$due" != 1 ]] || msg_ok "Updated successfully!"
  else
    msg_error "Unable to check Colanode release (status=$rc)"
  fi
  cd /opt || cleanup_rc=$?
  if [[ "$recovery_published" == 1 && "$rc" != 0 ]]; then
    msg_error "Colanode update incomplete; recovery record retained at $recovery_file and $stage"
  else
    if [[ "$recovery_published" == 1 ]]; then rm -f -- "$recovery_file" || cleanup_rc=$?; fi
    if [[ "$cleanup_rc" == 0 ]]; then _deploy_remove_owned_trees "$stage" || {
      cleanup_rc=$?
      msg_error "Retained Colanode stage: $stage"
    }; fi
  fi
  if [[ "$rc" == 0 && "$cleanup_rc" == 0 && -n "$prior_stage" && "$prior_stage" != "$stage" ]]; then
    if [[ "$recovery_published" == 0 ]]; then rm -f -- "$recovery_file" || cleanup_rc=$?; fi
    if [[ "$cleanup_rc" == 0 ]]; then
      _deploy_remove_owned_trees "$prior_stage" || {
        cleanup_rc=$?
        msg_error "Retained previous Colanode recovery stage: $prior_stage"
      }
    fi
  elif [[ "$rc" != 0 && "$recovery_published" == 1 && -n "$prior_stage" ]]; then
    msg_warn "Previous Colanode attempt retained at $prior_stage"
  fi
  [[ "$rc" == 0 ]] || exit "$rc"
  [[ "$cleanup_rc" == 0 ]] || exit "$cleanup_rc"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc") --script-id "colanode" -- "$@"
