#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Michel Roegl-Brunner (michelroegl-brunner)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://guacamole.apache.org/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Apache-Guacamole"
var_tags="${var_tags:-webserver;remote}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    build-essential \
    libcairo2-dev \
    libjpeg62-turbo-dev \
    libpng-dev \
    libtool-bin \
    uuid-dev \
    libvncserver-dev \
    freerdp3-dev \
    libssh2-1-dev \
    libtelnet-dev \
    libwebsockets-dev \
    libpulse-dev \
    libvorbis-dev \
    libwebp-dev \
    libssl-dev \
    libpango1.0-dev \
    libswscale-dev \
    libavcodec-dev \
    libavutil-dev \
    libavformat-dev
  msg_ok "Installed Dependencies"

  JAVA_VERSION="17" setup_java
  setup_mariadb
  MARIADB_DB_NAME="guacamole_db" MARIADB_DB_USER="guacamole_user" setup_mariadb_db

  msg_info "Setup Apache Tomcat"
  TOMCAT_VERSION=$(curl -fsSL https://dlcdn.apache.org/tomcat/tomcat-9/ | grep -oP '(?<=href=")v[^"/]+(?=/")' | sed 's/^v//' | sort -V | tail -n1)
  mkdir -p /opt/apache-guacamole/{tomcat9,server}
  curl -fsSL "https://dlcdn.apache.org/tomcat/tomcat-9/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz" | tar -xz -C /opt/apache-guacamole/tomcat9 --strip-components=1
  useradd -r -d /opt/apache-guacamole/tomcat9 -s /bin/false tomcat
  chown -R tomcat: /opt/apache-guacamole/tomcat9
  chmod -R g+r /opt/apache-guacamole/tomcat9/conf
  chmod g+x /opt/apache-guacamole/tomcat9/conf
  echo "${TOMCAT_VERSION}" > ~/.guacamole_tomcat
  msg_ok "Setup Apache Tomcat ${TOMCAT_VERSION}"

  msg_info "Setup Apache Guacamole"
  mkdir -p /etc/guacamole/{extensions,lib}
  GUAC_SERVER_VERSION=$(curl -fsSL https://api.github.com/repos/apache/guacamole-server/tags | jq -r '.[].name' | grep -v -- '-RC' | head -n 1)
  GUAC_CLIENT_VERSION=$(curl -fsSL https://api.github.com/repos/apache/guacamole-client/tags | jq -r '.[].name' | grep -v -- '-RC' | head -n 1)
  MYSQL_CONNECTOR_VERSION=$(curl -fsSL "https://repo1.maven.org/maven2/com/mysql/mysql-connector-j/maven-metadata.xml" | grep -oP '<latest>\K[^<]+')
  curl -fsSL "https://api.github.com/repos/apache/guacamole-server/tarball/refs/tags/${GUAC_SERVER_VERSION}" | tar -xz --strip-components=1 -C /opt/apache-guacamole/server
  cd /opt/apache-guacamole/server || exit
  export CPPFLAGS="-Wno-error=deprecated-declarations"
  $STD autoreconf -fi
  $STD ./configure --with-init-dir=/etc/init.d --enable-allow-freerdp-snapshots
  $STD make
  $STD make install
  $STD ldconfig
  echo "${GUAC_SERVER_VERSION}" > ~/.guacamole_server
  curl -fsSL "https://downloads.apache.org/guacamole/${GUAC_CLIENT_VERSION}/binary/guacamole-${GUAC_CLIENT_VERSION}.war" -o /opt/apache-guacamole/tomcat9/webapps/guacamole.war
  echo "${GUAC_CLIENT_VERSION}" > ~/.guacamole_client
  curl -fsSL "https://repo1.maven.org/maven2/com/mysql/mysql-connector-j/${MYSQL_CONNECTOR_VERSION}/mysql-connector-j-${MYSQL_CONNECTOR_VERSION}.jar" -o /etc/guacamole/lib/mysql-connector-j.jar
  echo "${MYSQL_CONNECTOR_VERSION}" > ~/.guacamole_mysql_connector
  cd /root || exit
  curl -fsSL "https://downloads.apache.org/guacamole/${GUAC_SERVER_VERSION}/binary/guacamole-auth-jdbc-${GUAC_SERVER_VERSION}.tar.gz" -o /root/guacamole-auth-jdbc-"${GUAC_SERVER_VERSION}".tar.gz
  $STD tar -xf /root/guacamole-auth-jdbc-"${GUAC_SERVER_VERSION}".tar.gz
  mv /root/guacamole-auth-jdbc-"${GUAC_SERVER_VERSION}"/mysql/guacamole-auth-jdbc-mysql-"${GUAC_SERVER_VERSION}".jar /etc/guacamole/extensions/
  echo "${GUAC_SERVER_VERSION}" > ~/.guacamole_auth_jdbc
  msg_ok "Setup Apache Guacamole"

  msg_info "Importing Database Schema"
  cd /root/guacamole-auth-jdbc-"${GUAC_SERVER_VERSION}"/mysql/schema || exit
  cat *.sql | mariadb -u root "${MARIADB_DB_NAME}"
  cat << EOF > /etc/guacamole/guacamole.properties
mysql-hostname: 127.0.0.1
mysql-port: 3306
mysql-database: ${MARIADB_DB_NAME}
mysql-username: ${MARIADB_DB_USER}
mysql-password: ${MARIADB_DB_PASS}
EOF
  rm -rf /root/guacamole-auth-jdbc-"${GUAC_SERVER_VERSION}"{,.tar.gz}
  msg_ok "Imported Database Schema"

  msg_info "Setup Service"
  cat << EOF > /etc/guacamole/guacd.conf
[server]
bind_host = 127.0.0.1
bind_port = 4822
EOF
  JAVA_HOME=$(update-alternatives --query javadoc | grep Value: | head -n1 | sed 's/Value: //' | sed 's@bin/javadoc$@@')
  cat << EOF > /etc/systemd/system/tomcat.service
[Unit]
Description=Apache Tomcat Web Application Container
After=network.target
[Service]
Type=forking
Environment="JAVA_HOME=${JAVA_HOME}"
Environment="CATALINA_PID=/opt/apache-guacamole/tomcat9/temp/tomcat.pid"
Environment="CATALINA_HOME=/opt/apache-guacamole/tomcat9/"
Environment="CATALINA_BASE=/opt/apache-guacamole/tomcat9/"
Environment="CATALINA_OPTS=-Xms512M -Xmx1024M -server -XX:+UseParallelGC"
Environment="JAVA_OPTS=-Djava.awt.headless=true -Djava.security.egd=file:/dev/./urandom"
ExecStart=/opt/apache-guacamole/tomcat9/bin/startup.sh
ExecStop=/opt/apache-guacamole/tomcat9/bin/shutdown.sh
User=tomcat
Group=tomcat
UMask=0007
RestartSec=10
Restart=always
[Install]
WantedBy=multi-user.target
EOF
  cat << EOF > /etc/systemd/system/guacd.service
[Unit]
Description=Guacamole Proxy Daemon (guacd)
After=mysql.service tomcat.service
Requires=mysql.service tomcat.service
[Service]
Type=forking
ExecStart=/etc/init.d/guacd start
ExecStop=/etc/init.d/guacd stop
ExecReload=/etc/init.d/guacd restart
PIDFile=/var/run/guacd.pid
[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now mysql tomcat guacd
  msg_ok "Setup Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8080/guacamole${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/apache-guacamole ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  LATEST_TOMCAT=$(curl -fsSL https://dlcdn.apache.org/tomcat/tomcat-9/ | grep -oP '(?<=href=")v[^"/]+(?=/")' | sed 's/^v//' | sort -V | tail -n1)
  LATEST_SERVER=$(curl -fsSL https://api.github.com/repos/apache/guacamole-server/tags | jq -r '.[].name' | grep -v -- '-RC' | head -n 1)
  LATEST_CLIENT=$(curl -fsSL https://api.github.com/repos/apache/guacamole-client/tags | jq -r '.[].name' | grep -v -- '-RC' | head -n 1)
  LATEST_MYSQL_CONNECTOR=$(curl -fsSL "https://repo1.maven.org/maven2/com/mysql/mysql-connector-j/maven-metadata.xml" | grep -oP '<latest>\K[^<]+')

  CURRENT_TOMCAT=$(cat ~/.guacamole_tomcat 2> /dev/null || echo "unknown")
  CURRENT_SERVER=$(cat ~/.guacamole_server 2> /dev/null || echo "unknown")
  CURRENT_CLIENT=$(cat ~/.guacamole_client 2> /dev/null || echo "unknown")
  CURRENT_MYSQL_CONNECTOR=$(cat ~/.guacamole_mysql_connector 2> /dev/null || echo "unknown")

  UPDATE_NEEDED=false
  [[ "$CURRENT_TOMCAT" != "$LATEST_TOMCAT" ]] && UPDATE_NEEDED=true
  [[ "$CURRENT_SERVER" != "$LATEST_SERVER" ]] && UPDATE_NEEDED=true
  [[ "$CURRENT_CLIENT" != "$LATEST_CLIENT" ]] && UPDATE_NEEDED=true
  [[ "$CURRENT_MYSQL_CONNECTOR" != "$LATEST_MYSQL_CONNECTOR" ]] && UPDATE_NEEDED=true

  if [[ "$UPDATE_NEEDED" == "false" ]]; then
    msg_ok "All components are up to date"
    exit
  fi

  JAVA_VERSION="17" setup_java

  msg_info "Stopping Services"
  systemctl stop guacd tomcat
  msg_ok "Stopped Services"

  if [[ "$CURRENT_TOMCAT" != "$LATEST_TOMCAT" ]]; then
    msg_info "Updating Tomcat (${CURRENT_TOMCAT} → ${LATEST_TOMCAT})"
    cp -a /opt/apache-guacamole/tomcat9/conf /tmp/tomcat-conf-backup
    curl -fsSL "https://dlcdn.apache.org/tomcat/tomcat-9/v${LATEST_TOMCAT}/bin/apache-tomcat-${LATEST_TOMCAT}.tar.gz" | tar -xz -C /opt/apache-guacamole/tomcat9 --strip-components=1 --exclude='conf/*'
    cp -a /tmp/tomcat-conf-backup/* /opt/apache-guacamole/tomcat9/conf/
    rm -rf /tmp/tomcat-conf-backup
    chown -R tomcat: /opt/apache-guacamole/tomcat9
    echo "${LATEST_TOMCAT}" > ~/.guacamole_tomcat
    msg_ok "Updated Tomcat"
  else
    msg_ok "Tomcat already up to date (${CURRENT_TOMCAT})"
  fi

  if [[ "$CURRENT_SERVER" != "$LATEST_SERVER" ]]; then
    msg_info "Updating Guacamole Server (${CURRENT_SERVER} → ${LATEST_SERVER})"
    rm -rf /opt/apache-guacamole/server/*
    curl -fsSL "https://api.github.com/repos/apache/guacamole-server/tarball/refs/tags/${LATEST_SERVER}" | tar -xz --strip-components=1 -C /opt/apache-guacamole/server
    cd /opt/apache-guacamole/server || exit
    export CPPFLAGS="-Wno-error=deprecated-declarations"
    $STD autoreconf -fi
    $STD ./configure --with-init-dir=/etc/init.d --enable-allow-freerdp-snapshots
    $STD make
    $STD make install
    $STD ldconfig
    echo "${LATEST_SERVER}" > ~/.guacamole_server
    msg_ok "Updated Guacamole Server"

    msg_info "Updating Guacamole Auth JDBC"
    rm -f /etc/guacamole/extensions/guacamole-auth-jdbc-mysql-*.jar
    curl -fsSL "https://downloads.apache.org/guacamole/${LATEST_SERVER}/binary/guacamole-auth-jdbc-${LATEST_SERVER}.tar.gz" -o /tmp/guacamole-auth-jdbc.tar.gz
    $STD tar -xf /tmp/guacamole-auth-jdbc.tar.gz -C /tmp
    mv /tmp/guacamole-auth-jdbc-"${LATEST_SERVER}"/mysql/guacamole-auth-jdbc-mysql-"${LATEST_SERVER}".jar /etc/guacamole/extensions/
    echo "${LATEST_SERVER}" > ~/.guacamole_auth_jdbc
    msg_ok "Updated Guacamole Auth JDBC"
  else
    msg_ok "Guacamole Server already up to date (${CURRENT_SERVER})"
  fi

  if [[ "$CURRENT_CLIENT" != "$LATEST_CLIENT" ]]; then
    msg_info "Updating Guacamole Client (${CURRENT_CLIENT} → ${LATEST_CLIENT})"
    curl -fsSL "https://downloads.apache.org/guacamole/${LATEST_CLIENT}/binary/guacamole-${LATEST_CLIENT}.war" -o /opt/apache-guacamole/tomcat9/webapps/guacamole.war
    echo "${LATEST_CLIENT}" > ~/.guacamole_client
    msg_ok "Updated Guacamole Client"
  else
    msg_ok "Guacamole Client already up to date (${CURRENT_CLIENT})"
  fi

  if [[ "$CURRENT_MYSQL_CONNECTOR" != "$LATEST_MYSQL_CONNECTOR" ]]; then
    msg_info "Updating MySQL Connector (${CURRENT_MYSQL_CONNECTOR} → ${LATEST_MYSQL_CONNECTOR})"
    curl -fsSL "https://repo1.maven.org/maven2/com/mysql/mysql-connector-j/${LATEST_MYSQL_CONNECTOR}/mysql-connector-j-${LATEST_MYSQL_CONNECTOR}.jar" -o /etc/guacamole/lib/mysql-connector-j.jar
    echo "${LATEST_MYSQL_CONNECTOR}" > ~/.guacamole_mysql_connector
    msg_ok "Updated MySQL Connector"
  else
    msg_ok "MySQL Connector already up to date (${CURRENT_MYSQL_CONNECTOR})"
  fi

  if [[ "$CURRENT_SERVER" != "$LATEST_SERVER" ]]; then
    msg_info "Applying MySQL Schema Upgrades"
    cd /tmp/guacamole-auth-jdbc-"${LATEST_SERVER}"/mysql/schema/upgrade/ || exit
    if compgen -G "upgrade-pre-*.sql" > /dev/null 2>&1; then
      mapfile -t UPGRADE_FILES < <(ls -1 upgrade-pre-*.sql 2> /dev/null | sort -V)
      for SQL_FILE in "${UPGRADE_FILES[@]}"; do
        FILE_VERSION=$(echo "${SQL_FILE}" | grep -oP 'upgrade-pre-\K[0-9\.]+(?=\.)')
        if [[ $(echo -e "${FILE_VERSION}\n${CURRENT_SERVER}" | sort -V | head -n1) == "${CURRENT_SERVER}" && "${FILE_VERSION}" != "${CURRENT_SERVER}" ]]; then
          msg_info "Applying schema patch: ${SQL_FILE}"
          mysql -u root guacamole_db < "${SQL_FILE}" 2> /dev/null || msg_warn "Failed to apply ${SQL_FILE} (may already be applied)"
        fi
      done
    fi
    rm -rf /tmp/guacamole-auth-jdbc*
    msg_ok "MySQL Schema updated"
  fi

  if compgen -G "/etc/guacamole/extensions/guacamole-auth-totp-*.jar" > /dev/null; then
    msg_info "Updating TOTP Extension"
    rm -f /etc/guacamole/extensions/guacamole-auth-totp-*.jar
    curl -fsSL "https://downloads.apache.org/guacamole/${LATEST_SERVER}/binary/guacamole-auth-totp-${LATEST_SERVER}.tar.gz" -o /tmp/guacamole-auth-totp.tar.gz
    $STD tar -xf /tmp/guacamole-auth-totp.tar.gz -C /tmp
    mv /tmp/guacamole-auth-totp-"${LATEST_SERVER}"/guacamole-auth-totp-"${LATEST_SERVER}".jar /etc/guacamole/extensions/
    chmod 664 /etc/guacamole/extensions/guacamole-auth-totp-"${LATEST_SERVER}".jar
    rm -rf /tmp/guacamole-auth-totp*
    msg_ok "Updated TOTP Extension"
  fi

  if compgen -G "/etc/guacamole/extensions/guacamole-auth-duo-*.jar" > /dev/null; then
    msg_info "Updating DUO Extension"
    rm -f /etc/guacamole/extensions/guacamole-auth-duo-*.jar
    curl -fsSL "https://downloads.apache.org/guacamole/${LATEST_SERVER}/binary/guacamole-auth-duo-${LATEST_SERVER}.tar.gz" -o /tmp/guacamole-auth-duo.tar.gz
    $STD tar -xf /tmp/guacamole-auth-duo.tar.gz -C /tmp
    mv /tmp/guacamole-auth-duo-"${LATEST_SERVER}"/guacamole-auth-duo-"${LATEST_SERVER}".jar /etc/guacamole/extensions/
    chmod 664 /etc/guacamole/extensions/guacamole-auth-duo-"${LATEST_SERVER}".jar
    rm -rf /tmp/guacamole-auth-duo*
    msg_ok "Updated DUO Extension"
  fi

  if compgen -G "/etc/guacamole/extensions/guacamole-auth-ldap-*.jar" > /dev/null; then
    msg_info "Updating LDAP Extension"
    rm -f /etc/guacamole/extensions/guacamole-auth-ldap-*.jar
    curl -fsSL "https://downloads.apache.org/guacamole/${LATEST_SERVER}/binary/guacamole-auth-ldap-${LATEST_SERVER}.tar.gz" -o /tmp/guacamole-auth-ldap.tar.gz
    $STD tar -xf /tmp/guacamole-auth-ldap.tar.gz -C /tmp
    mv /tmp/guacamole-auth-ldap-"${LATEST_SERVER}"/guacamole-auth-ldap-"${LATEST_SERVER}".jar /etc/guacamole/extensions/
    chmod 664 /etc/guacamole/extensions/guacamole-auth-ldap-"${LATEST_SERVER}".jar
    rm -rf /tmp/guacamole-auth-ldap*
    msg_ok "Updated LDAP Extension"
  fi

  if compgen -G "/etc/guacamole/extensions/guacamole-auth-quickconnect-*.jar" > /dev/null; then
    msg_info "Updating Quick Connect Extension"
    rm -f /etc/guacamole/extensions/guacamole-auth-quickconnect-*.jar
    curl -fsSL "https://downloads.apache.org/guacamole/${LATEST_SERVER}/binary/guacamole-auth-quickconnect-${LATEST_SERVER}.tar.gz" -o /tmp/guacamole-auth-quickconnect.tar.gz
    $STD tar -xf /tmp/guacamole-auth-quickconnect.tar.gz -C /tmp
    mv /tmp/guacamole-auth-quickconnect-"${LATEST_SERVER}"/guacamole-auth-quickconnect-"${LATEST_SERVER}".jar /etc/guacamole/extensions/
    chmod 664 /etc/guacamole/extensions/guacamole-auth-quickconnect-"${LATEST_SERVER}".jar
    rm -rf /tmp/guacamole-auth-quickconnect*
    msg_ok "Updated Quick Connect Extension"
  fi

  if compgen -G "/etc/guacamole/extensions/guacamole-history-recording-storage-*.jar" > /dev/null; then
    msg_info "Updating History Recording Storage Extension"
    rm -f /etc/guacamole/extensions/guacamole-history-recording-storage-*.jar
    curl -fsSL "https://downloads.apache.org/guacamole/${LATEST_SERVER}/binary/guacamole-history-recording-storage-${LATEST_SERVER}.tar.gz" -o /tmp/guacamole-history-recording-storage.tar.gz
    $STD tar -xf /tmp/guacamole-history-recording-storage.tar.gz -C /tmp
    mv /tmp/guacamole-history-recording-storage-"${LATEST_SERVER}"/guacamole-history-recording-storage-"${LATEST_SERVER}".jar /etc/guacamole/extensions/
    chmod 664 /etc/guacamole/extensions/guacamole-history-recording-storage-"${LATEST_SERVER}".jar
    rm -rf /tmp/guacamole-history-recording-storage*
    msg_ok "Updated History Recording Storage Extension"
  fi

  msg_info "Resetting permissions"
  mkdir -p /var/guacamole
  chown daemon:daemon /var/guacamole
  mkdir -p /home/daemon/.config/freerdp
  chown daemon:daemon /home/daemon/.config/freerdp
  msg_ok "Permissions reset"

  msg_info "Starting Services"
  systemctl daemon-reload
  systemctl start tomcat guacd
  msg_ok "Started Services"
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
