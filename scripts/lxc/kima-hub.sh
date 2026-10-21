#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/Chevron7Locked/kima-hub

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Kima-Hub"
var_tags="${var_tags:-music;streaming;media}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    build-essential \
    git \
    openssl \
    ffmpeg \
    python3 \
    python3-dev \
    libsndfile1 \
    libfftw3-single3 \
    libsamplerate0 \
    libyaml-0-2 \
    redis-server
  msg_ok "Installed Dependencies"

  PG_VERSION="16" PG_MODULES="pgvector" setup_postgresql
  PG_DB_NAME="kima" PG_DB_USER="kima" PG_DB_GRANT_SUPERUSER="true" setup_postgresql_db
  NODE_VERSION="22" setup_nodejs
  PYTHON_VERSION="3.11" setup_uv

  msg_info "Configuring Redis"
  systemctl enable -q --now redis-server
  msg_ok "Configured Redis"

  fetch_and_deploy_gh_release "kima-hub" "Chevron7Locked/kima-hub" "tarball"

  msg_info "Installing Python Dependencies"
  cd /opt/kima-hub || exit
  $STD uv venv --python 3.11 /opt/kima-hub/venv
  $STD uv pip install --no-cache --python /opt/kima-hub/venv/bin/python -r services/audio-analyzer/requirements.txt -r services/audio-analyzer-clap/requirements.txt
  # Upstream's outside-image recipe explicitly supplies its parity-tested NumPy
  # pin before the Essentia wheel (whose dependency metadata is overly strict).
  $STD uv pip install --no-cache --no-deps --python /opt/kima-hub/venv/bin/python essentia==2.1b6.dev1389
  cp -a services/audio-analyzer-clap/gpu_switch.py services/audio-analyzer/
  msg_ok "Installed Python Dependencies"

  msg_info "Preparing Supported ONNX Models"
  local builder model_rc
  builder=$(mktemp -d "${TMPDIR:-/tmp}/kima-onnx.XXXXXX") || exit $?
  mkdir -p "$builder/ckpt" services/audio-analyzer-clap/models
  if $STD uv venv --python 3.11 "$builder/venv" &&
    $STD uv pip install --no-cache --python "$builder/venv/bin/python" --index-url https://download.pytorch.org/whl/cpu --extra-index-url https://pypi.org/simple torch==2.8.0 transformers==4.57.6 onnx 'numpy<2' &&
    curl_with_retry https://huggingface.co/laion/clap-htsat-unfused/resolve/8fa0f1c6d0433df6e97c127f64b2a1d6c0dcda8a/pytorch_model.bin "$builder/ckpt/pytorch_model.bin" &&
    printf '%s  %s\n' 1cd3c601bc4afe0fa87be3de4c13dd2cfadd249fac1e29acf74a9b296c3219bb "$builder/ckpt/pytorch_model.bin" | sha256sum -c - &&
    curl_with_retry https://huggingface.co/laion/clap-htsat-unfused/resolve/8fa0f1c6d0433df6e97c127f64b2a1d6c0dcda8a/config.json "$builder/ckpt/config.json" &&
    printf '%s  %s\n' 9efb9557bc804f2ca6e394486af2e45dfed0b18554909735a99c6220b84e4288 "$builder/ckpt/config.json" | sha256sum -c - &&
    curl_with_retry https://huggingface.co/laion/clap-htsat-unfused/resolve/8fa0f1c6d0433df6e97c127f64b2a1d6c0dcda8a/preprocessor_config.json "$builder/ckpt/preprocessor_config.json" &&
    printf '%s  %s\n' 9739f58296aa6f9ac18008fd0150fb2649bc554985fbde86d0a4041c882ac753 "$builder/ckpt/preprocessor_config.json" | sha256sum -c - &&
    $STD "$builder/venv/bin/python" services/audio-analyzer-clap/export_onnx.py --src "$builder/ckpt" --out "$builder/hf_audio.onnx" &&
    printf '%s  %s\n' 37df17afb9881569c4f50e5b691167aa54586418059701a74a54934514969972 "$builder/hf_audio.onnx" | sha256sum -c - &&
    curl_with_retry https://huggingface.co/Xenova/clap-htsat-unfused/resolve/main/onnx/text_model.onnx "$builder/text_model.onnx" &&
    printf '%s  %s\n' 6df7c51f2d78e236a03f2b816e613d538c815639d13644fe7c2124f439da9648 "$builder/text_model.onnx" | sha256sum -c - &&
    mv -n -- "$builder/hf_audio.onnx" "$builder/text_model.onnx" services/audio-analyzer-clap/models/; then :; else
    model_rc=$?
    _deploy_remove_owned_trees "$builder"
    exit "$model_rc"
  fi
  _deploy_remove_owned_trees "$builder"
  printf '%s  %s\n' 37df17afb9881569c4f50e5b691167aa54586418059701a74a54934514969972 services/audio-analyzer-clap/models/hf_audio.onnx 6df7c51f2d78e236a03f2b816e613d538c815639d13644fe7c2124f439da9648 services/audio-analyzer-clap/models/text_model.onnx | sha256sum -c -
  # These are the exact pinned offline cache inputs used by upstream's parity
  # gate. Never replace a pre-existing cache file on an integrity failure.
  local hash repo revision name directory temporary cache_rc
  while read -r hash repo revision name; do
    directory="/root/.cache/huggingface/hub/models--${repo//\//--}"
    mkdir -p "$directory/snapshots/$revision" "$directory/refs"
    if [[ ! -e "$directory/snapshots/$revision/$name" ]]; then
      temporary=$(mktemp "$directory/snapshots/$revision/.kima-cache.XXXXXX") || exit $?
      if curl_with_retry "https://huggingface.co/$repo/resolve/$revision/$name" "$temporary" && printf '%s  %s\n' "$hash" "$temporary" | sha256sum -c -; then
        mv -n -- "$temporary" "$directory/snapshots/$revision/$name"
        rm -f -- "$temporary"
      else
        cache_rc=$?
        rm -f -- "$temporary"
        exit "$cache_rc"
      fi
    fi
    printf '%s  %s\n' "$hash" "$directory/snapshots/$revision/$name" | sha256sum -c -
    printf '%s' "$revision" > "$directory/refs/main"
  done << 'MODELS'
