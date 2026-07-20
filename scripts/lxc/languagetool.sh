#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://languagetool.org/

# shellcheck disable=SC2034
APP="LanguageTool"
var_tags="${var_tags:-spellcheck}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-16}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y fasttext
  msg_ok "Installed Dependencies"

  JAVA_VERSION="21" setup_java

  msg_info "Setting up LanguageTool"
  RELEASE=$(curl -fsSL https://languagetool.org/download/ | grep -oP 'LanguageTool-\K[0-9]+\.[0-9]+(\.[0-9]+)?(?=\.zip)' | sort -V | tail -n1)
  download_file "https://languagetool.org/download/LanguageTool-stable.zip" /tmp/LanguageTool-stable.zip
  unzip -q /tmp/LanguageTool-stable.zip -d /opt
  mv /opt/LanguageTool-*/ /opt/LanguageTool/
  download_file "https://dl.fbaipublicfiles.com/fasttext/supervised-models/lid.176.bin" /opt/lid.176.bin
  rm -f /tmp/LanguageTool-stable.zip

  ngram_dir=""
  lang_code=""
  max_attempts=3
  attempt=0

  while [[ $attempt -lt $max_attempts ]]; do
    read -r -p "${TAB3}Enter language code (en, de, es, fr, nl) to download ngrams or press ENTER to skip: " lang_code

    if [[ -z "$lang_code" ]]; then
      break
    fi

    if [[ "$lang_code" =~ [[:space:]] ]]; then
      ((attempt++))
      remaining=$((max_attempts - attempt))
      if [[ $remaining -gt 0 ]]; then
        msg_error "Please enter only ONE language code. You have $remaining attempt(s) remaining."
      else
        msg_error "Maximum attempts reached. Continuing without ngrams."
        lang_code=""
      fi
      continue
    fi
    break
  done

  if [[ -n "$lang_code" ]]; then
    if [[ "$lang_code" =~ ^(en|de|es|fr|nl)$ ]]; then
      msg_info "Searching for $lang_code ngrams..."
      filename=$(curl -fsSL https://languagetool.org/download/ngram-data/ | grep -oP "ngrams-${lang_code}-[0-9]+\.zip" | sort -uV | tail -n1)

      if [[ -n "$filename" ]]; then
        msg_info "Downloading $filename"
        download_file "https://languagetool.org/download/ngram-data/${filename}" "/tmp/${filename}"

        mkdir -p /opt/ngrams
        msg_info "Extracting $lang_code ngrams to /opt/ngrams"
        unzip -q "/tmp/${filename}" -d /opt/ngrams
        rm "/tmp/${filename}"

        ngram_dir="/opt/ngrams"
        msg_ok "Installed $lang_code ngrams"
      else
        msg_info "No ngram file found for ${lang_code}"
      fi
    else
      msg_error "Invalid language code: $lang_code"
    fi
  fi

  cat << EOF > /opt/LanguageTool/server.properties
fasttextModel=/opt/lid.176.bin
fasttextBinary=/usr/bin/fasttext
EOF
  if [[ -n "$ngram_dir" ]]; then
    echo "languageModel=/opt/ngrams" >> /opt/LanguageTool/server.properties
  fi
  echo "${RELEASE}" > ~/.languagetool
  msg_ok "Setup LanguageTool"

  msg_info "Creating Service"
  cat << 'EOF' > /etc/systemd/system/language-tool.service
[Unit]
Description=LanguageTool Service
After=network.target

[Service]
WorkingDirectory=/opt/LanguageTool
ExecStart=java -cp languagetool-server.jar org.languagetool.server.HTTPServer --config server.properties --public --allow-origin "*"
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now language-tool
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8081/v2${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/LanguageTool ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  RELEASE=$(curl -fsSL https://languagetool.org/download/ | grep -oP 'LanguageTool-\K[0-9]+\.[0-9]+(\.[0-9]+)?(?=\.zip)' | sort -V | tail -n1)
  if [[ "${RELEASE}" != "$(cat ~/.languagetool 2> /dev/null)" ]] || [[ ! -f ~/.languagetool ]]; then
    msg_info "Stopping Service"
    systemctl stop language-tool
    msg_ok "Stopped Service"

    msg_info "Creating Backup"
    cp /opt/LanguageTool/server.properties /opt/server.properties
    msg_ok "Created Backup"

    msg_info "Updating LanguageTool"
    rm -rf /opt/LanguageTool
    download_file "https://languagetool.org/download/LanguageTool-stable.zip" /tmp/LanguageTool-stable.zip
    unzip -q /tmp/LanguageTool-stable.zip -d /opt
    mv /opt/LanguageTool-*/ /opt/LanguageTool/
    mv /opt/server.properties /opt/LanguageTool/server.properties
    rm -f /tmp/LanguageTool-stable.zip
    echo "${RELEASE}" > ~/.languagetool
    msg_ok "Updated LanguageTool"

    msg_info "Starting Service"
    systemctl start language-tool
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  else
    msg_ok "No update required. ${APP} is already at v${RELEASE}"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
