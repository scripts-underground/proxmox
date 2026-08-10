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

function install_script() {
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

    read -r -p "${TAB3}Select machine-learning type [1]: " ML_TYPE
    ML_TYPE="${ML_TYPE:-1}"
    if [[ "$ML_TYPE" == "2" ]]; then
      touch ~/.openvino
      $STD apt install -y --no-install-recommends patchelf
      if [[ -d /dev/dri ]]; then
        msg_info "Installing Intel OpenVINO dependencies"
        tmp_dir=$(mktemp -d)
        $STD pushd "$tmp_dir"
        curl_with_retry "https://raw.githubusercontent.com/immich-app/immich/refs/heads/main/machine-learning/Dockerfile" "Dockerfile"
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
  fetch_and_deploy_gh_release "VectorChord" "tensorchord/VectorChord" "binary" "${VCHORD_RELEASE}" "/tmp" "postgresql-${ACTUAL_PG_VERSION}-vchord_*_$(get_system_arch).deb"

  sed -i "s/^#shared_preload.*/shared_preload_libraries = 'vchord.so'/" /etc/postgresql/${ACTUAL_PG_VERSION}/main/postgresql.conf
  systemctl restart postgresql.service
  PG_DB_NAME="immich" PG_DB_USER="immich" PG_DB_GRANT_SUPERUSER="true" PG_DB_SKIP_ALTER_ROLE="true" setup_postgresql_db

  msg_info "Installing GCC-13 (available as fallback compiler)"
  $STD apt install -y gcc-13 g++-13
  msg_ok "Installed GCC-13"

  msg_warn "Compiling Custom Photo-processing Libraries (can take anywhere from 15min to 2h)"
  LD_LIBRARY_PATH=/usr/local/lib
  export LD_RUN_PATH=/usr/local/lib
  STAGING_DIR=/opt/staging
  BASE_REPO="https://github.com/immich-app/base-images"
  BASE_DIR=${STAGING_DIR}/base-images
  SOURCE_DIR=${STAGING_DIR}/image-source
  $STD git clone -b main "$BASE_REPO" "$BASE_DIR"
  mkdir -p "$SOURCE_DIR"

  msg_info "(1/5) Compiling libjxl"
  cd "$STAGING_DIR" || exit
  SOURCE=${SOURCE_DIR}/libjxl
  JPEGLI_LIBJPEG_LIBRARY_SOVERSION="62"
  JPEGLI_LIBJPEG_LIBRARY_VERSION="62.3.0"
  LIBJXL_REVISION="332feb17d17311c748445f7ee75c4fb55cc38530"
  $STD git clone https://github.com/libjxl/libjxl.git "$SOURCE"
  cd "$SOURCE" || exit
  $STD git reset --hard "$LIBJXL_REVISION"
  $STD git submodule update --init --recursive --depth 1 --recommend-shallow
  $STD git apply "$BASE_DIR"/server/sources/libjxl-patches/jpegli-empty-dht-marker.patch
  $STD git apply "$BASE_DIR"/server/sources/libjxl-patches/jpegli-icc-warning.patch
  mkdir build
  cd build || exit
  $STD cmake \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_TESTING=OFF \
    -DJPEGXL_ENABLE_DOXYGEN=OFF \
    -DJPEGXL_ENABLE_MANPAGES=OFF \
    -DJPEGXL_ENABLE_PLUGIN_GIMP210=OFF \
    -DJPEGXL_ENABLE_BENCHMARK=OFF \
    -DJPEGXL_ENABLE_EXAMPLES=OFF \
    -DJPEGXL_FORCE_SYSTEM_BROTLI=ON \
    -DJPEGXL_FORCE_SYSTEM_HWY=ON \
    -DJPEGXL_ENABLE_JPEGLI=ON \
    -DJPEGXL_ENABLE_JPEGLI_LIBJPEG=ON \
    -DJPEGXL_INSTALL_JPEGLI_LIBJPEG=ON \
    -DJPEGXL_ENABLE_PLUGINS=ON \
    -DJPEGLI_LIBJPEG_LIBRARY_SOVERSION="$JPEGLI_LIBJPEG_LIBRARY_SOVERSION" \
    -DJPEGLI_LIBJPEG_LIBRARY_VERSION="$JPEGLI_LIBJPEG_LIBRARY_VERSION" \
    -DLIBJPEG_TURBO_VERSION_NUMBER=2001005 \
    ..
  $STD cmake --build . -- -j"$(nproc)"
  $STD cmake --install .
  ldconfig /usr/local/lib
  $STD make clean
  cd "$STAGING_DIR" || exit
  rm -rf "$SOURCE"/{build,third_party}
  msg_ok "(1/5) Compiled libjxl"

  msg_info "(2/5) Compiling libheif"
  SOURCE=${SOURCE_DIR}/libheif
  LIBHEIF_REVISION="62f1b8c76ed4d8305071fdacbe74ef9717bacac5"
  $STD git clone https://github.com/strukturag/libheif.git "$SOURCE"
  cd "$SOURCE" || exit
  $STD git reset --hard "$LIBHEIF_REVISION"
  mkdir build
  cd build || exit
  $STD cmake --preset=release-noplugins \
    -DWITH_DAV1D=ON \
    -DENABLE_PARALLEL_TILE_DECODING=ON \
    -DWITH_LIBSHARPYUV=ON \
    -DWITH_LIBDE265=ON \
    -DWITH_AOM_DECODER=OFF \
    -DWITH_AOM_ENCODER=ON \
    -DWITH_X265=OFF \
    -DWITH_EXAMPLES=OFF \
    ..
  $STD make install -j"$(nproc)"
  ldconfig /usr/local/lib
  $STD make clean
  cd "$STAGING_DIR" || exit
  rm -rf "$SOURCE"/build
  msg_ok "(2/5) Compiled libheif"

  msg_info "(3/5) Compiling libraw"
  SOURCE=${SOURCE_DIR}/libraw
  LIBRAW_REVISION="b860248a89d9082b8e0a1e202e516f46af9adb29"
  $STD git clone https://github.com/LibRaw/LibRaw.git "$SOURCE"
  cd "$SOURCE" || exit
  $STD git reset --hard "$LIBRAW_REVISION"
  $STD autoreconf --install
  $STD ./configure --disable-examples
  $STD make -j"$(nproc)"
  $STD make install
  ldconfig /usr/local/lib
  $STD make clean
  cd "$STAGING_DIR" || exit
  msg_ok "(3/5) Compiled libraw"

  msg_info "(4/5) Compiling imagemagick"
  SOURCE=$SOURCE_DIR/imagemagick
  : "${IMAGEMAGICK_REVISION:=$(jq -cr '.revision' $BASE_DIR/server/sources/imagemagick.json)}"
  $STD git clone https://github.com/ImageMagick/ImageMagick.git "$SOURCE"
  cd "$SOURCE" || exit
  $STD git reset --hard "$IMAGEMAGICK_REVISION"
  $STD ./configure --with-modules CPPFLAGS="-DMAGICK_LIBRAW_VERSION_TAIL=202502"
  $STD make -j"$(nproc)"
  $STD make install
  ldconfig /usr/local/lib
  $STD make clean
  cd "$STAGING_DIR" || exit
  msg_ok "(4/5) Compiled imagemagick"

  msg_info "(5/5) Compiling libvips"
  SOURCE=$SOURCE_DIR/libvips
  LIBVIPS_REVISION="e01a4797cabe77d457fdfa7d776b7a7e7ca6d6a7"
  $STD git clone https://github.com/libvips/libvips.git "$SOURCE"
  cd "$SOURCE" || exit
  $STD git reset --hard "$LIBVIPS_REVISION"
  $STD git apply "$BASE_DIR"/server/sources/libvips-patches/0001-put-other-loaders-ahead-of-dcrawload.patch
  $STD meson setup build --buildtype=release --libdir=lib -Dintrospection=disabled -Dtiff=disabled
  cd build || exit
  $STD ninja install
  ldconfig /usr/local/lib
  cd "$STAGING_DIR" || exit
  rm -rf "$SOURCE"/build
  msg_ok "(5/5) Compiled libvips"
  cat << EOF > ~/.immich_library_revisions
imagemagick: $IMAGEMAGICK_REVISION
libheif: $LIBHEIF_REVISION
libjxl: $LIBJXL_REVISION
libraw: $LIBRAW_REVISION
libvips: $LIBVIPS_REVISION
EOF
  msg_ok "Custom Photo-processing Libraries Compiled Successfully"

  INSTALL_DIR="/opt/${APPLICATION}"
  UPLOAD_DIR="${INSTALL_DIR}/upload"
  SRC_DIR="${INSTALL_DIR}/source"
  APP_DIR="${INSTALL_DIR}/app"
  PLUGIN_DIR="${APP_DIR}/plugins/immich-plugin-core"
  ML_DIR="${APP_DIR}/machine-learning"
  GEO_DIR="${INSTALL_DIR}/geodata"
  mkdir -p {"${APP_DIR}","${UPLOAD_DIR}","${GEO_DIR}","${INSTALL_DIR}"/cache}

  fetch_and_deploy_gh_release "Immich" "$var_lxc_git_repo" "tarball" "v3.0.3" "$SRC_DIR"
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
  $STD pnpm --filter @immich/sdk --filter @immich/plugin-sdk --filter immich build
  unset SHARP_IGNORE_GLOBAL_LIBVIPS
  export SHARP_FORCE_GLOBAL_LIBVIPS=true
  $STD pnpm --filter immich --prod --no-optional deploy "$APP_DIR"

  if [[ -f "$APP_DIR/helmet.json" ]]; then
    jq '.contentSecurityPolicy.directives["upgrade-insecure-requests"] = null' "$APP_DIR/helmet.json" > "$APP_DIR/helmet.json.tmp" && mv "$APP_DIR/helmet.json.tmp" "$APP_DIR/helmet.json"
  fi

  cp "$APP_DIR"/package.json "$APP_DIR"/bin
  sed -i "s|^start|${APP_DIR}/bin/start|" "$APP_DIR"/bin/immich-admin

  cd "$SRC_DIR" || exit
  echo "packageImportMethod: hardlink" >> ./pnpm-workspace.yaml
  unset SHARP_FORCE_GLOBAL_LIBVIPS
  export SHARP_IGNORE_GLOBAL_LIBVIPS=true
  $STD pnpm --filter @immich/sdk --filter immich-web --filter @immich/cli build
  $STD pnpm --filter @immich/cli --prod --no-optional deploy "$APP_DIR"/cli
  cp -a web/build "$APP_DIR"/www
  cp LICENSE "$APP_DIR"
  cd "$SRC_DIR" || exit
  export MISE_TRUSTED_CONFIG_PATHS="$SRC_DIR"/mise.toml
  export MISE_DISABLE_TOOLS=github:jellyfin/jellyfin-ffmpeg
  $STD mise install
  # shellcheck disable=SC2155
  export PATH="$(mise bin-paths 2> /dev/null | tr '\n' ':')$PATH"
  if ! command -v extism-js > /dev/null 2>&1; then
    EXTISM_ARCH="$(uname -m)"
    curl_download /tmp/extism-js.gz "https://github.com/extism/js-pdk/releases/download/v1.6.0/extism-js-${EXTISM_ARCH}-linux-v1.6.0.gz"
    gunzip -f /tmp/extism-js.gz
    install -m 0755 /tmp/extism-js /usr/local/bin/extism-js
    rm -f /tmp/extism-js
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
      $STD sudo --preserve-env=VIRTUAL_ENV -Pnu immich uv python install "${ML_PYTHON}" && break
      [[ $attempt -lt 3 ]] && msg_warn "Python download attempt $attempt failed, retrying..." && sleep 5
    done
    msg_ok "Pre-installed Python ${ML_PYTHON}"
    msg_info "Installing Intel OpenVINO machine-learning"
    for attempt in $(seq 1 3); do
      $STD sudo --preserve-env=VIRTUAL_ENV,UV_HTTP_TIMEOUT -Pnu immich uv sync --extra openvino --no-dev --active --link-mode copy -n -p "${ML_PYTHON}" --managed-python && break
      [[ $attempt -lt 3 ]] && msg_warn "uv sync attempt $attempt failed, retrying..." && sleep 10
    done
    patchelf --clear-execstack "${VIRTUAL_ENV}/lib/python3.13/site-packages/onnxruntime/capi/onnxruntime_pybind11_state.cpython-313-$(get_system_arch)-linux-gnu.so"
    msg_ok "Installed Intel OpenVINO machine-learning"
  else
    ML_PYTHON="python3.11"
    msg_info "Pre-installing Python ${ML_PYTHON} for machine-learning"
    for attempt in $(seq 1 3); do
      $STD sudo --preserve-env=VIRTUAL_ENV -Pnu immich uv python install "${ML_PYTHON}" && break
      [[ $attempt -lt 3 ]] && msg_warn "Python download attempt $attempt failed, retrying..." && sleep 5
    done
    msg_ok "Pre-installed Python ${ML_PYTHON}"
    msg_info "Installing machine-learning"
    for attempt in $(seq 1 3); do
      $STD sudo --preserve-env=VIRTUAL_ENV,UV_HTTP_TIMEOUT -Pnu immich uv sync --extra cpu --no-dev --active --link-mode copy -n -p "${ML_PYTHON}" --managed-python && break
      [[ $attempt -lt 3 ]] && msg_warn "uv sync attempt $attempt failed, retrying..." && sleep 10
    done
    msg_ok "Installed machine-learning"
  fi
  cd "$SRC_DIR" || exit
  cp -a machine-learning/{ann,immich_ml} "$ML_DIR"
  [[ -f ~/.openvino ]] && sed -i "/intra_op/s/int = 0/int = os.cpu_count() or 0/" "$ML_DIR"/immich_ml/config.py
  ln -sf "$APP_DIR"/resources "$INSTALL_DIR"

  cd "$APP_DIR" || exit
  grep -rl /usr/src | xargs -n1 sed -i "s|\/usr/src|$INSTALL_DIR|g"
  grep -rlE "'/build'" | xargs -n1 sed -i "s|'/build'|'$APP_DIR'|g"
  sed -i "s@\"/cache\"@\"$INSTALL_DIR/cache\"@g" "$ML_DIR"/immich_ml/config.py
  ln -s "$UPLOAD_DIR" "$APP_DIR"/upload
  ln -s "$UPLOAD_DIR" "$ML_DIR"/upload

  msg_info "Installing GeoNames data"
  cd "$GEO_DIR" || exit
  curl_with_retry "https://download.geonames.org/export/dump/admin1CodesASCII.txt" "admin1CodesASCII.txt"
  curl_with_retry "https://download.geonames.org/export/dump/admin2Codes.txt" "admin2Codes.txt"
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
    python3 - << 'PY'
from pathlib import Path
p = Path('/opt/immich/app/dist/repositories/media.repository.js')
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

function compile_libjxl() {
  SOURCE=${SOURCE_DIR}/libjxl
  JPEGLI_LIBJPEG_LIBRARY_SOVERSION="62"
  JPEGLI_LIBJPEG_LIBRARY_VERSION="62.3.0"
  LIBJXL_REVISION="332feb17d17311c748445f7ee75c4fb55cc38530"
  if [[ "$LIBJXL_REVISION" != "$(grep 'libjxl' ~/.immich_library_revisions | awk '{print $2}')" ]]; then
    msg_info "Recompiling libjxl"
    [[ -d "$SOURCE" ]] && rm -rf "$SOURCE"
    $STD git clone https://github.com/libjxl/libjxl.git "$SOURCE"
    cd "$SOURCE" || exit
    $STD git reset --hard "$LIBJXL_REVISION"
    $STD git submodule update --init --recursive --depth 1 --recommend-shallow
    $STD git apply "$BASE_DIR"/server/sources/libjxl-patches/jpegli-empty-dht-marker.patch
    $STD git apply "$BASE_DIR"/server/sources/libjxl-patches/jpegli-icc-warning.patch
    mkdir build
    cd build || exit
    $STD cmake \
      -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_TESTING=OFF \
      -DJPEGXL_ENABLE_DOXYGEN=OFF \
      -DJPEGXL_ENABLE_MANPAGES=OFF \
      -DJPEGXL_ENABLE_PLUGIN_GIMP210=OFF \
      -DJPEGXL_ENABLE_BENCHMARK=OFF \
      -DJPEGXL_ENABLE_EXAMPLES=OFF \
      -DJPEGXL_FORCE_SYSTEM_BROTLI=ON \
      -DJPEGXL_FORCE_SYSTEM_HWY=ON \
      -DJPEGXL_ENABLE_JPEGLI=ON \
      -DJPEGXL_ENABLE_JPEGLI_LIBJPEG=ON \
      -DJPEGXL_INSTALL_JPEGLI_LIBJPEG=ON \
      -DJPEGXL_ENABLE_PLUGINS=ON \
      -DJPEGLI_LIBJPEG_LIBRARY_SOVERSION="$JPEGLI_LIBJPEG_LIBRARY_SOVERSION" \
      -DJPEGLI_LIBJPEG_LIBRARY_VERSION="$JPEGLI_LIBJPEG_LIBRARY_VERSION" \
      -DLIBJPEG_TURBO_VERSION_NUMBER=2001005 \
      ..
    $STD cmake --build . -- -j"$(nproc)"
    $STD cmake --install .
    ldconfig /usr/local/lib
    $STD make clean
    cd "$STAGING_DIR" || exit
    rm -rf "$SOURCE"/{build,third_party}
    sed -i "s/libjxl: .*$/libjxl: $LIBJXL_REVISION/" ~/.immich_library_revisions
    msg_ok "Recompiled libjxl"
  fi
}

function compile_libheif() {
  SOURCE=${SOURCE_DIR}/libheif
  ensure_dependencies libaom-dev
  LIBHEIF_REVISION="62f1b8c76ed4d8305071fdacbe74ef9717bacac5"
  if [[ "${update:-}" ]] || [[ "$LIBHEIF_REVISION" != "$(grep 'libheif' ~/.immich_library_revisions | awk '{print $2}')" ]]; then
    msg_info "Recompiling libheif"
    [[ -d "$SOURCE" ]] && rm -rf "$SOURCE"
    $STD git clone https://github.com/strukturag/libheif.git "$SOURCE"
    cd "$SOURCE" || exit
    $STD git reset --hard "$LIBHEIF_REVISION"
    mkdir build
    cd build || exit
    $STD cmake --preset=release-noplugins \
      -DWITH_DAV1D=ON \
      -DENABLE_PARALLEL_TILE_DECODING=ON \
      -DWITH_LIBSHARPYUV=ON \
      -DWITH_LIBDE265=ON \
      -DWITH_AOM_DECODER=OFF \
      -DWITH_AOM_ENCODER=ON \
      -DWITH_X265=OFF \
      -DWITH_EXAMPLES=OFF \
      ..
    $STD make install -j"$(nproc)"
    ldconfig /usr/local/lib
    $STD make clean
    cd "$STAGING_DIR" || exit
    rm -rf "$SOURCE"/build
    sed -i "s/libheif: .*$/libheif: $LIBHEIF_REVISION/" ~/.immich_library_revisions
    msg_ok "Recompiled libheif"
  fi
}

function compile_libraw() {
  SOURCE=${SOURCE_DIR}/libraw
  LIBRAW_REVISION="b860248a89d9082b8e0a1e202e516f46af9adb29"
  if [[ "$LIBRAW_REVISION" != "$(grep 'libraw' ~/.immich_library_revisions | awk '{print $2}')" ]]; then
    msg_info "Recompiling libraw"
    [[ -d "$SOURCE" ]] && rm -rf "$SOURCE"
    $STD git clone https://github.com/LibRaw/LibRaw.git "$SOURCE"
    cd "$SOURCE" || exit
    $STD git reset --hard "$LIBRAW_REVISION"
    $STD autoreconf --install
    $STD ./configure --disable-examples
    $STD make -j"$(nproc)"
    $STD make install
    ldconfig /usr/local/lib
    $STD make clean
    cd "$STAGING_DIR" || exit
    sed -i "s/libraw: .*$/libraw: $LIBRAW_REVISION/" ~/.immich_library_revisions
    msg_ok "Recompiled libraw"
  fi
}

function compile_imagemagick() {
  SOURCE=$SOURCE_DIR/imagemagick
  : "${IMAGEMAGICK_REVISION:=$(jq -cr '.revision' $BASE_DIR/server/sources/imagemagick.json)}"
  if [[ "$IMAGEMAGICK_REVISION" != "$(grep 'imagemagick' ~/.immich_library_revisions | awk '{print $2}')" ]] ||
    ! grep -q 'DMAGICK_LIBRAW' /usr/local/lib/ImageMagick-7*/config-Q16HDRI/configure.xml; then
    msg_info "Recompiling ImageMagick"
    [[ -d "$SOURCE" ]] && rm -rf "$SOURCE"
    $STD git clone https://github.com/ImageMagick/ImageMagick.git "$SOURCE"
    cd "$SOURCE" || exit
    $STD git reset --hard "$IMAGEMAGICK_REVISION"
    $STD ./configure --with-modules CPPFLAGS="-DMAGICK_LIBRAW_VERSION_TAIL=202502"
    $STD make -j"$(nproc)"
    $STD make install
    ldconfig /usr/local/lib
    $STD make clean
    cd "$STAGING_DIR" || exit
    sed -i "s/imagemagick: .*$/imagemagick: $IMAGEMAGICK_REVISION/" ~/.immich_library_revisions
    msg_ok "Recompiled ImageMagick"
  fi
}

function compile_libvips() {
  SOURCE=$SOURCE_DIR/libvips
  LIBVIPS_REVISION="e01a4797cabe77d457fdfa7d776b7a7e7ca6d6a7"
  if [[ "$LIBVIPS_REVISION" != "$(grep 'libvips' ~/.immich_library_revisions | awk '{print $2}')" ]]; then
    msg_info "Recompiling libvips"
    [[ -d "$SOURCE" ]] && rm -rf "$SOURCE"
    $STD git clone https://github.com/libvips/libvips.git "$SOURCE"
    cd "$SOURCE" || exit
    $STD git reset --hard "$LIBVIPS_REVISION"
    $STD git apply "$BASE_DIR"/server/sources/libvips-patches/0001-put-other-loaders-ahead-of-dcrawload.patch
    $STD meson setup build --buildtype=release --libdir=lib -Dintrospection=disabled -Dtiff=disabled
    cd build || exit
    $STD ninja install
    ldconfig /usr/local/lib
    cd "$STAGING_DIR" || exit
    rm -rf "$SOURCE"/build
    sed -i "s/libvips: .*$/libvips: $LIBVIPS_REVISION/" ~/.immich_library_revisions
    msg_ok "Recompiled libvips"
  fi
}

function update_script() {
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

  STAGING_DIR=/opt/staging
  BASE_DIR=${STAGING_DIR}/base-images
  SOURCE_DIR=${STAGING_DIR}/image-source
  cd /tmp || exit
  if [[ -f ~/.intel_version ]]; then
    curl_with_retry "https://raw.githubusercontent.com/immich-app/immich/refs/heads/main/machine-learning/Dockerfile" "Dockerfile"
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
  if [[ -f ~/.immich_library_revisions ]]; then
    libraries=("libjxl" "libheif" "libraw" "imagemagick" "libvips")
    cd "$BASE_DIR" || exit
    msg_warn "Checking for updates to custom image-processing libraries (recompile time: 2-15min per library)"
    $STD git pull
    for library in "${libraries[@]}"; do
      compile_"$library"
    done
    msg_ok "Image-processing libraries up to date"
  fi

  RELEASE="v3.0.3"
  if check_for_gh_release "Immich" "$var_lxc_git_repo" "${RELEASE}" "each release is tested individually before the version is updated. Please do not open issues for this"; then
    if [[ $(cat ~/.immich) > "2.5.1" ]]; then
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
    if check_for_gh_release "VectorChord" "tensorchord/VectorChord" "${VCHORD_RELEASE}" "updated together with Immich after testing"; then
      $STD sudo -u postgres psql -d immich -c "VACUUM (ANALYZE) smart_search;"
      $STD sudo -u postgres psql -d immich -c "VACUUM (ANALYZE) face_search;"
      fetch_and_deploy_gh_release "VectorChord" "tensorchord/VectorChord" "binary" "${VCHORD_RELEASE}" "/tmp" "postgresql-${PG_VERSION}-vchord_*_$(get_system_arch).deb"
      systemctl restart postgresql
      $STD sudo -u postgres psql -d immich -c "ALTER EXTENSION vector UPDATE;"
      $STD sudo -u postgres psql -d immich -c "ALTER EXTENSION vchord UPDATE;"
      $STD sudo -u postgres psql -d immich -c "REINDEX INDEX face_index;"
      $STD sudo -u postgres psql -d immich -c "REINDEX INDEX clip_index;"
    fi
    ensure_dependencies ccache gcc-13 g++-13

    INSTALL_DIR="/opt/${APP}"
    UPLOAD_DIR="$(sed -n '/^IMMICH_MEDIA_LOCATION/s/[^=]*=//p' /opt/immich/.env)"
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

    (
      shopt -s dotglob
      rm -rf "${APP_DIR:?}"/*
    )

    setup_uv
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "Immich" "$var_lxc_git_repo" "tarball" "${RELEASE}" "$SRC_DIR"
    PNPM_VERSION="$(jq -r '.packageManager | split("@")[1] | split("+")[0]' ${SRC_DIR}/package.json)"
    export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
    export CI=1
    NODE_VERSION="24" NODE_MODULE="corepack" setup_nodejs
    $STD corepack prepare "pnpm@${PNPM_VERSION}" --activate
    export PATH="/root/.local/share/pnpm/bin:$PATH"
    $STD pnpm config set --global dangerouslyAllowAllBuilds true

    msg_info "Updating Immich web and microservices"
    cd "$SRC_DIR"/server || exit
    export SHARP_IGNORE_GLOBAL_LIBVIPS=true
    $STD pnpm --filter @immich/sdk --filter @immich/plugin-sdk --filter immich build
    unset SHARP_IGNORE_GLOBAL_LIBVIPS
    export SHARP_FORCE_GLOBAL_LIBVIPS=true
    $STD pnpm --filter immich --prod --no-optional deploy "$APP_DIR"

    if [[ -f "$APP_DIR/helmet.json" ]]; then
      jq '.contentSecurityPolicy.directives["upgrade-insecure-requests"] = null' "$APP_DIR/helmet.json" > "$APP_DIR/helmet.json.tmp" && mv "$APP_DIR/helmet.json.tmp" "$APP_DIR/helmet.json"
    fi

    cp "$APP_DIR"/package.json "$APP_DIR"/bin
    sed -i "s|^start|${APP_DIR}/bin/start|" "$APP_DIR"/bin/immich-admin

    cd "$SRC_DIR" || exit
    echo "packageImportMethod: hardlink" >> ./pnpm-workspace.yaml
    unset SHARP_FORCE_GLOBAL_LIBVIPS
    export SHARP_IGNORE_GLOBAL_LIBVIPS=true
    $STD pnpm --filter @immich/sdk --filter immich-web --filter @immich/cli build
    $STD pnpm --filter @immich/cli --prod --no-optional deploy "$APP_DIR"/cli
    cp -a web/build "$APP_DIR"/www
    cp LICENSE "$APP_DIR"
    [[ -f "$INSTALL_DIR"/start.sh ]] && mv "$INSTALL_DIR"/start.sh "$APP_DIR"/bin

    cd "$SRC_DIR" || exit
    export MISE_TRUSTED_CONFIG_PATHS="$SRC_DIR"/mise.toml
    export MISE_DISABLE_TOOLS=github:jellyfin/jellyfin-ffmpeg
    $STD mise install
    # shellcheck disable=SC2155
    export PATH="$(mise bin-paths 2> /dev/null | tr '\n' ':')$PATH"
    if ! command -v extism-js > /dev/null 2>&1; then
      EXTISM_ARCH="$(uname -m)"
      curl_download /tmp/extism-js.gz "https://github.com/extism/js-pdk/releases/download/v1.6.0/extism-js-${EXTISM_ARCH}-linux-v1.6.0.gz"
      gunzip -f /tmp/extism-js.gz
      install -m 0755 /tmp/extism-js /usr/local/bin/extism-js
      rm -f /tmp/extism-js
    fi
    if ! command -v wasm-merge > /dev/null 2>&1; then
      BINARYEN_VERSION="$(grep -oiP 'binaryen"\s*=\s*"\Kversion_[0-9]+' "$SRC_DIR"/mise.toml | head -n1)"
      [[ -z "$BINARYEN_VERSION" ]] && BINARYEN_VERSION="version_124"
      BINARYEN_ARCH="$(uname -m)"
      curl_download /tmp/binaryen.tar.gz "https://github.com/WebAssembly/binaryen/releases/download/${BINARYEN_VERSION}/binaryen-${BINARYEN_VERSION}-${BINARYEN_ARCH}-linux.tar.gz"
      tar -xzf /tmp/binaryen.tar.gz -C /opt
      rm -f /tmp/binaryen.tar.gz
      export PATH="/opt/binaryen-${BINARYEN_VERSION}/bin:$PATH"
    fi
    $STD mise exec -- pnpm --filter @immich/sdk --filter @immich/plugin-sdk --filter @immich/plugin-core install --frozen-lockfile
    $STD mise exec -- pnpm --filter @immich/sdk --filter @immich/plugin-sdk --filter @immich/plugin-core build
    mkdir -p "$PLUGIN_DIR"
    cp -r ./packages/plugin-core/dist "$PLUGIN_DIR"/dist
    cp ./packages/plugin-core/manifest.json "$PLUGIN_DIR"
    msg_ok "Updated Immich server, web, cli and plugins"

    cd "$SRC_DIR"/machine-learning || exit
    mkdir -p "$ML_DIR"
    chown immich:immich "$INSTALL_DIR"
    find "$INSTALL_DIR" -maxdepth 1 -mindepth 1 ! -name upload -exec chown -R immich:immich {} +
    chown immich:immich "${UPLOAD_DIR:-$INSTALL_DIR/upload}" 2> /dev/null || true
    chown immich:immich ./uv.lock
    export VIRTUAL_ENV="${ML_DIR}"/ml-venv
    export UV_HTTP_TIMEOUT=300
    if [[ -f ~/.openvino ]]; then
      ML_PYTHON="python3.13"
      msg_info "Pre-installing Python ${ML_PYTHON} for machine-learning"
      for attempt in $(seq 1 3); do
        $STD sudo --preserve-env=VIRTUAL_ENV -Pnu immich uv python install "${ML_PYTHON}" && break
        [[ $attempt -lt 3 ]] && msg_warn "Python download attempt $attempt failed, retrying..." && sleep 5
      done
      msg_ok "Pre-installed Python ${ML_PYTHON}"
      msg_info "Updating Intel OpenVINO machine-learning"
      for attempt in $(seq 1 3); do
        $STD sudo --preserve-env=VIRTUAL_ENV,UV_HTTP_TIMEOUT -Pnu immich uv sync --extra openvino --no-dev --active --link-mode copy -n -p "${ML_PYTHON}" --managed-python && break
        [[ $attempt -lt 3 ]] && msg_warn "uv sync attempt $attempt failed, retrying..." && sleep 10
      done
      patchelf --clear-execstack "${VIRTUAL_ENV}/lib/python3.13/site-packages/onnxruntime/capi/onnxruntime_pybind11_state.cpython-313-$(get_system_arch)-linux-gnu.so"
      msg_ok "Updated Intel OpenVINO machine-learning"
    else
      ML_PYTHON="python3.11"
      msg_info "Pre-installing Python ${ML_PYTHON} for machine-learning"
      for attempt in $(seq 1 3); do
        $STD sudo --preserve-env=VIRTUAL_ENV -Pnu immich uv python install "${ML_PYTHON}" && break
        [[ $attempt -lt 3 ]] && msg_warn "Python download attempt $attempt failed, retrying..." && sleep 5
      done
      msg_ok "Pre-installed Python ${ML_PYTHON}"
      msg_info "Updating machine-learning"
      for attempt in $(seq 1 3); do
        $STD sudo --preserve-env=VIRTUAL_ENV,UV_HTTP_TIMEOUT -Pnu immich uv sync --extra cpu --no-dev --active --link-mode copy -n -p "${ML_PYTHON}" --managed-python && break
        [[ $attempt -lt 3 ]] && msg_warn "uv sync attempt $attempt failed, retrying..." && sleep 10
      done
      msg_ok "Updated machine-learning"
    fi
    cd "$SRC_DIR" || exit
    cp -a machine-learning/{ann,immich_ml} "$ML_DIR"
    [[ -f "$INSTALL_DIR"/ml_start.sh ]] && mv "$INSTALL_DIR"/ml_start.sh "$ML_DIR"
    if [[ ! -f "$ML_DIR"/ml_start.sh ]]; then
      cat << EOF > "$ML_DIR"/ml_start.sh
#!/usr/bin/env bash

cd ${ML_DIR} || exit
. ${VIRTUAL_ENV}/bin/activate

set -a
. ${INSTALL_DIR}/.env
set +a

python3 -m immich_ml
EOF
      chmod +x "$ML_DIR"/ml_start.sh
    fi
    [[ -f ~/.openvino ]] && sed -i "/intra_op/s/int = 0/int = os.cpu_count() or 0/" "$ML_DIR"/immich_ml/config.py
    ln -sf "$APP_DIR"/resources "$INSTALL_DIR"
    cd "$APP_DIR" || exit
    grep -rl /usr/src | xargs -n1 sed -i "s|\/usr/src|$INSTALL_DIR|g"
    grep -rlE "'/build'" | xargs -n1 sed -i "s|'/build'|'$APP_DIR'|g"
    sed -i "s@\"/cache\"@\"$INSTALL_DIR/cache\"@g" "$ML_DIR"/immich_ml/config.py
    ln -s "${UPLOAD_DIR:-/opt/immich/upload}" "$APP_DIR"/upload
    ln -s "${UPLOAD_DIR:-/opt/immich/upload}" "$ML_DIR"/upload
    ln -s "$GEO_DIR" "$APP_DIR"
    [[ ! -f /usr/bin/immich ]] && ln -sf "$APP_DIR"/cli/bin/immich /usr/bin/immich
    [[ ! -f /usr/bin/immich-admin ]] && ln -sf "$APP_DIR"/bin/immich-admin /usr/bin/immich-admin

    if ! grep -q '^DB_HOSTNAME=' "$INSTALL_DIR"/.env; then
      sed -i '/^DB_DATABASE_NAME/a DB_HOSTNAME=127.0.0.1' "$INSTALL_DIR"/.env
    fi
    if ! grep -q 'HELMET_FILE' "$INSTALL_DIR"/.env; then
      sed -i -e '$a\' "$INSTALL_DIR"/.env
      echo "IMMICH_HELMET_FILE=true" >> "$INSTALL_DIR"/.env
    fi

    if grep -q 'ExecStart=/usr/bin/node' /etc/systemd/system/immich-web.service; then
      sed -i '/^EnvironmentFile=/d' /etc/systemd/system/immich-web.service
      sed -i "s|^ExecStart=.*|ExecStart=${APP_DIR}/bin/start.sh|" /etc/systemd/system/immich-web.service
      systemctl daemon-reload
    fi

    msg_info "Patching media.repository.js"
    MEDIA_REPO_JS="/opt/immich/app/dist/repositories/media.repository.js"
    if [[ -f "$MEDIA_REPO_JS" ]]; then
      python3 - << 'PY'
from pathlib import Path
p = Path('/opt/immich/app/dist/repositories/media.repository.js')
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

    chown immich:immich "$INSTALL_DIR"
    find "$INSTALL_DIR" -maxdepth 1 -mindepth 1 ! -name upload -exec chown -R immich:immich {} +
    chown immich:immich "${UPLOAD_DIR:-$INSTALL_DIR/upload}" 2> /dev/null || true
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
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