9739f58296aa6f9ac18008fd0150fb2649bc554985fbde86d0a4041c882ac753 laion/clap-htsat-unfused 8fa0f1c6d0433df6e97c127f64b2a1d6c0dcda8a preprocessor_config.json
9e7f63c2d15d666b52e21d250d2e513b87c9b713cfa6987a82ed89e5e6e50655 roberta-base e2da8e2f811d1448a5b465c236feacd80ffbac7b vocab.json
1ce1664773c50f3e0cc8842619a93edc4624525b728b188a9e0be33b7726adc5 roberta-base e2da8e2f811d1448a5b465c236feacd80ffbac7b merges.txt
847bbeab6174d66a88898f729d52fa8d355fafe1bea101cf960dd404581df70e roberta-base e2da8e2f811d1448a5b465c236feacd80ffbac7b tokenizer.json
994f46754c5bf4014f1aa92d34b1374319c3a6b3f702105cd5b742beaecd18ce roberta-base e2da8e2f811d1448a5b465c236feacd80ffbac7b tokenizer_config.json
MODELS
  $STD /opt/kima-hub/venv/bin/python services/audio-analyzer/convert_musicnn.py gate services/audio-analyzer/models services/audio-analyzer/models/musicnn-answers.npz
  cd services/audio-analyzer-clap || exit
  HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 $STD /opt/kima-hub/venv/bin/python verify_runtime.py
  msg_ok "Prepared Supported ONNX Models"

  msg_info "Building Backend"
  cd /opt/kima-hub/backend || exit
  $STD npm ci
  $STD npm run build
  msg_ok "Built Backend"

  msg_info "Configuring Backend"
  SESSION_SECRET=$(openssl rand -hex 32)
  ENCRYPTION_KEY=$(openssl rand -hex 32)
  cat << EOF > /opt/kima-hub/backend/.env
