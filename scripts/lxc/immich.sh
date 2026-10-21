#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: vhsdream
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://immich.app

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Immich"
var_tags="${var_tags:-photos}"
var_disk="${var_disk:-20}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-6144}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_gpu="${var_gpu:-yes}"
var_lxc_git_repo="${var_lxc_git_repo:-immich-app/immich}"
var_lxc_release="${var_lxc_release:-v3.3.1}"

function install_script() {
  local RELEASE="${var_appversion:-$var_lxc_release}" retry_rc
  ARCH_RAW=$(uname -m)
  [[ "$ARCH_RAW" == "aarch64" ]] && ARCH_RAW="arm64"
  # shellcheck disable=SC2034
  ARCH=$(uname -m)
  if lscpu | grep -q 'GenuineIntel'; then
    echo ""
    echo ""
    echo -e "🤖 ${BL}Immich Machine-Learning Options${CL}"
    echo "─────────────────────────────────────────"
    echo "Please choose your machine-learning type:"
    echo ""
    echo " 1) CPU only (default)"
    echo " 2) **NEW** Intel OpenVINO CPU or iGPU"
    echo ""

    read -r -p "${TAB3}Select machine-learning type [1]: " ML_TYPE || true
    ML_TYPE="${ML_TYPE:-1}"
    if [[ "$ML_TYPE" == "2" ]]; then
      touch ~/.openvino
      $STD apt install -y --no-install-recommends patchelf
      if [[ -d /dev/dri ]]; then
        msg_info "Installing Intel OpenVINO dependencies"
        tmp_dir=$(mktemp -d)
        $STD pushd "$tmp_dir"
        curl_with_retry "https://raw.githubusercontent.com/${var_lxc_git_repo}/${RELEASE}/machine-learning/Dockerfile" "Dockerfile"
        readarray -t INTEL_URLS < <(
          sed -n "/intel-[igc|opencl]/p" ./Dockerfile | awk '{print $3}'
          sed -n "/libigdgmm12/p" ./Dockerfile | awk '{print $3}'
        )
        for url in "${INTEL_URLS[@]}"; do
          curl_with_retry "$url" "$(basename "$url")"
        done
        $STD apt install -y ./libigdgmm12*.deb
        rm ./libigdgmm12*.deb
        $STD apt install -y ./*.deb
        $STD apt-mark hold libigdgmm12
        $STD popd
        rm -rf "$tmp_dir"
        dpkg-query -W -f='${Version}\n' intel-opencl-icd > ~/.intel_version
        msg_ok "Installed Intel OpenVINO dependencies"
      fi
    fi
  fi

  msg_info "Installing dependencies"
  $STD apt install --no-install-recommends -y \
    git \
    redis \
    autoconf \
    build-essential \
    python3-dev \
    automake \
    cmake \
    jq \
    libtool \
    libltdl-dev \
    libgdk-pixbuf-2.0-dev \
    libbrotli-dev \
    libexif-dev \
    libexpat1-dev \
    libglib2.0-dev \
    libgsf-1-dev \
    libjpeg62-turbo-dev \
    libspng-dev \
    liblcms2-dev \
    libopenexr-dev \
    libgif-dev \
    librsvg2-dev \
    libexpat1 \
    libgcc-s1 \
    libgomp1 \
    liblqr-1-0 \
    libltdl7 \
    libopenjp2-7 \
    libopenjp2-7-dev \
    meson \
    ninja-build \
    pkg-config \
    mesa-utils \
    mesa-va-drivers \
    mesa-vulkan-drivers \
    ocl-icd-libopencl1 \
    tini \
    zlib1g \
    libio-compress-brotli-perl \
    libwebp7 \
    libwebpdemux2 \
    libwebpmux3 \
    libhwy1t64 \
    libdav1d-dev \
    libhwy-dev \
    libwebp-dev \
    libaom-dev \
    ccache

  setup_deb822_repo \
    "jellyfin" \
    "https://repo.jellyfin.org/jellyfin_team.gpg.key" \
    "https://repo.jellyfin.org/debian" \
    "$(get_os_info codename)"
  $STD apt install -y jellyfin-ffmpeg7
  ln -sf /usr/lib/jellyfin-ffmpeg/ffmpeg /usr/bin/ffmpeg
  ln -sf /usr/lib/jellyfin-ffmpeg/ffprobe /usr/bin/ffprobe

  if [[ "$CTTYPE" == "0" && -d /dev/dri ]]; then
    chgrp video /dev/dri 2> /dev/null || true
    chmod 755 /dev/dri 2> /dev/null || true
    chmod 660 /dev/dri/* 2> /dev/null || true
    $STD adduser "$(id -u -n)" video 2> /dev/null || true
    $STD adduser "$(id -u -n)" render 2> /dev/null || true
  fi
  msg_ok "Dependencies Installed"

  msg_info "Installing Mise"
  curl -fSs https://mise.jdx.dev/gpg-key.pub | tee /etc/apt/keyrings/mise-archive-keyring.pub 1> /dev/null
  echo "deb [signed-by=/etc/apt/keyrings/mise-archive-keyring.pub arch=$(get_system_arch)] https://mise.jdx.dev/deb stable main" > /etc/apt/sources.list.d/mise.list
  $STD apt update
  $STD apt install -y mise
  msg_ok "Installed Mise"

  msg_info "Configuring Debian Testing Repo"
  if [[ -f /etc/apt/sources.list.d/debian.sources ]]; then
    sed -i 's/ trixie-updates/ trixie-updates testing/g' /etc/apt/sources.list.d/debian.sources
  else
    cat << EOF > /etc/apt/sources.list.d/testing.sources
Types: deb
URIs: http://deb.debian.org/debian
Suites: testing
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
  fi
  cat << EOF > /etc/apt/preferences.d/preferences
Package: *
Pin: release a=unstable
Pin-Priority: 450

Package: *
Pin:release a=testing
Pin-Priority: 450
EOF
  $STD apt update
  msg_ok "Configured Debian Testing repo"

  msg_info "Installing packages from Debian Testing repo"
  $STD apt install -t testing --no-install-recommends -yqq libmimalloc3 libde265-dev
  msg_ok "Installed packages from Debian Testing repo"

  setup_uv
  PG_VERSION="16" PG_MODULES="pgvector" setup_postgresql

  ACTUAL_PG_VERSION=$(ls /etc/postgresql/ 2> /dev/null | sort -V | tail -1)
  ACTUAL_PG_VERSION=${ACTUAL_PG_VERSION:-16}

  VCHORD_RELEASE="1.1.1"
  var_appversion='' fetch_and_deploy_gh_release "VectorChord" "tensorchord/VectorChord" "binary" "${VCHORD_RELEASE}" "${TMPDIR:-/tmp}" "postgresql-${ACTUAL_PG_VERSION}-vchord_*_$(get_system_arch).deb"

  sed -i "s/^#shared_preload.*/shared_preload_libraries = 'vchord.so'/" /etc/postgresql/${ACTUAL_PG_VERSION}/main/postgresql.conf
  systemctl restart postgresql.service
  PG_DB_NAME="immich" PG_DB_USER="immich" PG_DB_GRANT_SUPERUSER="true" PG_DB_SKIP_ALTER_ROLE="true" setup_postgresql_db

  msg_info "Installing GCC-13 (available as fallback compiler)"
  $STD apt install -y gcc-13 g++-13
  msg_ok "Installed GCC-13"

  msg_warn "Compiling Custom Photo-processing Libraries (can take anywhere from 15min to 2h)"
  export LD_LIBRARY_PATH="/usr/local/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  export LD_RUN_PATH=/usr/local/lib
  INSTALL_DIR=/opt/immich
  SRC_DIR="${INSTALL_DIR}/source"
  fetch_and_deploy_gh_release "Immich" "$var_lxc_git_repo" tarball "$RELEASE" "$SRC_DIR"
  local base_tag
  base_tag=$(sed -nE 's#^FROM ghcr.io/immich-app/base-server-dev:([0-9]+)@.*#\1#p' "$SRC_DIR/server/Dockerfile")
  [[ "$base_tag" =~ ^[0-9]{12}$ ]] || {
    msg_error "Selected Immich source has no supported pinned base-server tag"
    exit 65
  }
  STAGING_DIR=$(mktemp -d "${TMPDIR:-/tmp}/immich-libraries.XXXXXX") || exit $?
  BASE_REPO="https://github.com/immich-app/base-images"
  BASE_DIR=${STAGING_DIR}/base-images
  SOURCE_DIR=${STAGING_DIR}/image-source
  $STD git clone --depth 1 --branch "$base_tag" "$BASE_REPO" "$BASE_DIR"
  mkdir -p "$SOURCE_DIR"

  local library revision revision_variable library_rc revisions_file
  revisions_file=$(mktemp "$HOME/.immich-library-revisions.XXXXXX") || exit $?
  for library in libjxl jpegli libheif libraw imagemagick libvips; do
    revision=$(jq -er '.revision | select(type=="string" and test("^[0-9a-f]{40}$"))' "$BASE_DIR/server/sources/$library.json") || exit 65
    revision_variable="${library^^}_REVISION"
    revision="${!revision_variable:-$revision}"
    [[ -n "$revision" && "$revision" != *[[:space:]]* ]] || exit 65
    local -x "$revision_variable=$revision"
    cd "$BASE_DIR/server/sources" || exit
    if $STD bash "$BASE_DIR/server/sources/$library.sh"; then :; else
      library_rc=$?
      rm -f -- "$revisions_file"
      _deploy_remove_owned_trees "$STAGING_DIR"
      exit "$library_rc"
    fi
    printf '%s: %s\n' "$library" "$revision" >> "$revisions_file"
  done
  mv -T -- "$revisions_file" "$HOME/.immich_library_revisions"
  cd /opt || exit
  _deploy_remove_owned_trees "$STAGING_DIR"
  msg_ok "Custom Photo-processing Libraries Compiled Successfully"

  INSTALL_DIR=/opt/immich
  UPLOAD_DIR="${INSTALL_DIR}/upload"
  SRC_DIR="${INSTALL_DIR}/source"
  APP_DIR="${INSTALL_DIR}/app"
  PLUGIN_DIR="${APP_DIR}/plugins/immich-plugin-core"
  ML_DIR="${APP_DIR}/machine-learning"
  GEO_DIR="${INSTALL_DIR}/geodata"
  mkdir -p {"${APP_DIR}","${UPLOAD_DIR}","${GEO_DIR}","${INSTALL_DIR}"/cache}

  PNPM_VERSION="$(jq -r '.packageManager | split("@")[1] | split("+")[0]' ${SRC_DIR}/package.json)"
  export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
  NODE_VERSION="24" NODE_MODULE="corepack" setup_nodejs
  $STD corepack prepare "pnpm@${PNPM_VERSION}" --activate
  export PATH="/root/.local/share/pnpm/bin:$PATH"
  $STD pnpm config set --global dangerouslyAllowAllBuilds true

  msg_info "Installing Immich (patience)"

  cd "$SRC_DIR"/server || exit
  export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
  export CI=1
  export SHARP_IGNORE_GLOBAL_LIBVIPS=true
  $STD pnpm --filter @immich/sdk --filter @immich/plugin-sdk --filter immich install --frozen-lockfile
  $STD pnpm --filter @immich/sdk --filter @immich/plugin-sdk --filter immich build
  unset SHARP_IGNORE_GLOBAL_LIBVIPS
  export SHARP_FORCE_GLOBAL_LIBVIPS=true
  $STD pnpm --filter immich --prod --no-optional deploy "$APP_DIR"
  $STD pnpm --config.verify-deps-before-run=false --dir "$APP_DIR/node_modules/sharp" exec npm run build

  if [[ -f "$APP_DIR/helmet.json" ]]; then
    jq '.contentSecurityPolicy.directives["upgrade-insecure-requests"] = null' "$APP_DIR/helmet.json" > "$APP_DIR/helmet.json.tmp" && mv "$APP_DIR/helmet.json.tmp" "$APP_DIR/helmet.json"
  fi

  cp "$APP_DIR"/package.json "$APP_DIR"/bin
  sed -i "s|^start|${APP_DIR}/bin/start|" "$APP_DIR"/bin/immich-admin

  cd "$SRC_DIR" || exit
  echo "packageImportMethod: hardlink" >> ./pnpm-workspace.yaml
  unset SHARP_FORCE_GLOBAL_LIBVIPS
  export SHARP_IGNORE_GLOBAL_LIBVIPS=true
  $STD pnpm --filter @immich/sdk --filter immich-web --filter @immich/cli install --frozen-lockfile
  $STD pnpm --filter @immich/sdk --filter immich-web --filter @immich/cli build
  $STD pnpm --filter @immich/cli --prod --no-optional deploy "$APP_DIR"/cli
  cp -a web/build "$APP_DIR"/www
  cp LICENSE "$APP_DIR"
  cd "$SRC_DIR" || exit
  export MISE_TRUSTED_CONFIG_PATHS="$SRC_DIR"/mise.toml
  export MISE_DISABLE_TOOLS=github:jellyfin/jellyfin-ffmpeg
  for i in 1 2 3; do
    if $STD mise install --locked; then break; else retry_rc=$?; fi
    if [[ "$i" == 3 ]]; then
      msg_error "Plugin tool installation failed after three attempts"
      exit "$retry_rc"
    fi
    sleep 5
  done
  # shellcheck disable=SC2155
  export PATH="$(mise bin-paths 2> /dev/null | tr '\n' ':')$PATH"
  if ! command -v extism-js > /dev/null 2>&1; then
    EXTISM_ARCH="$(uname -m)"
    local extism_version extism_stage tool_rc
    extism_version=$(python3 -c 'import sys,tomllib;print(tomllib.load(open(sys.argv[1],"rb"))["tools"]["github:extism/js-pdk"])' "$SRC_DIR/mise.toml") || exit 65
    [[ "$extism_version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 65
    extism_stage=$(mktemp -d "${TMPDIR:-/tmp}/immich-extism.XXXXXX") || exit $?
    if curl_download "$extism_stage/extism-js.gz" "https://github.com/extism/js-pdk/releases/download/${extism_version}/extism-js-${EXTISM_ARCH}-linux-${extism_version}.gz" && gunzip "$extism_stage/extism-js.gz" && install -m 0755 "$extism_stage/extism-js" /usr/local/bin/extism-js; then :; else
      tool_rc=$?
      _deploy_remove_owned_trees "$extism_stage"
      exit "$tool_rc"
    fi
    _deploy_remove_owned_trees "$extism_stage"
  fi
  if ! command -v wasm-merge > /dev/null 2>&1; then
    local binaryen_version binaryen_stage binaryen_arch tool_rc
    binaryen_version=$(python3 -c 'import sys,tomllib;print(tomllib.load(open(sys.argv[1],"rb"))["tools"]["github:webassembly/binaryen"])' "$SRC_DIR/mise.toml") || exit 65
    [[ "$binaryen_version" =~ ^version_[0-9]+$ ]] || exit 65
    binaryen_arch=$(uname -m)
    binaryen_stage=$(mktemp -d "${TMPDIR:-/tmp}/immich-binaryen.XXXXXX") || exit $?
    if curl_download "$binaryen_stage/binaryen.tar.gz" "https://github.com/WebAssembly/binaryen/releases/download/${binaryen_version}/binaryen-${binaryen_version}-${binaryen_arch}-linux.tar.gz" && tar -xzf "$binaryen_stage/binaryen.tar.gz" -C /opt; then :; else
      tool_rc=$?
      _deploy_remove_owned_trees "$binaryen_stage"
      exit "$tool_rc"
    fi
    _deploy_remove_owned_trees "$binaryen_stage"
    export PATH="/opt/binaryen-${binaryen_version}/bin:$PATH"
  fi
  $STD mise exec -- pnpm --filter @immich/sdk --filter @immich/plugin-sdk --filter @immich/plugin-core install --frozen-lockfile
  $STD mise exec -- pnpm --filter @immich/sdk --filter @immich/plugin-sdk --filter @immich/plugin-core build
  mkdir -p "$PLUGIN_DIR"
  cp -r ./packages/plugin-core/dist "$PLUGIN_DIR"/dist
  cp ./packages/plugin-core/manifest.json "$PLUGIN_DIR"
  msg_ok "Installed Immich Server, Web and Plugin Components"

  cd "$SRC_DIR"/machine-learning || exit
  $STD useradd -U -s /usr/sbin/nologin -r -M -d "$INSTALL_DIR" immich
  mkdir -p "$ML_DIR"
  chown immich:immich "$INSTALL_DIR"
  find "$INSTALL_DIR" -maxdepth 1 -mindepth 1 ! -name upload -exec chown -R immich:immich {} +
  chown immich:immich "$UPLOAD_DIR" 2> /dev/null || true
  export VIRTUAL_ENV="${ML_DIR}/ml-venv"
  export UV_HTTP_TIMEOUT=300
  if [[ -f ~/.openvino ]]; then
    ML_PYTHON="python3.13"
    msg_info "Pre-installing Python ${ML_PYTHON} for machine-learning"
    for attempt in $(seq 1 3); do
      if $STD sudo --preserve-env=VIRTUAL_ENV -Pnu immich uv python install "${ML_PYTHON}"; then break; else retry_rc=$?; fi
      if [[ "$attempt" == 3 ]]; then
        msg_error "Python installation failed after three attempts"
        exit "$retry_rc"
      fi
      [[ $attempt -lt 3 ]] && msg_warn "Python download attempt $attempt failed, retrying..." && sleep 5
    done
    msg_ok "Pre-installed Python ${ML_PYTHON}"
    msg_info "Installing Intel OpenVINO machine-learning"
    for attempt in $(seq 1 3); do
      if $STD sudo --preserve-env=VIRTUAL_ENV,UV_HTTP_TIMEOUT -Pnu immich uv sync --extra openvino --no-dev --active --link-mode copy -n -p "${ML_PYTHON}" --managed-python; then break; else retry_rc=$?; fi
      if [[ "$attempt" == 3 ]]; then
        msg_error "ML environment sync failed after three attempts"
        exit "$retry_rc"
      fi
      [[ $attempt -lt 3 ]] && msg_warn "uv sync attempt $attempt failed, retrying..." && sleep 10
    done
    patchelf --clear-execstack "${VIRTUAL_ENV}/lib/python3.13/site-packages/onnxruntime/capi/onnxruntime_pybind11_state.cpython-313-$(get_system_arch)-linux-gnu.so"
    msg_ok "Installed Intel OpenVINO machine-learning"
  else
    ML_PYTHON="python$(sed -nE 's/^FROM python:([0-9]+\.[0-9]+)[^[:space:]]* AS builder-cpu$/\1/p' "$SRC_DIR/machine-learning/Dockerfile")"
    [[ "$ML_PYTHON" =~ ^python[0-9]+\.[0-9]+$ ]] || exit 65
    msg_info "Pre-installing Python ${ML_PYTHON} for machine-learning"
    for attempt in $(seq 1 3); do
      if $STD sudo --preserve-env=VIRTUAL_ENV -Pnu immich uv python install "${ML_PYTHON}"; then break; else retry_rc=$?; fi
      if [[ "$attempt" == 3 ]]; then
        msg_error "Python installation failed after three attempts"
        exit "$retry_rc"
      fi
      [[ $attempt -lt 3 ]] && msg_warn "Python download attempt $attempt failed, retrying..." && sleep 5
    done
    msg_ok "Pre-installed Python ${ML_PYTHON}"
    msg_info "Installing machine-learning"
    for attempt in $(seq 1 3); do
      if $STD sudo --preserve-env=VIRTUAL_ENV,UV_HTTP_TIMEOUT -Pnu immich uv sync --extra cpu --no-dev --active --link-mode copy -n -p "${ML_PYTHON}" --managed-python; then break; else retry_rc=$?; fi
      if [[ "$attempt" == 3 ]]; then
        msg_error "ML environment sync failed after three attempts"
        exit "$retry_rc"
      fi
      [[ $attempt -lt 3 ]] && msg_warn "uv sync attempt $attempt failed, retrying..." && sleep 10
    done
    msg_ok "Installed machine-learning"
  fi
  cd "$SRC_DIR" || exit
  cp -a machine-learning/{ann,immich_ml} "$ML_DIR"
  [[ -f ~/.openvino ]] && sed -i "/intra_op/s/int = 0/int = os.cpu_count() or 0/" "$ML_DIR"/immich_ml/config.py
  ln -sf "$APP_DIR"/resources "$INSTALL_DIR"

  cd "$APP_DIR" || exit
  local matches grep_rc
  matches=$(mktemp) || exit $?
  if grep -rlZ /usr/src . > "$matches"; then :; else
    grep_rc=$?
    [[ "$grep_rc" == 1 ]] || {
      rm -f -- "$matches"
      exit "$grep_rc"
    }
  fi
  xargs -0 -r -a "$matches" sed -i "s|\/usr/src|$INSTALL_DIR|g"
  if grep -rlZE "'/build'" . > "$matches"; then :; else
    grep_rc=$?
    [[ "$grep_rc" == 1 ]] || {
      rm -f -- "$matches"
      exit "$grep_rc"
    }
  fi
  xargs -0 -r -a "$matches" sed -i "s|'/build'|'$APP_DIR'|g"
  rm -f -- "$matches"
  sed -i "s@\"/cache\"@\"$INSTALL_DIR/cache\"@g" "$ML_DIR"/immich_ml/config.py
  ln -s "$UPLOAD_DIR" "$APP_DIR"/upload
  ln -s "$UPLOAD_DIR" "$ML_DIR"/upload

  msg_info "Installing GeoNames data"
  cd "$GEO_DIR" || exit
  curl_with_retry "https://download.geonames.org/export/dump/admin1CodesASCII.txt" "admin1CodesASCII.txt"
  curl_with_retry "https://download.geonames.org/export/dump/admin2Codes.txt" "admin2Codes.txt"
  curl_with_retry "https://download.geonames.org/export/dump/countryInfo.txt" "countryInfo.txt"
  curl_with_retry "https://download.geonames.org/export/dump/cities500.zip" "cities500.zip"
  curl_with_retry "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/v5.1.2/geojson/ne_10m_admin_0_countries.geojson" "ne_10m_admin_0_countries.geojson"
  unzip -q cities500.zip
  date --iso-8601=seconds | tr -d "\n" > geodata-date.txt
  rm cities500.zip
  cd "$INSTALL_DIR" || exit
  ln -s "$GEO_DIR" "$APP_DIR"
  msg_ok "Installed GeoNames data"

  msg_info "Patching media.repository.js"
  MEDIA_REPO_JS="/opt/immich/app/dist/repositories/media.repository.js"
  if [[ -f "$MEDIA_REPO_JS" ]]; then
    python3 - "$MEDIA_REPO_JS" << 'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
old = "(0, sharp_1.default)(input).metadata()"
new = "(0, sharp_1.default)(input, { unlimited: true, limitInputPixels: false }).metadata()"
if new in s:
    print('hotfix already there')
elif old in s:
    p.write_text(s.replace(old, new, 1))
    print('hotfix applied')
else:
    print('pattern not found, skipped')
PY
  fi
  msg_ok "Patched media.repository.js"

  mkdir -p /var/log/immich
  touch /var/log/immich/{web.log,ml.log}
  msg_ok "Installed Immich"

  msg_info "Modifying user, creating env file, scripts & services"
  usermod -aG video,render immich

  cat << EOF > "${INSTALL_DIR}"/.env
TZ=$(cat /etc/timezone)
IMMICH_VERSION=release
NODE_ENV=production
IMMICH_ALLOW_SETUP=true

## Change to 'false' to disable CSP
IMMICH_HELMET_FILE=true

DB_HOSTNAME=127.0.0.1
DB_USERNAME=${PG_DB_USER}
DB_PASSWORD=${PG_DB_PASS}
DB_DATABASE_NAME=${PG_DB_NAME}
DB_VECTOR_EXTENSION=vectorchord

REDIS_HOSTNAME=127.0.0.1
IMMICH_MACHINE_LEARNING_URL=http://127.0.0.1:3003
MACHINE_LEARNING_CACHE_FOLDER=${INSTALL_DIR}/cache
MACHINE_LEARNING_MODEL_REVISION=v2
## - For OpenVINO only - uncomment below to increase
## - inference speed while reducing accuracy
## - Default is FP32
# MACHINE_LEARNING_OPENVINO_PRECISION=FP16

IMMICH_MEDIA_LOCATION=${UPLOAD_DIR}
EOF
  cat << EOF > "${ML_DIR}"/ml_start.sh
#!/usr/bin/env bash

cd ${ML_DIR} || exit
. ${VIRTUAL_ENV}/bin/activate

set -a
. ${INSTALL_DIR}/.env
set +a

python3 -m immich_ml
EOF
  cat << EOF > "$APP_DIR"/bin/start.sh
#!/usr/bin/env bash

set -a
. ${INSTALL_DIR}/.env
set +a

/usr/bin/node --no-warnings ${APP_DIR}/dist/main.js "\$@"
EOF
  chmod +x "$ML_DIR"/ml_start.sh "$APP_DIR"/bin/start.sh
  ln -sf "$APP_DIR"/cli/bin/immich /usr/bin/immich
  ln -sf "$APP_DIR"/bin/immich-admin /usr/bin/immich-admin
  cat << EOF > /etc/systemd/system/immich-web.service
[Unit]
Description=Immich Web Service
After=network.target
Requires=redis-server.service
Requires=postgresql.service
Requires=immich-ml.service

[Service]
Type=simple
User=immich
Group=immich
UMask=0077
WorkingDirectory=${APP_DIR}
ExecStart=${APP_DIR}/bin/start.sh
Restart=on-failure
SyslogIdentifier=immich-web
StandardOutput=append:/var/log/immich/web.log
StandardError=append:/var/log/immich/web.log

[Install]
WantedBy=multi-user.target
EOF
  cat << EOF > /etc/systemd/system/immich-ml.service
[Unit]
Description=Immich Machine-Learning
After=network.target

[Service]
Type=simple
UMask=0077
User=immich
Group=immich
WorkingDirectory=${APP_DIR}
EnvironmentFile=${INSTALL_DIR}/.env
ExecStart=${ML_DIR}/ml_start.sh
Restart=on-failure
SyslogIdentifier=immich-machine-learning
StandardOutput=append:/var/log/immich/ml.log
StandardError=append:/var/log/immich/ml.log

[Install]
WantedBy=multi-user.target
EOF
  chown -R immich:immich /var/log/immich
  chown immich:immich "$INSTALL_DIR"
  find "$INSTALL_DIR" -maxdepth 1 -mindepth 1 ! -name upload -exec chown -R immich:immich {} +
  chown immich:immich "$UPLOAD_DIR" 2> /dev/null || true
  systemctl enable -q --now immich-ml.service immich-web.service
  msg_ok "Modified user, created env file, scripts and services"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:2283${CL}"
}

function update_script() {
  local RELEASE="${var_appversion:-$var_lxc_release}" retry_rc
  INSTALL_DIR=/opt/immich
  SRC_DIR="$INSTALL_DIR/source"
  APP_DIR="$INSTALL_DIR/app"
  GEO_DIR="$INSTALL_DIR/geodata"
  # The selected source owns the library tuple and complete build recipes.
  # Keep this definition inside the transported hook, not in script globals.
  function compile_immich_libraries() {
    local base_tag stage library revision revision_variable previous='' record rc
    base_tag=$(sed -nE 's#^FROM ghcr.io/immich-app/base-server-dev:([0-9]+)@.*#\1#p' "$SRC_DIR/server/Dockerfile")
    [[ "$base_tag" =~ ^[0-9]{12}$ ]] || {
      msg_error "Selected source has no supported base-server tag"
      return 65
    }
    stage=$(mktemp -d "${TMPDIR:-/tmp}/immich-libraries.XXXXXX") || return $?
    $STD git clone --depth 1 --branch "$base_tag" https://github.com/immich-app/base-images "$stage/base-images"
    record=$(mktemp "$HOME/.immich-library-revisions.XXXXXX") || return $?
    [[ ! -f "$HOME/.immich_library_revisions" ]] || cp -p -- "$HOME/.immich_library_revisions" "$record"
    for library in libjxl jpegli libheif libraw imagemagick libvips; do
      revision=$(jq -er '.revision | select(type=="string" and test("^[0-9a-f]{40}$"))' "$stage/base-images/server/sources/$library.json") || return 65
      revision_variable="${library^^}_REVISION"
      revision="${!revision_variable:-$revision}"
      [[ -n "$revision" && "$revision" != *[[:space:]]* ]] || return 65
      local -x "$revision_variable=$revision"
      previous=$(awk -v key="$library:" '$1==key {print $2}' "$record")
      if [[ "$revision" != "$previous" ]]; then
        cd "$stage/base-images/server/sources" || return $?
        if $STD bash "$stage/base-images/server/sources/$library.sh"; then :; else
          rc=$?
          rm -f -- "$record"
          cd /opt || return $?
          _deploy_remove_owned_trees "$stage"
          return "$rc"
        fi
        if [[ -n "$previous" ]]; then
          sed -i "s/^${library}: .*\$/${library}: $revision/" "$record"
        else printf '%s: %s\n' "$library" "$revision" >> "$record"; fi
      fi
    done
    mv -T -- "$record" "$HOME/.immich_library_revisions"
    cd /opt || return $?
    _deploy_remove_owned_trees "$stage"
  }
  ARCH_RAW=$(uname -m)
  [[ "$ARCH_RAW" == "aarch64" ]] && ARCH_RAW="arm64"
  # shellcheck disable=SC2034
  ARCH=$(uname -m)
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/immich ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if [[ -f /etc/apt/sources.list.d/immich.list ]]; then
    msg_error "Wrong Debian version detected!"
    msg_error "You must upgrade your LXC to Debian Trixie before updating."
    msg_error "Please visit https://github.com/community-scripts/ProxmoxVE/discussions/7726 for details."
    echo "${TAB3}  If you have upgraded your LXC to Trixie and you still see this message, please open an Issue in the Community-Scripts repo."
    exit
  fi

  if ! grep -qE '(^|[[:space:]])testing([[:space:]]|$)' /etc/apt/sources.list.d/debian.sources 2> /dev/null; then
    msg_info "Adding Debian Testing repo"
    if grep -q "trixie-updates" /etc/apt/sources.list.d/debian.sources 2> /dev/null; then
      sed -i 's/ trixie-updates/ trixie-updates testing/g' /etc/apt/sources.list.d/debian.sources
    else
      sed -i '/^[[:space:]]*Suites:.*trixie/ s/$/ testing/' /etc/apt/sources.list.d/debian.sources
    fi
    cat << EOF > /etc/apt/preferences.d/preferences
Package: *
Pin: release a=unstable
Pin-Priority: 450

Package: *
Pin:release a=testing
Pin-Priority: 450
EOF
    [[ -f /etc/apt/preferences.d/immich ]] && rm /etc/apt/preferences.d/immich
    $STD apt update
    msg_ok "Added Debian Testing repo"
  fi

  if ! dpkg -l "libmimalloc3" | grep -q '3.1' || ! dpkg -l "libde265-dev" | grep -q '1.0.16'; then
    msg_info "Installing/upgrading Testing repo packages"
    $STD apt install -t testing libmimalloc3 libde265-dev -y
    msg_ok "Installed/upgraded Testing repo packages"
  fi

  if [[ ! -f /etc/apt/sources.list.d/mise.list ]]; then
    msg_info "Installing Mise"
    curl -fSs https://mise.jdx.dev/gpg-key.pub | tee /etc/apt/keyrings/mise-archive-keyring.pub 1> /dev/null
    echo "deb [signed-by=/etc/apt/keyrings/mise-archive-keyring.pub arch=$(get_system_arch)] https://mise.jdx.dev/deb stable main" > /etc/apt/sources.list.d/mise.list
    ensure_dependencies mise
    msg_ok "Installed Mise"
  fi

  cd "${TMPDIR:-/tmp}" || exit
  if [[ -f ~/.intel_version ]]; then
    curl_with_retry "https://raw.githubusercontent.com/${var_lxc_git_repo}/${RELEASE}/machine-learning/Dockerfile" "Dockerfile"
    readarray -t INTEL_URLS < <(
      sed -n "/intel-[igc|opencl]/p" ./Dockerfile | awk '{print $3}'
      sed -n "/libigdgmm12/p" ./Dockerfile | awk '{print $3}'
    )
    INTEL_RELEASE="$(grep "intel-opencl-icd_" ./Dockerfile | awk -F '_' '{print $2}')"
    if [[ "$INTEL_RELEASE" != "$(cat ~/.intel_version)" ]]; then
      msg_info "Updating Intel OpenVINO dependencies"
      for url in "${INTEL_URLS[@]}"; do
        curl_with_retry "$url" "$(basename "$url")"
      done
      $STD apt-mark unhold libigdgmm12
      $STD apt install -y --allow-downgrades ./libigdgmm12*.deb
      rm ./libigdgmm12*.deb
      $STD apt install -y ./*.deb
      rm ./*.deb
      $STD apt-mark hold libigdgmm12
      dpkg-query -W -f='${Version}\n' intel-opencl-icd > ~/.intel_version
      rm -f ./Dockerfile
      msg_ok "Updated Intel OpenVINO dependencies"
    fi
  fi
  if check_for_gh_release "Immich" "$var_lxc_git_repo" "${RELEASE}" "each release is tested individually before the version is updated. Please do not open issues for this"; then
    if [[ $(cat ~/.immich) > "2.5.1" && -x /opt/immich/app/bin/immich-admin ]]; then
      msg_info "Enabling Maintenance Mode"
      cd /opt/immich/app/bin || exit
      $STD ./immich-admin enable-maintenance-mode
      export MAINT_MODE=1
      $STD cd -
      msg_ok "Enabled Maintenance Mode"
    fi
    msg_info "Stopping Services"
    systemctl stop immich-web
    systemctl stop immich-ml
    msg_ok "Stopped Services"
    VCHORD_RELEASE="1.1.1"
    PG_VERSION=$(ls /etc/postgresql/ 2> /dev/null | sort -V | tail -1)
    PG_VERSION=${PG_VERSION:-16}
    [[ -f ~/.vchord_version ]] && mv ~/.vchord_version ~/.vectorchord
    if var_appversion='' check_for_gh_release "VectorChord" "tensorchord/VectorChord" "${VCHORD_RELEASE}" "updated together with Immich after testing"; then
      $STD sudo -u postgres psql -d immich -c "VACUUM (ANALYZE) smart_search;"
      $STD sudo -u postgres psql -d immich -c "VACUUM (ANALYZE) face_search;"
      var_appversion='' fetch_and_deploy_gh_release "VectorChord" "tensorchord/VectorChord" "binary" "${VCHORD_RELEASE}" "${TMPDIR:-/tmp}" "postgresql-${PG_VERSION}-vchord_*_$(get_system_arch).deb"
      systemctl restart postgresql
      $STD sudo -u postgres psql -d immich -c "ALTER EXTENSION vector UPDATE;"
      $STD sudo -u postgres psql -d immich -c "ALTER EXTENSION vchord UPDATE;"
      $STD sudo -u postgres psql -d immich -c "REINDEX INDEX face_index;"
      $STD sudo -u postgres psql -d immich -c "REINDEX INDEX clip_index;"
    else
      local vectorchord_rc=$?
      [[ "$vectorchord_rc" == 1 ]] || exit "$vectorchord_rc"
    fi
    ensure_dependencies ccache gcc-13 g++-13

    INSTALL_DIR=/opt/immich
    [[ -f "$INSTALL_DIR/.env" ]] || {
      msg_error "Missing existing Immich environment"
      exit 65
    }
    local keep_plan keep_file
    keep_plan=$(
      node - /opt/immich/.env << 'JS'
const fs=require('node:fs'),path=require('node:path');
const env=require('node:util').parseEnv(fs.readFileSync(process.argv[2],'utf8'));
if(!env.IMMICH_MEDIA_LOCATION)throw Error('Missing saved upload location');
const upload=path.resolve('/opt/immich/app',env.IMMICH_MEDIA_LOCATION),keeps=[],source_keeps=[];
for(const value of [upload,env.IMMICH_CONFIG_FILE]) {
 if(!value)continue;const p=path.resolve('/opt/immich/app',value);
 for(const [root,paths] of [['/opt/immich/app',keeps],['/opt/immich/source',source_keeps]]) {
  if(p===root)throw Error('Persistent data cannot share app source root');
  if(p.startsWith(root+'/'))paths.push(path.relative(root,p));
 }
}
process.stdout.write(JSON.stringify({upload,keeps,source_keeps}));
JS
    ) || exit 65
    UPLOAD_DIR=$(jq -er '.upload' <<< "$keep_plan") || exit 65
    keep_file=$(mktemp) || exit $?
    jq -j '.keeps[] | .+"\u0000"' <<< "$keep_plan" > "$keep_file"
    local -a app_keeps=() source_keeps=() inherited_keeps=("${CLEAN_INSTALL_KEEP_PATHS[@]}")
    mapfile -d '' -t app_keeps < "$keep_file"
    jq -j '.source_keeps[] | .+"\u0000"' <<< "$keep_plan" > "$keep_file"
    mapfile -d '' -t source_keeps < "$keep_file"
    rm -f -- "$keep_file"
    SRC_DIR="${INSTALL_DIR}/source"
    APP_DIR="${INSTALL_DIR}/app"
    PLUGIN_DIR="${APP_DIR}/plugins/immich-plugin-core"
    ML_DIR="${APP_DIR}/machine-learning"
    GEO_DIR="${INSTALL_DIR}/geodata"

    [[ -f "$ML_DIR"/ml_start.sh ]] && cp "$ML_DIR"/ml_start.sh "$INSTALL_DIR"
    if grep -qs "set -a" "$APP_DIR"/bin/start.sh && grep -qs "warnings" "$APP_DIR"/bin/start.sh; then
      cp "$APP_DIR"/bin/start.sh "$INSTALL_DIR"
    else
      cat << EOF > "$INSTALL_DIR"/start.sh
#!/usr/bin/env bash

set -a
. ${INSTALL_DIR}/.env
set +a

/usr/bin/node --no-warnings ${APP_DIR}/dist/main.js "\$@"
EOF
      chmod +x "$INSTALL_DIR"/start.sh
    fi

    setup_uv
    local -a CLEAN_INSTALL_KEEP_PATHS=("${inherited_keeps[@]}" "${source_keeps[@]}")
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "Immich" "$var_lxc_git_repo" "tarball" "${RELEASE}" "$SRC_DIR"
    compile_immich_libraries
    local LIVE_APP_DIR="$APP_DIR"
    # App artifacts can be large; stage beside the persistent live application,
    # independent of a production TMPDIR that may be RAM-backed.
    local app_stage app_build_rc=0 app_cleanup_rc=0 app_leave_rc=0
    app_stage=$(mktemp -d "$INSTALL_DIR/.app-build.XXXXXX") || exit $?
    APP_DIR="$app_stage"
    PLUGIN_DIR="$APP_DIR/plugins/immich-plugin-core"
    ML_DIR="$APP_DIR/machine-learning"
    # The caller owns this exact stage on every return, including build failure.
    # Required steps are checked explicitly because the function is conditional.
    function build_immich_app() {
      local plugin_paths
      PNPM_VERSION="$(jq -r '.packageManager | split("@")[1] | split("+")[0]' "$SRC_DIR/package.json")" || return $?
      export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
      export CI=1
      NODE_VERSION="24" NODE_MODULE="corepack" setup_nodejs || return $?
      $STD corepack prepare "pnpm@${PNPM_VERSION}" --activate || return $?
      export PATH="/root/.local/share/pnpm/bin:$PATH"
      $STD pnpm config set --global dangerouslyAllowAllBuilds true || return $?

      msg_info "Updating Immich web and microservices"
      cd "$SRC_DIR"/server || return $?
      export SHARP_IGNORE_GLOBAL_LIBVIPS=true
      $STD pnpm --filter @immich/sdk --filter @immich/plugin-sdk --filter immich install --frozen-lockfile || return $?
      $STD pnpm --filter @immich/sdk --filter @immich/plugin-sdk --filter immich build || return $?
      unset SHARP_IGNORE_GLOBAL_LIBVIPS
      export SHARP_FORCE_GLOBAL_LIBVIPS=true
      $STD pnpm --filter immich --prod --no-optional deploy "$APP_DIR" || return $?
      $STD pnpm --config.verify-deps-before-run=false --dir "$APP_DIR/node_modules/sharp" exec npm run build || return $?

      if [[ -f "$APP_DIR/helmet.json" ]]; then
        jq '.contentSecurityPolicy.directives["upgrade-insecure-requests"] = null' "$APP_DIR/helmet.json" > "$APP_DIR/helmet.json.tmp" || return $?
        mv "$APP_DIR/helmet.json.tmp" "$APP_DIR/helmet.json" || return $?
      fi

      cp "$APP_DIR"/package.json "$APP_DIR"/bin || return $?
      sed -i "s|^start|${LIVE_APP_DIR}/bin/start|" "$APP_DIR"/bin/immich-admin || return $?

      cd "$SRC_DIR" || return $?
      cat << 'EOF' >> ./pnpm-workspace.yaml || return $?
packageImportMethod: hardlink
EOF
      unset SHARP_FORCE_GLOBAL_LIBVIPS
      export SHARP_IGNORE_GLOBAL_LIBVIPS=true
      $STD pnpm --filter @immich/sdk --filter immich-web --filter @immich/cli install --frozen-lockfile || return $?
      $STD pnpm --filter @immich/sdk --filter immich-web --filter @immich/cli build || return $?
      $STD pnpm --filter @immich/cli --prod --no-optional deploy "$APP_DIR"/cli || return $?
      cp -a web/build "$APP_DIR"/www || return $?
      cp LICENSE "$APP_DIR" || return $?
      if [[ -f "$INSTALL_DIR"/start.sh ]]; then mv "$INSTALL_DIR"/start.sh "$APP_DIR"/bin || return $?; fi

      cd "$SRC_DIR" || return $?
      export MISE_TRUSTED_CONFIG_PATHS="$SRC_DIR"/mise.toml
      export MISE_DISABLE_TOOLS=github:jellyfin/jellyfin-ffmpeg
      for i in 1 2 3; do
        if $STD mise install --locked; then break; else retry_rc=$?; fi
        if [[ "$i" == 3 ]]; then
          msg_error "Plugin tool installation failed after three attempts"
          return "$retry_rc"
        fi
        sleep 5
      done
      plugin_paths=$(mise bin-paths 2> /dev/null | tr '\n' ':') || return $?
      export PATH="${plugin_paths}$PATH"
      if ! command -v extism-js > /dev/null 2>&1; then
        EXTISM_ARCH="$(uname -m)"
        local extism_version extism_stage tool_rc
        extism_version=$(python3 -c 'import sys,tomllib;print(tomllib.load(open(sys.argv[1],"rb"))["tools"]["github:extism/js-pdk"])' "$SRC_DIR/mise.toml") || return 65
        [[ "$extism_version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 65
        extism_stage=$(mktemp -d "${TMPDIR:-/tmp}/immich-extism.XXXXXX") || return $?
        if curl_download "$extism_stage/extism-js.gz" "https://github.com/extism/js-pdk/releases/download/${extism_version}/extism-js-${EXTISM_ARCH}-linux-${extism_version}.gz" && gunzip "$extism_stage/extism-js.gz" && install -m 0755 "$extism_stage/extism-js" /usr/local/bin/extism-js; then :; else
          tool_rc=$?
          _deploy_remove_owned_trees "$extism_stage" || msg_error "Owned Extism stage cleanup failed: $extism_stage"
          return "$tool_rc"
        fi
        _deploy_remove_owned_trees "$extism_stage" || return $?
      fi
      if ! command -v wasm-merge > /dev/null 2>&1; then
        BINARYEN_VERSION=$(python3 -c 'import sys,tomllib;print(tomllib.load(open(sys.argv[1],"rb"))["tools"]["github:webassembly/binaryen"])' "$SRC_DIR/mise.toml") || return 65
        [[ "$BINARYEN_VERSION" =~ ^version_[0-9]+$ ]] || return 65
        BINARYEN_ARCH="$(uname -m)"
        local binaryen_stage tool_rc
        binaryen_stage=$(mktemp -d "${TMPDIR:-/tmp}/immich-binaryen.XXXXXX") || return $?
        if curl_download "$binaryen_stage/binaryen.tar.gz" "https://github.com/WebAssembly/binaryen/releases/download/${BINARYEN_VERSION}/binaryen-${BINARYEN_VERSION}-${BINARYEN_ARCH}-linux.tar.gz" && tar -xzf "$binaryen_stage/binaryen.tar.gz" -C /opt; then :; else
          tool_rc=$?
          _deploy_remove_owned_trees "$binaryen_stage" || msg_error "Owned Binaryen stage cleanup failed: $binaryen_stage"
          return "$tool_rc"
        fi
        _deploy_remove_owned_trees "$binaryen_stage" || return $?
        export PATH="/opt/binaryen-${BINARYEN_VERSION}/bin:$PATH"
      fi
      $STD mise exec -- pnpm --filter @immich/sdk --filter @immich/plugin-sdk --filter @immich/plugin-core install --frozen-lockfile || return $?
      $STD mise exec -- pnpm --filter @immich/sdk --filter @immich/plugin-sdk --filter @immich/plugin-core build || return $?
      mkdir -p "$PLUGIN_DIR" || return $?
      cp -r ./packages/plugin-core/dist "$PLUGIN_DIR"/dist || return $?
      cp ./packages/plugin-core/manifest.json "$PLUGIN_DIR" || return $?
      msg_ok "Built Immich server, web, cli and plugins"

      cd "$SRC_DIR"/machine-learning || return $?
      mkdir -p "$ML_DIR" || return $?
      chown -R immich:immich "$SRC_DIR/machine-learning" || return $?
      chown immich:immich ./uv.lock || return $?
      export VIRTUAL_ENV="$LIVE_APP_DIR/machine-learning/ml-venv"
      mkdir -p "$ML_DIR" "$LIVE_APP_DIR/machine-learning" || return $?
      export UV_HTTP_TIMEOUT=300
      if [[ -f ~/.openvino ]]; then
        ML_PYTHON="python3.13"
        msg_info "Pre-installing Python ${ML_PYTHON} for machine-learning"
        for attempt in $(seq 1 3); do
          if $STD sudo --preserve-env=VIRTUAL_ENV -Pnu immich uv python install "${ML_PYTHON}"; then break; else retry_rc=$?; fi
          if [[ "$attempt" == 3 ]]; then
            msg_error "Python installation failed after three attempts"
            return "$retry_rc"
          fi
          [[ $attempt -lt 3 ]] && msg_warn "Python download attempt $attempt failed, retrying..." && sleep 5
        done
        msg_ok "Pre-installed Python ${ML_PYTHON}"
        msg_info "Updating Intel OpenVINO machine-learning"
        for attempt in $(seq 1 3); do
          if $STD sudo --preserve-env=VIRTUAL_ENV,UV_HTTP_TIMEOUT -Pnu immich uv sync --extra openvino --no-dev --active --link-mode copy -n -p "${ML_PYTHON}" --managed-python; then break; else retry_rc=$?; fi
          if [[ "$attempt" == 3 ]]; then
            msg_error "ML environment sync failed after three attempts"
            return "$retry_rc"
          fi
          [[ $attempt -lt 3 ]] && msg_warn "uv sync attempt $attempt failed, retrying..." && sleep 10
        done
        patchelf --clear-execstack "${VIRTUAL_ENV}/lib/python3.13/site-packages/onnxruntime/capi/onnxruntime_pybind11_state.cpython-313-$(get_system_arch)-linux-gnu.so" || return $?
        msg_ok "Updated Intel OpenVINO machine-learning"
      else
        ML_PYTHON="python$(sed -nE 's/^FROM python:([0-9]+\.[0-9]+)[^[:space:]]* AS builder-cpu$/\1/p' "$SRC_DIR/machine-learning/Dockerfile")" || return $?
        [[ "$ML_PYTHON" =~ ^python[0-9]+\.[0-9]+$ ]] || return 65
        msg_info "Pre-installing Python ${ML_PYTHON} for machine-learning"
        for attempt in $(seq 1 3); do
          if $STD sudo --preserve-env=VIRTUAL_ENV -Pnu immich uv python install "${ML_PYTHON}"; then break; else retry_rc=$?; fi
          if [[ "$attempt" == 3 ]]; then
            msg_error "Python installation failed after three attempts"
            return "$retry_rc"
          fi
          [[ $attempt -lt 3 ]] && msg_warn "Python download attempt $attempt failed, retrying..." && sleep 5
        done
        msg_ok "Pre-installed Python ${ML_PYTHON}"
        msg_info "Updating machine-learning"
        for attempt in $(seq 1 3); do
          if $STD sudo --preserve-env=VIRTUAL_ENV,UV_HTTP_TIMEOUT -Pnu immich uv sync --extra cpu --no-dev --active --link-mode copy -n -p "${ML_PYTHON}" --managed-python; then break; else retry_rc=$?; fi
          if [[ "$attempt" == 3 ]]; then
            msg_error "ML environment sync failed after three attempts"
            return "$retry_rc"
          fi
          [[ $attempt -lt 3 ]] && msg_warn "uv sync attempt $attempt failed, retrying..." && sleep 10
        done
        msg_ok "Updated machine-learning"
      fi
      cd "$SRC_DIR" || return $?
      cp -a machine-learning/{ann,immich_ml} "$ML_DIR" || return $?
      if [[ -f "$INSTALL_DIR"/ml_start.sh ]]; then mv "$INSTALL_DIR"/ml_start.sh "$ML_DIR" || return $?; fi
      if [[ ! -f "$ML_DIR"/ml_start.sh ]]; then
        cat << EOF > "$ML_DIR"/ml_start.sh || return $?
#!/usr/bin/env bash

cd ${LIVE_APP_DIR}/machine-learning || exit
. ${VIRTUAL_ENV}/bin/activate

set -a
. ${INSTALL_DIR}/.env
set +a

python3 -m immich_ml
EOF
        chmod +x "$ML_DIR"/ml_start.sh || return $?
      fi
      if [[ -f ~/.openvino ]]; then sed -i "/intra_op/s/int = 0/int = os.cpu_count() or 0/" "$ML_DIR"/immich_ml/config.py || return $?; fi
      cd "$APP_DIR" || return $?
      local matches grep_rc
      matches=$(mktemp) || return $?
      if grep -rlZ /usr/src . > "$matches"; then :; else
        grep_rc=$?
        [[ "$grep_rc" == 1 ]] || {
          rm -f -- "$matches"
          return "$grep_rc"
        }
      fi
      xargs -0 -r -a "$matches" sed -i "s|\/usr/src|$INSTALL_DIR|g" || {
        grep_rc=$?
        rm -f -- "$matches"
        return "$grep_rc"
      }
      if grep -rlZE "'/build'" . > "$matches"; then :; else
        grep_rc=$?
        [[ "$grep_rc" == 1 ]] || {
          rm -f -- "$matches"
          return "$grep_rc"
        }
      fi
      xargs -0 -r -a "$matches" sed -i "s|'/build'|'$LIVE_APP_DIR'|g" || {
        grep_rc=$?
        rm -f -- "$matches"
        return "$grep_rc"
      }
      rm -f -- "$matches" || return $?
      sed -i "s@\"/cache\"@\"$INSTALL_DIR/cache\"@g" "$ML_DIR"/immich_ml/config.py || return $?
      ln -s "${UPLOAD_DIR:-/opt/immich/upload}" "$APP_DIR"/upload || return $?
      ln -s "${UPLOAD_DIR:-/opt/immich/upload}" "$ML_DIR"/upload || return $?
      mkdir -p "$GEO_DIR" || return $?
      if [[ ! -s "$GEO_DIR/countryInfo.txt" ]]; then curl_with_retry "https://download.geonames.org/export/dump/countryInfo.txt" "$GEO_DIR/countryInfo.txt" || return $?; fi
      ln -sfn "$GEO_DIR" "$APP_DIR/geodata" || return $?
      if [[ ! -f /usr/bin/immich ]]; then ln -sf "$LIVE_APP_DIR"/cli/bin/immich /usr/bin/immich || return $?; fi
      if [[ ! -f /usr/bin/immich-admin ]]; then ln -sf "$LIVE_APP_DIR"/bin/immich-admin /usr/bin/immich-admin || return $?; fi

      if grep -q 'ExecStart=/usr/bin/node' /etc/systemd/system/immich-web.service; then
        sed -i '/^EnvironmentFile=/d' /etc/systemd/system/immich-web.service || return $?
        sed -i "s|^ExecStart=.*|ExecStart=${LIVE_APP_DIR}/bin/start.sh|" /etc/systemd/system/immich-web.service || return $?
        systemctl daemon-reload || return $?
      fi

      msg_info "Patching media.repository.js"
      MEDIA_REPO_JS="$APP_DIR/dist/repositories/media.repository.js"
      if [[ -f "$MEDIA_REPO_JS" ]]; then
        python3 - "$MEDIA_REPO_JS" << 'PY' || return $?
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
old = "(0, sharp_1.default)(input).metadata()"
new = "(0, sharp_1.default)(input, { unlimited: true, limitInputPixels: false }).metadata()"
if new in s:
    print('hotfix already there')
elif old in s:
    p.write_text(s.replace(old, new, 1))
    print('hotfix applied')
else:
    print('pattern not found, skipped')
PY
      fi
      msg_ok "Patched media.repository.js"

      CLEAN_INSTALL_KEEP_PATHS=("${inherited_keeps[@]}" upload machine-learning/ml-venv "${app_keeps[@]}")
      # Projection must share the app disk too; global scratch can be another FS.
      TMPDIR="$INSTALL_DIR" _deploy_replace_contents "$APP_DIR" "$LIVE_APP_DIR" 1 || return $?
    }
    build_immich_app || app_build_rc=$?
    cd "$INSTALL_DIR" || app_leave_rc=$?
    _deploy_remove_owned_trees "$app_stage" || app_cleanup_rc=$?
    [[ "$app_build_rc" == 0 ]] || exit "$app_build_rc"
    [[ "$app_leave_rc" == 0 ]] || exit "$app_leave_rc"
    [[ "$app_cleanup_rc" == 0 ]] || exit "$app_cleanup_rc"
    APP_DIR="$LIVE_APP_DIR"
    ML_DIR="$APP_DIR/machine-learning"
    if [[ "${MAINT_MODE:-0}" == 1 ]]; then
      msg_info "Disabling Maintenance Mode"
      cd /opt/immich/app/bin || exit
      $STD ./immich-admin disable-maintenance-mode || true
      unset MAINT_MODE
      $STD cd -
      msg_ok "Disabled Maintenance Mode"
    fi
    systemctl restart immich-ml immich-web
    [[ -f /etc/systemd/system/immich-proxy.service ]] && systemctl restart immich-proxy
    msg_ok "Updated successfully!"
  else
    local checker_rc=$?
    [[ "$checker_rc" == 1 ]] || exit "$checker_rc"
    [[ -f "$HOME/.immich_library_revisions" ]] || compile_immich_libraries
    mkdir -p "$GEO_DIR"
    if [[ ! -s "$GEO_DIR/countryInfo.txt" ]]; then
      if [[ -s "$APP_DIR/countryInfo.txt" ]]; then
        cp -a -- "$APP_DIR/countryInfo.txt" "$GEO_DIR/countryInfo.txt"
      else curl_with_retry "https://download.geonames.org/export/dump/countryInfo.txt" "$GEO_DIR/countryInfo.txt"; fi
      ln -sfn "$GEO_DIR" "$APP_DIR/geodata"
      systemctl restart immich-web
    fi
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
