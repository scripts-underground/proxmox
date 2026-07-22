#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://signoz.io/ | Github: https://github.com/SigNoz/signoz

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="SigNoz"
var_tags="${var_tags:-notes}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    apt-transport-https \
    ca-certificates
  msg_ok "Installed Dependencies"

  JAVA_VERSION="21" setup_java

  msg_info "Setting up ClickHouse"
  curl -fsSL "https://packages.clickhouse.com/rpm/lts/repodata/repomd.xml.key" | gpg --dearmor -o /usr/share/keyrings/clickhouse-keyring.gpg
  cat << EOF > /etc/apt/sources.list.d/clickhouse.sources
Types: deb
URIs: https://packages.clickhouse.com/deb
Suites: stable
Components: main
Architectures: $(get_system_arch)
Signed-By: /usr/share/keyrings/clickhouse-keyring.gpg
EOF
  $STD apt update
  export DEBIAN_FRONTEND=noninteractive
  $STD apt install -y clickhouse-server clickhouse-client
  msg_ok "Setup ClickHouse"

  msg_info "Setting up Zookeeper"
  ZOOURL=$(curl -fsSL https://dlcdn.apache.org/zookeeper/current/ | grep -o 'apache-zookeeper-[0-9.]\+-bin\.tar\.gz' | head -n1)
  curl -fsSL "https://dlcdn.apache.org/zookeeper/current/$ZOOURL" -o ~/zookeeper.tar.gz
  tar -xzf "$HOME/zookeeper.tar.gz" -C "$HOME"
  mkdir -p /opt/zookeeper
  mkdir -p /var/lib/zookeeper
  mkdir -p /var/log/zookeeper
  cp -r ~/apache-zookeeper-*-bin/* /opt/zookeeper

  cat << EOF > /opt/zookeeper/conf/zoo.cfg
tickTime=2000
dataDir=/var/lib/zookeeper
clientPort=2181
admin.serverPort=3181
EOF

  cat << EOF > /opt/zookeeper/conf/zoo.env
ZOO_LOG_DIR=/var/log/zookeeper
EOF

  cat << EOF > /etc/systemd/system/zookeeper.service
[Unit]
Description=Zookeeper
Documentation=http://zookeeper.apache.org

[Service]
EnvironmentFile=/opt/zookeeper/conf/zoo.env
Type=forking
WorkingDirectory=/opt/zookeeper
ExecStart=/opt/zookeeper/bin/zkServer.sh start /opt/zookeeper/conf/zoo.cfg
ExecStop=/opt/zookeeper/bin/zkServer.sh stop /opt/zookeeper/conf/zoo.cfg
ExecReload=/opt/zookeeper/bin/zkServer.sh restart /opt/zookeeper/conf/zoo.cfg
TimeoutSec=30
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now zookeeper
  msg_ok "Setup Zookeeper"

  msg_info "Configuring ClickHouse"
  cat << EOF > /etc/clickhouse-server/config.d/cluster.xml
<clickhouse replace="true">
    <distributed_ddl>
        <path>/clickhouse/task_queue/ddl</path>
    </distributed_ddl>
    <remote_servers>
        <cluster>
            <shard>
                <replica>
                    <host>127.0.0.1</host>
                    <port>9000</port>
                </replica>
            </shard>
        </cluster>
    </remote_servers>
    <zookeeper>
        <node>
            <host>127.0.0.1</host>
            <port>2181</port>
        </node>
    </zookeeper>
    <macros>
        <shard>01</shard>
        <replica>01</replica>
    </macros>
</clickhouse>
EOF
  systemctl enable -q --now clickhouse-server
  msg_ok "Configured ClickHouse"

  fetch_and_deploy_gh_release "signoz-schema-migrator" "SigNoz/signoz-otel-collector" "prebuild" "latest" "/opt/signoz-schema-migrator" "signoz-schema-migrator_linux_$(get_system_arch).tar.gz"

  msg_info "Running ClickHouse migrations"
  cd /opt/signoz-schema-migrator/bin || exit
  $STD ./signoz-schema-migrator sync --dsn="tcp://localhost:9000?password=" --replication=true --up=
  $STD ./signoz-schema-migrator async --dsn="tcp://localhost:9000?password=" --replication=true --up=
  msg_ok "ClickHouse Migrations Completed"

  fetch_and_deploy_gh_release "signoz" "SigNoz/signoz" "prebuild" "latest" "/opt/signoz" "signoz-community_linux_$(get_system_arch).tar.gz"

  msg_info "Setting up SigNoz"
  mkdir -p /var/lib/signoz
  cat << EOF > /opt/signoz/conf/systemd.env
SIGNOZ_INSTRUMENTATION_LOGS_LEVEL=info
INVITE_EMAIL_TEMPLATE=/opt/signoz/templates/invitation_email_template.html
SIGNOZ_SQLSTORE_SQLITE_PATH=/var/lib/signoz/signoz.db
SIGNOZ_WEB_ENABLED=true
SIGNOZ_WEB_DIRECTORY=/opt/signoz/web
SIGNOZ_JWT_SECRET=secret
SIGNOZ_ALERTMANAGER_PROVIDER=signoz
SIGNOZ_TELEMETRYSTORE_PROVIDER=clickhouse
SIGNOZ_TELEMETRYSTORE_CLICKHOUSE_DSN=tcp://localhost:9000?password=
DOT_METRICS_ENABLED=true
EOF

  cat << EOF > /etc/systemd/system/signoz.service
[Unit]
Description=SigNoz
Documentation=https://signoz.io/docs
After=clickhouse-server.service

[Service]
Type=simple
KillMode=mixed
Restart=on-failure
WorkingDirectory=/opt/signoz
EnvironmentFile=/opt/signoz/conf/systemd.env
ExecStart=/opt/signoz/bin/signoz server

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now signoz
  msg_ok "Setup Signoz"

  fetch_and_deploy_gh_release "signoz-otel-collector" "SigNoz/signoz-otel-collector" "prebuild" "latest" "/opt/signoz-otel-collector" "signoz-otel-collector_linux_$(get_system_arch).tar.gz"

  msg_info "Setting up SigNoz OTel Collector"
  mkdir -p /var/lib/signoz-otel-collector
  cat << EOF > /opt/signoz-otel-collector/conf/config.yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
        max_recv_msg_size_mib: 16
      http:
        endpoint: 0.0.0.0:4318
  jaeger:
    protocols:
      grpc:
        endpoint: 0.0.0.0:14250
      thrift_http:
        endpoint: 0.0.0.0:14268
  httplogreceiver/heroku:
    endpoint: 0.0.0.0:8081
    source: heroku
  httplogreceiver/json:
    endpoint: 0.0.0.0:8082
    source: json
processors:
  batch:
    send_batch_size: 50000
    timeout: 1s
  signozspanmetrics/delta:
    metrics_exporter: signozclickhousemetrics
    latency_histogram_buckets: [100us, 1ms, 2ms, 6ms, 10ms, 50ms, 100ms, 250ms, 500ms, 1000ms, 1400ms, 2000ms, 5s, 10s, 20s, 40s, 60s]
    dimensions_cache_size: 100000
    dimensions:
      - name: service.namespace
        default: default
      - name: deployment.environment
        default: default
      - name: signoz.collector.id
    aggregation_temporality: AGGREGATION_TEMPORALITY_DELTA
extensions:
  health_check:
    endpoint: 0.0.0.0:13133
  zpages:
    endpoint: localhost:55679
  pprof:
    endpoint: localhost:1777
exporters:
  clickhousetraces:
    datasource: tcp://localhost:9000/signoz_traces?password=
    use_new_schema: true
  signozclickhousemetrics:
    dsn: tcp://localhost:9000/signoz_metrics?password=
    timeout: 45s
  clickhouselogsexporter:
    dsn: tcp://localhost:9000/signoz_logs?password=
    timeout: 10s
    use_new_schema: true
  metadataexporter:
    dsn: tcp://localhost:9000/signoz_metadata?password=
    timeout: 10s
    tenant_id: default
    cache:
      provider: in_memory
service:
  telemetry:
    logs:
      encoding: json
  extensions: [health_check, zpages, pprof]
  pipelines:
    traces:
      receivers: [otlp, jaeger]
      processors: [signozspanmetrics/delta, batch]
      exporters: [clickhousetraces, metadataexporter]
    metrics:
      receivers: [otlp]
      processors: [batch]
      exporters: [metadataexporter, signozclickhousemetrics]
    logs:
      receivers: [otlp, httplogreceiver/heroku, httplogreceiver/json]
      processors: [batch]
      exporters: [clickhouselogsexporter, metadataexporter]
EOF

  cat << EOF > /opt/signoz-otel-collector/conf/opamp.yaml
server_endpoint: ws://127.0.0.1:4320/v1/opamp
EOF

  cat << EOF > /etc/systemd/system/signoz-otel-collector.service
[Unit]
Description=SigNoz OTel Collector
Documentation=https://signoz.io/docs
After=clickhouse-server.service

[Service]
Type=simple
KillMode=mixed
Restart=on-failure
WorkingDirectory=/opt/signoz-otel-collector
ExecStart=/opt/signoz-otel-collector/bin/signoz-otel-collector --config=/opt/signoz-otel-collector/conf/config.yaml --manager-config=/opt/signoz-otel-collector/conf/opamp.yaml --copy-path=/var/lib/signoz-otel-collector/config.yaml

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now signoz-otel-collector
  rm -rf ~/zookeeper.tar.gz
  rm -rf ~/apache-zookeeper-*-bin
  msg_ok "Setup Signoz OTel Collector"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8080${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/signoz ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "signoz" "SigNoz/signoz"; then
    msg_info "Stopping Services"
    systemctl stop signoz
    systemctl stop signoz-otel-collector
    msg_ok "Stopped Services"

    fetch_and_deploy_gh_release "signoz" "SigNoz/signoz" "prebuild" "latest" "/opt/signoz" "signoz-community_linux_$(get_system_arch).tar.gz"
    fetch_and_deploy_gh_release "signoz-otel-collector" "SigNoz/signoz-otel-collector" "prebuild" "latest" "/opt/signoz-otel-collector" "signoz-otel-collector_linux_$(get_system_arch).tar.gz"
    fetch_and_deploy_gh_release "signoz-schema-migrator" "SigNoz/signoz-otel-collector" "prebuild" "latest" "/opt/signoz-schema-migrator" "signoz-schema-migrator_linux_$(get_system_arch).tar.gz"

    msg_info "Updating SigNoz"
    cd /opt/signoz-schema-migrator/bin || exit
    $STD ./signoz-schema-migrator sync --dsn="tcp://localhost:9000?password=" --replication=true --up=
    $STD ./signoz-schema-migrator async --dsn="tcp://localhost:9000?password=" --replication=true --up=
    msg_ok "Updated SigNoz"

    msg_info "Starting Services"
    systemctl start signoz-otel-collector
    systemctl start signoz
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