NODE_ENV=production
DATABASE_URL=postgresql://${PG_DB_USER}:${PG_DB_PASS}@localhost:5432/${PG_DB_NAME}
REDIS_URL=redis://localhost:6379
PORT=3006
MUSIC_PATH=/music
TRANSCODE_CACHE_PATH=/opt/kima-hub/cache/transcodes
SESSION_SECRET=${SESSION_SECRET}
SETTINGS_ENCRYPTION_KEY=${ENCRYPTION_KEY}
INTERNAL_API_SECRET=$(openssl rand -hex 16)
EOF
  msg_ok "Configured Backend"

  msg_info "Running Database Migrations"
  cd /opt/kima-hub/backend || exit
  $STD npx prisma generate
  $STD npx prisma migrate deploy
  msg_ok "Ran Database Migrations"

  msg_info "Building Frontend"
  cd /opt/kima-hub/frontend || exit
  $STD npm ci
  export NEXT_PUBLIC_BACKEND_URL=http://127.0.0.1:3006
  $STD npm run build
  msg_ok "Built Frontend"

  msg_info "Configuring Frontend"
  cat << EOF > /opt/kima-hub/frontend/.env
NODE_ENV=production
BACKEND_URL=http://localhost:3006
PORT=3030
EOF
  msg_ok "Configured Frontend"

  msg_info "Creating Directories"
  mkdir -p /opt/kima-hub/cache/transcodes
  mkdir -p /music
  msg_ok "Created Directories"

  msg_info "Creating Services"
  cat << EOF > /etc/systemd/system/kima-backend.service
[Unit]
Description=Kima Hub Backend
After=network.target postgresql.service redis-server.service
Wants=postgresql.service redis-server.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/kima-hub/backend
EnvironmentFile=/opt/kima-hub/backend/.env
ExecStart=/usr/bin/node /opt/kima-hub/backend/dist/index.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  cat << EOF > /etc/systemd/system/kima-frontend.service
[Unit]
Description=Kima Hub Frontend
After=network.target kima-backend.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/kima-hub/frontend
EnvironmentFile=/opt/kima-hub/frontend/.env
ExecStart=/usr/bin/npm start
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  cat << EOF > /etc/systemd/system/kima-analyzer.service
[Unit]
Description=Kima Hub Audio Analyzer (Essentia)
After=network.target postgresql.service redis-server.service kima-backend.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/kima-hub/services/audio-analyzer
Environment=DATABASE_URL=postgresql://${PG_DB_USER}:${PG_DB_PASS}@localhost:5432/${PG_DB_NAME}
Environment=REDIS_URL=redis://localhost:6379
Environment=MUSIC_PATH=/music
Environment=BATCH_SIZE=10
Environment=SLEEP_INTERVAL=5
Environment=NUM_WORKERS=2
Environment=THREADS_PER_WORKER=1
BindReadOnlyPaths=/opt/kima-hub/services/audio-analyzer/models:/app/models
ExecStart=/opt/kima-hub/venv/bin/python /opt/kima-hub/services/audio-analyzer/analyzer.py
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

  cat << EOF > /etc/systemd/system/kima-analyzer-clap.service
[Unit]
Description=Kima Hub CLAP Audio Analyzer
After=network.target postgresql.service redis-server.service kima-backend.service kima-analyzer.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/kima-hub/services/audio-analyzer-clap
Environment=DATABASE_URL=postgresql://${PG_DB_USER}:${PG_DB_PASS}@localhost:5432/${PG_DB_NAME}
Environment=REDIS_URL=redis://localhost:6379
Environment=BACKEND_URL=http://localhost:3006
Environment=MUSIC_PATH=/music
Environment=SLEEP_INTERVAL=5
Environment=NUM_WORKERS=1
ExecStart=/opt/kima-hub/venv/bin/python /opt/kima-hub/services/audio-analyzer-clap/analyzer.py
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now kima-backend kima-frontend kima-analyzer kima-analyzer-clap
  msg_ok "Created Services"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:3030${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/kima-hub ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  NODE_VERSION="22" setup_nodejs
  PYTHON_VERSION="3.11" setup_uv

  if check_for_gh_release "kima-hub" "Chevron7Locked/kima-hub"; then
    msg_info "Stopping Services"
    systemctl stop kima-frontend kima-backend kima-analyzer kima-analyzer-clap
    msg_ok "Stopped Services"

    [[ -f /opt/kima-hub/backend/.env && -f /opt/kima-hub/frontend/.env ]] || exit 65
    local -a CLEAN_INSTALL_KEEP_PATHS=("${CLEAN_INSTALL_KEEP_PATHS[@]}" backend/.env frontend/.env models cache venv services/audio-analyzer-clap/models)
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "kima-hub" "Chevron7Locked/kima-hub" "tarball"
    cd /opt/kima-hub || exit
    if [[ ! -x venv/bin/python ]]; then $STD uv venv --python 3.11 /opt/kima-hub/venv; fi
    $STD /opt/kima-hub/venv/bin/python -c 'import sys; assert sys.version_info[:2] == (3, 11), "Kima source wheels require a Python3.11 environment"'
    $STD uv pip install --no-cache --python /opt/kima-hub/venv/bin/python -r services/audio-analyzer/requirements.txt -r services/audio-analyzer-clap/requirements.txt
    $STD uv pip install --no-cache --no-deps --python /opt/kima-hub/venv/bin/python essentia==2.1b6.dev1389
    cp -a services/audio-analyzer-clap/gpu_switch.py services/audio-analyzer/
    # A preserved model is data: reject incompatible bytes rather than silently
    # replacing them. Build missing inputs privately before publishing anything.
    if [[ -e services/audio-analyzer-clap/models/hf_audio.onnx ]]; then
      printf '%s  %s\n' 37df17afb9881569c4f50e5b691167aa54586418059701a74a54934514969972 services/audio-analyzer-clap/models/hf_audio.onnx | sha256sum -c -
    fi
    if [[ -e services/audio-analyzer-clap/models/text_model.onnx ]]; then
      printf '%s  %s\n' 6df7c51f2d78e236a03f2b816e613d538c815639d13644fe7c2124f439da9648 services/audio-analyzer-clap/models/text_model.onnx | sha256sum -c -
    fi
    if [[ ! -s services/audio-analyzer-clap/models/hf_audio.onnx || ! -s services/audio-analyzer-clap/models/text_model.onnx ]]; then
      local builder model_rc
      builder=$(mktemp -d "${TMPDIR:-/tmp}/kima-onnx.XXXXXX") || exit $?
      mkdir -p "$builder/ckpt" services/audio-analyzer-clap/models
      if $STD uv venv --python 3.11 "$builder/venv" &&
        $STD uv pip install --no-cache --python "$builder/venv/bin/python" --index-url https://download.pytorch.org/whl/cpu --extra-index-url https://pypi.org/simple torch==2.8.0 transformers==4.57.6 onnx 'numpy<2' &&
        curl_with_retry https://huggingface.co/laion/clap-htsat-unfused/resolve/8fa0f1c6d0433df6e97c127f64b2a1d6c0dcda8a/pytorch_model.bin "$builder/ckpt/pytorch_model.bin" &&
        printf '%s  %s\n' 1cd3c601bc4afe0fa87be3de4c13dd2cfadd249fac1e29acf74a9b296c3219bb "$builder/ckpt/pytorch_model.bin" | sha256sum -c - &&
        curl_with_retry https://huggingface.co/laion/clap-htsat-unfused/resolve/8fa0f1c6d0433df6e97c127f64b2a1d6c0dcda8a/config.json "$builder/ckpt/config.json" &&
        printf '%s  %s\n' 9efb9557bc804f2ca6e394486af2e45dfed0b18554909735a99c6220b84e4288 "$builder/ckpt/config.json" | sha256sum -c - &&
        curl_with_retry https://huggingface.co/laion/clap-htsat-unfused/resolve/8fa0f1c6d0433df6e97c127f64b2a1d6c0dcda8a/preprocessor_config.json "$builder/ckpt/preprocessor_config.json" &&
        printf '%s  %s\n' 9739f58296aa6f9ac18008fd0150fb2649bc554985fbde86d0a4041c882ac753 "$builder/ckpt/preprocessor_config.json" | sha256sum -c - &&
        $STD "$builder/venv/bin/python" services/audio-analyzer-clap/export_onnx.py --src "$builder/ckpt" --out "$builder/hf_audio.onnx" &&
        printf '%s  %s\n' 37df17afb9881569c4f50e5b691167aa54586418059701a74a54934514969972 "$builder/hf_audio.onnx" | sha256sum -c - &&
        curl_with_retry https://huggingface.co/Xenova/clap-htsat-unfused/resolve/main/onnx/text_model.onnx "$builder/text_model.onnx" &&
        printf '%s  %s\n' 6df7c51f2d78e236a03f2b816e613d538c815639d13644fe7c2124f439da9648 "$builder/text_model.onnx" | sha256sum -c - &&
        mv -n -- "$builder/hf_audio.onnx" "$builder/text_model.onnx" services/audio-analyzer-clap/models/; then :; else
        model_rc=$?
        _deploy_remove_owned_trees "$builder"
        exit "$model_rc"
      fi
      _deploy_remove_owned_trees "$builder"
    fi
    printf '%s  %s\n' 37df17afb9881569c4f50e5b691167aa54586418059701a74a54934514969972 services/audio-analyzer-clap/models/hf_audio.onnx 6df7c51f2d78e236a03f2b816e613d538c815639d13644fe7c2124f439da9648 services/audio-analyzer-clap/models/text_model.onnx | sha256sum -c -
    local hash repo revision name directory temporary cache_rc
    while read -r hash repo revision name; do
      directory="/root/.cache/huggingface/hub/models--${repo//\//--}"
      mkdir -p "$directory/snapshots/$revision" "$directory/refs"
      if [[ ! -e "$directory/snapshots/$revision/$name" ]]; then
        temporary=$(mktemp "$directory/snapshots/$revision/.kima-cache.XXXXXX") || exit $?
        if curl_with_retry "https://huggingface.co/$repo/resolve/$revision/$name" "$temporary" && printf '%s  %s\n' "$hash" "$temporary" | sha256sum -c -; then
          mv -n -- "$temporary" "$directory/snapshots/$revision/$name"
          rm -f -- "$temporary"
        else
          cache_rc=$?
          rm -f -- "$temporary"
          exit "$cache_rc"
        fi
      fi
      printf '%s  %s\n' "$hash" "$directory/snapshots/$revision/$name" | sha256sum -c -
      printf '%s' "$revision" > "$directory/refs/main"
    done << 'MODELS'
9739f58296aa6f9ac18008fd0150fb2649bc554985fbde86d0a4041c882ac753 laion/clap-htsat-unfused 8fa0f1c6d0433df6e97c127f64b2a1d6c0dcda8a preprocessor_config.json
9e7f63c2d15d666b52e21d250d2e513b87c9b713cfa6987a82ed89e5e6e50655 roberta-base e2da8e2f811d1448a5b465c236feacd80ffbac7b vocab.json
1ce1664773c50f3e0cc8842619a93edc4624525b728b188a9e0be33b7726adc5 roberta-base e2da8e2f811d1448a5b465c236feacd80ffbac7b merges.txt
847bbeab6174d66a88898f729d52fa8d355fafe1bea101cf960dd404581df70e roberta-base e2da8e2f811d1448a5b465c236feacd80ffbac7b tokenizer.json
994f46754c5bf4014f1aa92d34b1374319c3a6b3f702105cd5b742beaecd18ce roberta-base e2da8e2f811d1448a5b465c236feacd80ffbac7b tokenizer_config.json
MODELS
    $STD /opt/kima-hub/venv/bin/python services/audio-analyzer/convert_musicnn.py gate services/audio-analyzer/models services/audio-analyzer/models/musicnn-answers.npz
    cd services/audio-analyzer-clap || exit
    HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 $STD /opt/kima-hub/venv/bin/python verify_runtime.py
    # Preserve every existing environment/port/user option while changing only
    # the interpreter. The main analyzer's source fixes its model root at /app.
    local unit
    for unit in kima-analyzer kima-analyzer-clap; do
      [[ -f "/etc/systemd/system/$unit.service" ]] || exit 65
      sed -i -E 's#^(ExecStart=)(/usr/bin/python3|/opt/kima-hub/venv/bin/python)([[:space:]])#\1/opt/kima-hub/venv/bin/python\3#' "/etc/systemd/system/$unit.service"
    done
    if ! grep -q '^[[:space:]]*BindReadOnlyPaths=.*:/app/models\([[:space:]]\|$\)' /etc/systemd/system/kima-analyzer.service; then
      sed -i '/^\[Service\]/a BindReadOnlyPaths=/opt/kima-hub/services/audio-analyzer/models:/app/models' /etc/systemd/system/kima-analyzer.service
    fi
    systemctl daemon-reload

    msg_info "Rebuilding Backend"
    cd /opt/kima-hub/backend || exit
    $STD npm install
    $STD npm run build
    $STD npx prisma generate
    $STD npx prisma migrate deploy
    msg_ok "Rebuilt Backend"

    msg_info "Rebuilding Frontend"
    cd /opt/kima-hub/frontend || exit
    $STD npm install
    $STD npm run build
    msg_ok "Rebuilt Frontend"

    msg_info "Starting Services"
    systemctl start kima-backend kima-frontend kima-analyzer kima-analyzer-clap
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
